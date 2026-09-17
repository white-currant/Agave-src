import AppKit
import Foundation
import Observation

/// Папка экспорта живёт между запусками через закладку с областью безопасности —
/// без неё песочница забудет разрешение сразу после выхода.
///
/// Класс наблюдаемый: интерфейс читает `url` напрямую отсюда, и без этого
/// выбор папки не доходил бы до экрана.
@Observable
final class ExportFolder {
    @ObservationIgnored private static let bookmarkKey = "exportFolderBookmark"

    private(set) var url: URL?
    @ObservationIgnored private var accessedURL: URL?

    init() {
        restore()
    }

    deinit {
        accessedURL?.stopAccessingSecurityScopedResource()
    }

    var displayPath: String {
        guard let url else { return "" }
        var path = url.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        // NSHomeDirectory в песочнице указывает на контейнер, а не на папку
        // пользователя, поэтому настоящий путь берём у системы напрямую.
        if let home = Self.realHomeDirectory, path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    @ObservationIgnored
    private static let realHomeDirectory: String? = {
        guard let entry = getpwuid(getuid()) else { return nil }
        return String(cString: entry.pointee.pw_dir)
    }()

    var name: String {
        url?.lastPathComponent ?? "не выбрана"
    }

    /// Запоминает выбранную пользователем папку.
    func set(_ newURL: URL) {
        stopAccess()
        do {
            let bookmark = try newURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        } catch {
            // Даже если закладка не сохранилась, в текущем запуске папка работает.
        }
        url = newURL
        if newURL.startAccessingSecurityScopedResource() {
            accessedURL = newURL
        }
    }

    private func restore() {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }

        if resolved.startAccessingSecurityScopedResource() {
            accessedURL = resolved
        }
        url = resolved

        if isStale {
            set(resolved)
        }
    }

    private func stopAccess() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }

    /// Есть ли вообще право писать в папку.
    var isWritable: Bool {
        guard let url else { return false }
        return FileManager.default.isWritableFile(atPath: url.path)
    }

    /// Открывает саму папку в Finder.
    func openInFinder() {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    /// Открывает папку и подсвечивает в ней готовые файлы.
    func revealInFinder(selecting files: [URL]) {
        guard let url else { return }
        if files.isEmpty {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(files)
        }
    }
}
