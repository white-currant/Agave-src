import Foundation

/// Гоняет очередь файлов параллельно.
///
/// Кодирование — блокирующий вызов C-библиотек, поэтому оно уходит на собственную
/// диспетч-очередь, а не на кооперативный пул Swift: иначе несколько длинных
/// файлов забьют все потоки пула.
enum ConversionRunner {

    private static let encodingQueue = DispatchQueue(
        label: "com.yulion.agave.encoding",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// Сколько файлов молотим одновременно.
    static func laneCount(for fileCount: Int) -> Int {
        max(2, min(fileCount, ProcessInfo.processInfo.activeProcessorCount))
    }

    static func run(
        queue: [ConversionItem],
        settings: ConversionSettings,
        folder: URL,
        reserved: ReservedNames,
        cancellation: CancellationFlag
    ) async {
        let lanes = laneCount(for: queue.count)
        var next = 0

        await withTaskGroup(of: Void.self) { group in
            func schedule() {
                guard next < queue.count else { return }
                let item = queue[next]
                next += 1
                group.addTask {
                    await convert(
                        item, settings: settings, folder: folder,
                        reserved: reserved, cancellation: cancellation
                    )
                }
            }

            for _ in 0..<lanes { schedule() }
            while await group.next() != nil {
                schedule()
            }
        }
    }

    private static func convert(
        _ item: ConversionItem,
        settings: ConversionSettings,
        folder: URL,
        reserved: ReservedNames,
        cancellation: CancellationFlag
    ) async {
        let source = item.sourceURL

        if cancellation.isCancelled {
            await MainActor.run { item.status = .cancelled }
            return
        }
        await MainActor.run {
            item.status = .running
            item.progress = 0
        }

        let destination = await reserved.reserve(
            folder: folder,
            baseName: source.deletingPathExtension().lastPathComponent,
            fileExtension: settings.format.fileExtension,
            policy: settings.conflict
        )
        guard let destination else {
            await MainActor.run { item.status = .skipped }
            return
        }

        let reporter = ProgressReporter(item: item)

        do {
            try await blocking {
                try Transcoder.convert(
                    source: source,
                    destination: destination,
                    settings: settings,
                    onProgress: { reporter.report($0) },
                    isCancelled: { cancellation.isCancelled }
                )
            }
            await MainActor.run {
                item.progress = 1
                item.outputURL = destination
                item.status = .done
            }
        } catch is CancellationError {
            await MainActor.run { item.status = .cancelled }
        } catch {
            let text = (error as? ConversionError)?.errorDescription
                ?? error.localizedDescription
            await MainActor.run { item.status = .failed(text) }
        }
    }

    private static func blocking(_ body: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            encodingQueue.async {
                do {
                    try body()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Флаг отмены, безопасный для чтения из любого потока.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }

    func cancel() {
        lock.lock()
        flag = true
        lock.unlock()
    }

    func reset() {
        lock.lock()
        flag = false
        lock.unlock()
    }
}

/// Раздаёт имена выходных файлов так, чтобы два потока не забрали одно и то же.
actor ReservedNames {
    private var taken: Set<String> = []

    func reserve(
        folder: URL, baseName: String, fileExtension: String, policy: ConflictPolicy
    ) -> URL? {
        let manager = FileManager.default

        func candidate(_ suffix: String) -> URL {
            folder.appendingPathComponent("\(baseName)\(suffix).\(fileExtension)")
        }

        let plain = candidate("")
        if !manager.fileExists(atPath: plain.path), !taken.contains(plain.path) {
            taken.insert(plain.path)
            return plain
        }

        switch policy {
        case .skip:
            return nil
        case .overwrite:
            if taken.contains(plain.path) { return numbered(candidate) }
            taken.insert(plain.path)
            return plain
        case .rename:
            return numbered(candidate)
        }
    }

    private func numbered(_ candidate: (String) -> URL) -> URL {
        let manager = FileManager.default
        var index = 2
        while index < 10_000 {
            let url = candidate(" \(index)")
            if !manager.fileExists(atPath: url.path), !taken.contains(url.path) {
                taken.insert(url.path)
                return url
            }
            index += 1
        }
        let fallback = candidate(" \(UUID().uuidString.prefix(6))")
        taken.insert(fallback.path)
        return fallback
    }
}

/// Прокидывает прогресс в модель, не заваливая главный поток обновлениями.
final class ProgressReporter: @unchecked Sendable {
    private let item: ConversionItem
    private let lock = NSLock()
    private var lastSent: Double = -1

    init(item: ConversionItem) {
        self.item = item
    }

    func report(_ value: Double) {
        lock.lock()
        let shouldSend = value - lastSent >= 0.01 || value >= 1
        if shouldSend { lastSent = value }
        lock.unlock()

        guard shouldSend else { return }
        Task { @MainActor [item] in
            item.progress = value
        }
    }
}
