import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// Состояние приложения целиком: очередь, настройки, папка экспорта, ход работы.
@MainActor
@Observable
final class AppModel {
    private static let settingsKey = "conversionSettings"

    var items: [ConversionItem] = []
    var settings: ConversionSettings {
        didSet {
            normalizeSettings()
            persistSettings()
        }
    }
    var isRunning = false
    /// Сообщение уровня приложения: папка не выбрана, итог прогона и т. п.
    var banner: Banner?

    let exportFolder = ExportFolder()

    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private let cancellation = CancellationFlag()

    struct Banner: Equatable {
        enum Kind { case info, warning }
        var kind: Kind
        var text: String
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let stored = try? JSONDecoder().decode(ConversionSettings.self, from: data) {
            settings = stored
        } else {
            settings = ConversionSettings()
        }
    }

    // MARK: - Очередь

    var pendingCount: Int {
        items.filter { !$0.isFinished }.count
    }

    var doneItems: [ConversionItem] {
        items.filter { $0.status == .done }
    }

    var failedCount: Int {
        items.filter { $0.errorText != nil }.count
    }

    /// Общий прогресс по очереди — от 0 до 1.
    var progress: Double {
        guard !items.isEmpty else { return 0 }
        let sum = items.reduce(0.0) { total, item in
            switch item.status {
            case .done, .skipped, .failed, .cancelled: return total + 1
            case .running: return total + item.progress
            case .waiting: return total
            }
        }
        return sum / Double(items.count)
    }

    func add(urls: [URL]) {
        let expanded = Self.expand(urls)
        let existing = Set(items.map { $0.sourceURL.standardizedFileURL })
        let fresh = expanded
            .map { $0.standardizedFileURL }
            .filter { !existing.contains($0) }
        guard !fresh.isEmpty else { return }

        let newItems = fresh.map { ConversionItem(sourceURL: $0) }
        items.append(contentsOf: newItems)
        probe(newItems)
    }

    func addFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Добавить"
        panel.message = "Выберите звуковые файлы или папку"
        panel.allowedContentTypes = [.audio, .movie]

        guard panel.runModal() == .OK else { return }
        add(urls: panel.urls)
    }

    func remove(_ item: ConversionItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        guard !isRunning else { return }
        items.removeAll()
        banner = nil
    }

    /// Подтягивает длительность и формат в фоне — очередь бывает на сотни файлов.
    private func probe(_ newItems: [ConversionItem]) {
        Task.detached(priority: .utility) {
            for item in newItems {
                let info = AudioProbe.probe(item.sourceURL)
                await MainActor.run { item.info = info }
            }
        }
    }

    /// Разворачивает папки в список файлов и отсеивает не-аудио.
    private static func expand(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        let manager = FileManager.default

        for url in urls {
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                let enumerator = manager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
                while let child = enumerator?.nextObject() as? URL {
                    if isSupported(child) { result.append(child) }
                }
            } else if isSupported(url) {
                result.append(url)
            }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Расширения, которые система звуковыми не считает, но мы читаем сами.
    private static let extraExtensions: Set<String> = ["ogg", "oga", "ogx"]

    static func isSupported(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        if extraExtensions.contains(fileExtension) { return true }
        guard let type = UTType(filenameExtension: fileExtension) else { return false }
        // Видеоконтейнеры берём тоже — из них вытаскивается звуковая дорожка.
        return type.conforms(to: .audio) || type.conforms(to: .movie)
    }

    // MARK: - Папка экспорта

    func chooseExportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать"
        panel.message = "Куда складывать готовые файлы"
        panel.directoryURL = exportFolder.url

        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportFolder.set(url)
        if banner?.kind == .warning { banner = nil }
    }

    func openExportFolder() {
        guard exportFolder.url != nil else {
            chooseExportFolder()
            return
        }
        exportFolder.revealInFinder(selecting: doneItems.compactMap { $0.outputURL })
    }

    // MARK: - Запуск

    var canStart: Bool {
        !isRunning && items.contains { !$0.isFinished }
    }

    func start() {
        guard canStart else { return }
        guard let folder = exportFolder.url else {
            banner = Banner(kind: .warning, text: "Сначала укажите папку экспорта")
            chooseExportFolder()
            return
        }

        banner = nil
        isRunning = true
        cancellation.reset()

        let queue = items.filter { !$0.isFinished }
        for item in queue {
            item.status = .waiting
            item.progress = 0
            item.outputURL = nil
        }

        let settings = settings
        let flag = cancellation
        let reserved = ReservedNames()

        worker = Task { [weak self] in
            await ConversionRunner.run(
                queue: queue, settings: settings, folder: folder,
                reserved: reserved, cancellation: flag
            )
            self?.finish()
        }
    }

    func cancel() {
        cancellation.cancel()
    }

    private func finish() {
        isRunning = false
        worker = nil

        let done = doneItems.count
        let failed = failedCount
        let skipped = items.filter { $0.status == .skipped }.count

        if failed > 0 {
            banner = Banner(
                kind: .warning,
                text: "Готово: \(done). Не удалось: \(failed)."
            )
        } else if skipped > 0 {
            banner = Banner(
                kind: .info,
                text: "Готово: \(done). Пропущено как существующие: \(skipped)."
            )
        } else if done > 0 {
            banner = Banner(kind: .info, text: "Готово: \(done).")
        }
    }

    /// Смена формата может сделать выбранное качество недопустимым —
    /// подтягиваем его к ближайшему разрешённому.
    private func normalizeSettings() {
        var fixed = settings
        if fixed.format == .aac, case .variable(let quality) = fixed.bitrate {
            let approximate = BitrateMode.variable(quality).approximateKilobits
            let nearest = BitrateMode.constantChoices.min {
                abs($0 - approximate) < abs($1 - approximate)
            } ?? 256
            fixed.bitrate = .constant(nearest)
        }
        if fixed.format.hasBitDepth {
            fixed.bitDepth = fixed.format.resolvedBitDepth(fixed.bitDepth)
        }
        if fixed != settings {
            settings = fixed
        }
    }

    private func persistSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
    }
}
