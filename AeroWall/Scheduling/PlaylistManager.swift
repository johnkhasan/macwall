import Foundation
import Combine

/// Advances through `AppSettings.playlist` on a timer. `ScreenManager` reads `index`
/// to decide which video each display shows.
@MainActor
final class PlaylistManager: ObservableObject {
    static let shared = PlaylistManager()

    private static let indexKey = "playlistIndex"

    @Published private(set) var index: Int
    @Published private(set) var nextChange: Date?

    private let settings = AppSettings.shared
    private var timer: Timer?
    private var scheduledInterval: TimeInterval?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        index = UserDefaults.standard.integer(forKey: Self.indexKey)
    }

    func start() {
        guard cancellables.isEmpty else { return }
        settings.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.reschedule() }
            .store(in: &cancellables)
        reschedule()
    }

    var isActive: Bool {
        settings.playlistEnabled && settings.playlist.count > 1
    }

    func advance() {
        let count = settings.playlist.count
        guard count > 1 else { return }
        if settings.playlistShuffle {
            var next = index % count
            while next == index % count {
                next = Int.random(in: 0..<count)
            }
            setIndex(next)
        } else {
            setIndex((index + 1) % count)
        }
        restartTimer()
    }

    func jump(to newIndex: Int) {
        setIndex(newIndex)
        restartTimer()
    }

    private func setIndex(_ newIndex: Int) {
        index = newIndex
        UserDefaults.standard.set(newIndex, forKey: Self.indexKey)
    }

    private func reschedule() {
        let desired = isActive ? settings.playlistInterval : nil
        guard desired != scheduledInterval else { return }
        restartTimer()
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        nextChange = nil
        scheduledInterval = isActive ? settings.playlistInterval : nil
        guard let interval = scheduledInterval, interval > 0 else { return }

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        timer.tolerance = min(interval * 0.05, 30)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        nextChange = Date().addingTimeInterval(interval)
    }
}
