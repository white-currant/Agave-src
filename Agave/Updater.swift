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
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
#endif
