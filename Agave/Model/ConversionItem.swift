import Foundation
import Observation

/// Один файл в очереди.
@Observable
final class ConversionItem: Identifiable {
    enum Status: Equatable {
        case waiting
        case running
        case done
        case skipped
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let sourceURL: URL
    let displayName: String

    var byteSize: Int64
    var info: AudioProbe.Info?
    var status: Status = .waiting
    var progress: Double = 0
    var outputURL: URL?

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
        self.displayName = sourceURL.lastPathComponent
        let values = try? sourceURL.resourceValues(forKeys: [.fileSizeKey])
        self.byteSize = Int64(values?.fileSize ?? 0)
    }

    var isFinished: Bool {
        switch status {
        case .waiting, .running: return false
        default: return true
        }
    }

    var errorText: String? {
        if case .failed(let message) = status { return message }
        return nil
    }

    /// Подпись под именем файла: «MP3 · 3:42 · 8,4 МБ».
    var subtitle: String {
        var parts: [String] = []
        if let info {
            parts.append(info.formatLabel)
            if let duration = info.duration, duration > 0 {
                parts.append(Self.formatDuration(duration))
            }
        }
        if byteSize > 0 {
            parts.append(Self.byteFormatter.string(fromByteCount: byteSize))
        }
        return parts.joined(separator: " · ")
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
