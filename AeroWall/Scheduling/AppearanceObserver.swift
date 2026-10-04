import AppKit

/// Publishes whether the system is in Dark Mode, for light/dark wallpaper switching.
@MainActor
final class AppearanceObserver: ObservableObject {
    static let shared = AppearanceObserver()

    @Published private(set) var isDark = false
    private var observation: NSKeyValueObservation?

    private init() {}

    func start() {
        guard observation == nil else { return }
        isDark = Self.isDark(NSApp.effectiveAppearance)
        observation = NSApp.observe(\.effectiveAppearance, options: [.new]) { app, _ in
            let dark = Self.isDark(app.effectiveAppearance)
            Task { @MainActor in
                if AppearanceObserver.shared.isDark != dark {
                    AppearanceObserver.shared.isDark = dark
                }
            }
        }
    }

    private nonisolated static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
