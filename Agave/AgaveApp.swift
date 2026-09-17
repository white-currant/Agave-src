import SwiftUI

@main
struct AgaveApp: App {
    @State private var model = AppModel()
    #if SPARKLE_ENABLED
    @StateObject private var updater = UpdaterViewModel()
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 660, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 820, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Добавить файлы…") {
                    model.addFromPanel()
                }
                .keyboardShortcut("o")
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Папка экспорта…") {
                    model.chooseExportFolder()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Открыть папку экспорта") {
                    model.openExportFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            #if SPARKLE_ENABLED
            CommandGroup(after: .appInfo) {
                Button("Проверить обновления…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
            #endif
        }
    }
}
