import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().opacity(0.6)
                queue
                Divider().opacity(0.6)
                BottomBar()
            }
        }
        .background(WindowConfigurator())
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls: urls)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 3)
                    .background(Theme.accent.opacity(0.06))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isTargeted)
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Agave")
                    .font(.system(size: 15, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let banner = model.banner {
                Label(banner.text, systemImage: banner.kind == .warning
                    ? "exclamationmark.circle"
                    : "checkmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(banner.kind == .warning ? .orange : .secondary)
                    .labelStyle(.titleAndIcon)
                    .transition(.opacity)
            }

            if !model.items.isEmpty {
                Button("Очистить") { model.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .disabled(model.isRunning)
            }
        }
        .padding(.leading, Theme.trafficLightInset)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .frame(height: 52)
        .animation(.easeOut(duration: 0.15), value: model.banner)
    }

    private var headerSubtitle: String {
        if model.items.isEmpty {
            return "Пакетный конвертер звука"
        }
        let total = model.items.count
        if model.isRunning {
            return "Идёт конвертация · осталось \(model.pendingCount) из \(total)"
        }
        return "\(total) \(Self.plural(total, "файл", "файла", "файлов")) в очереди"
    }

    static func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod100 = count % 100
        if (11...14).contains(mod100) { return many }
        switch count % 10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }

    // MARK: - Очередь

    @ViewBuilder
    private var queue: some View {
        if model.items.isEmpty {
            EmptyStateView(isTargeted: isTargeted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.items) { item in
                        FileRow(item: item)
                        Divider()
                            .opacity(0.4)
                            .padding(.leading, 56)
                    }
                }
                // Место под талисмана в правом нижнем углу: без запаса он
                // накрывал бы последнюю строку списка.
                Color.clear.frame(height: 96)
            }
            .scrollContentBackground(.hidden)
            .overlay(alignment: .bottomTrailing) {
                AgaveMascot(mood: mascotMood, size: 150)
                    .padding(.trailing, 28)
                    .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
                    // Талисман — украшение: он не должен перехватывать нажатия
                    // по строкам списка под ним.
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.72), value: model.items.isEmpty)
        }
    }

    private var mascotMood: AgaveMascot.Mood {
        if model.isRunning { return .working }
        return isTargeted ? .excited : .idle
    }
}

/// Пустой экран: приглашение перетащить файлы. Здесь живёт талисман.
struct EmptyStateView: View {
    @Environment(AppModel.self) private var model
    var isTargeted = false

    var body: some View {
        VStack(spacing: 10) {
            AgaveMascot(mood: isTargeted ? .excited : .idle, size: 150)

            VStack(spacing: 4) {
                Text(isTargeted
                     ? "Отпускайте — разберу"
                     : "Перетащите сюда файлы или папку")
                    .font(.system(size: 14, weight: .medium))
                    .contentTransition(.opacity)
                Text("MP3, M4A, OGG, WAV, AIFF, FLAC, ALAC и всё, что читает система")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .animation(.easeOut(duration: 0.15), value: isTargeted)

            Button("Выбрать файлы…") {
                model.addFromPanel()
            }
            .controlSize(.regular)
            .padding(.top, 4)
        }
        .padding(32)
    }
}
