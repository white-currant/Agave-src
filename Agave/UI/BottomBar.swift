import SwiftUI

struct BottomBar: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            if model.isRunning {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .frame(height: 2)
                    .clipShape(Rectangle())
            }

            VStack(spacing: 10) {
                exportRow
                controlsRow(model: model)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Папка экспорта

    private var exportRow: some View {
        HStack(spacing: 10) {
            Image(systemName: model.exportFolder.url == nil ? "folder.badge.questionmark" : "folder.fill")
                .font(.system(size: 13))
                .foregroundStyle(model.exportFolder.url == nil ? .orange : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text("Папка экспорта")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(model.exportFolder.url == nil
                     ? "не выбрана"
                     : model.exportFolder.displayPath)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 8)

            Button("Изменить…") {
                model.chooseExportFolder()
            }
            .controlSize(.small)

            Button {
                model.openExportFolder()
            } label: {
                Label("Открыть", systemImage: "arrow.up.forward.app")
            }
            .controlSize(.small)
            .disabled(model.exportFolder.url == nil)
            .help("Открыть папку экспорта в Finder")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    // MARK: - Настройки и запуск

    private func controlsRow(model: AppModel) -> some View {
        @Bindable var model = model

        return HStack(spacing: 12) {
            Picker("", selection: $model.settings.format) {
                ForEach(OutputFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .labelsHidden()
            .fixedSize()
            .labeledControl("Формат")

            qualityPicker(model: model)

            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("Дополнительные настройки")
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                SettingsPopover()
                    .environment(model)
            }

            Spacer(minLength: 12)

            if model.isRunning {
                Text("\(Int(model.progress * 100))%")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                if model.isRunning {
                    model.cancel()
                } else {
                    model.start()
                }
            } label: {
                Text(model.isRunning ? "Остановить" : "Конвертировать")
                    .frame(minWidth: 112)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!model.isRunning && !model.canStart)
        }
    }

    @ViewBuilder
    private func qualityPicker(model: AppModel) -> some View {
        @Bindable var model = model
        let format = model.settings.format

        if format.isLossy {
            Picker("", selection: $model.settings.bitrate) {
                ForEach(bitrateChoices(for: format), id: \.self) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .labelsHidden()
            .fixedSize()
            .labeledControl("Битрейт")
        } else {
            Picker("", selection: $model.settings.bitDepth) {
                ForEach(format.availableBitDepths) { depth in
                    Text(depth.title).tag(depth)
                }
            }
            .labelsHidden()
            .fixedSize()
            .labeledControl("Разрядность")
        }
    }

    /// У AAC нет переменного битрейта в нашем движке — только постоянный.
    private func bitrateChoices(for format: OutputFormat) -> [BitrateMode] {
        var choices = BitrateMode.constantChoices.map { BitrateMode.constant($0) }
        if format.supportsVariableBitrate {
            choices += BitrateMode.variableChoices.map { BitrateMode.variable($0) }
        }
        return choices
    }
}
