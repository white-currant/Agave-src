#if SPARKLE_ENABLED
import Combine
import Sparkle

@MainActor
final class UpdaterViewModel: ObservableObject {
    let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    @Published private(set) var canCheckForUpdates = false
    private var cancellable: AnyCancellable?

    init() {
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
        // Сам по себе Sparkle проверяет не чаще раза в сутки; здесь — проверка на каждом запуске.
        // Окно появится, только если найдена новая версия.
        controller.updater.checkForUpdatesInBackground()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
#endif
