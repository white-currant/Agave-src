import SwiftUI

/// Редкие настройки, которые не должны занимать место в основном окне.
struct SettingsPopover: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 12) {
            row("Частота") {
                Picker("", selection: $model.settings.sampleRate) {
                    ForEach(SampleRateChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
            }

            row("Каналы") {
                Picker("", selection: $model.settings.channels) {
                    ForEach(ChannelChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
            }

            row("Если файл есть") {
                Picker("", selection: $model.settings.conflict) {
                    ForEach(ConflictPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
            }

            Divider()

            Toggle("Переносить теги (название, исполнитель, альбом)", isOn: $model.settings.copyMetadata)
                .font(.system(size: 12))
                .toggleStyle(.checkbox)

            if model.settings.format == .mp3 {
                Text("Для MP3 теги пишутся полностью. Для остальных форматов — насколько позволяет контейнер.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 10))
                Text("Параллельно: до \(ConversionRunner.laneCount(for: 64)) файлов")
                    .font(.system(size: 10))
            }
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 340)
    }

    private func row<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 108, alignment: .leading)
            content()
                .labelsHidden()
        }
    }
}
