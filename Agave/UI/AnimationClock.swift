import Foundation
import Observation

/// Общие часы для живых украшений: талисмана и листвы.
///
/// `TimelineView` тикает только в обычном режиме главного цикла, а пока открыто
/// меню или выпадающий список, AppKit крутит цикл в режиме отслеживания событий —
/// и анимация замирает. Таймер в общих режимах (`.common`) тикает в обоих.
@MainActor
@Observable
final class AnimationClock {
    static let shared = AnimationClock()

    private(set) var time: TimeInterval = Date.timeIntervalSinceReferenceDate

    @ObservationIgnored private var timer: Timer?

    private init() {
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                AnimationClock.shared.time = Date.timeIntervalSinceReferenceDate
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
