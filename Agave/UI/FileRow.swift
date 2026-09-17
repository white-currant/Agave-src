import AppKit
import SwiftUI

struct FileRow: View {
    let item: ConversionItem
    @Environment(AppModel.self) private var model
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            StatusBadge(status: item.status, progress: item.progress)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(detailText)
                    .font(.system(size: 11))
                    .foregroundStyle(detailColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            trailing
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: Theme.rowHeight)
        .contentShape(Rectangle())
        .background(isHovering ? Color.primary.opacity(0.04) : .clear)
        .onHover { isHovering = $0 }
        .help(item.errorText ?? item.sourceURL.path(percentEncoded: false))
        .onTapGesture(count: 2) { reveal() }
        .contextMenu {
            Button("Показать оригинал в Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.sourceURL])
            }
            if let output = item.outputURL {
                Button("Показать результат в Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([output])
                }
            }
            Divider()
            Button("Убрать из очереди") {
                model.remove(item)
            }
            .disabled(model.isRunning)
        }
    }

    private var detailText: String {
        switch item.status {
        case .failed(let message): return message
        case .skipped: return "Пропущен — файл уже есть в папке экспорта"
        case .cancelled: return "Отменён"
        default: return item.subtitle
        }
    }

    private var detailColor: Color {
        switch item.status {
        case .failed: return .orange
        default: return .secondary
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch item.status {
        case .running:
            Text("\(Int(item.progress * 100))%")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        case .done:
            if isHovering {
                Button {
                    reveal()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Показать в Finder")
            }
        default:
            if isHovering, !model.isRunning {
                Button {
                    model.remove(item)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Убрать из очереди")
            }
        }
    }

    private func reveal() {
        let target = item.outputURL ?? item.sourceURL
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }
}

/// Кружок слева: он же индикатор состояния и прогресса.
struct StatusBadge: View {
    let status: ConversionItem.Status
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.12))
                .frame(width: 28, height: 28)

            switch status {
            case .running:
                Circle()
                    .trim(from: 0, to: max(0.03, progress))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 22, height: 22)
                    .animation(.linear(duration: 0.15), value: progress)
            default:
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint)
            }
        }
    }

    private var symbol: String {
        switch status {
        case .waiting: return "music.note"
        case .running: return "waveform"
        case .done: return "checkmark"
        case .skipped: return "minus"
        case .cancelled: return "xmark"
        case .failed: return "exclamationmark"
        }
    }

    private var tint: Color {
        switch status {
        case .done: return .green
        case .failed: return .orange
        case .running: return Theme.accent
        default: return .secondary
        }
    }
}
