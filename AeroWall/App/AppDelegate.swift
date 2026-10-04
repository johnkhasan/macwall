import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceObserver.shared.start()
        PlaylistManager.shared.start()
        WeatherService.shared.start()
        ScreenManager.shared.start()
        PauseController.shared.start()

        let settings = AppSettings.shared
        if settings.hasLaunchedBefore {
            // Later launches (e.g. at login) stay quietly in the menu bar.
            DispatchQueue.main.async {
                for window in NSApp.windows where window.identifier?.rawValue.hasPrefix(AeroWallApp.mainWindowID) == true {
                    window.close()
                }
            }
        } else {
            settings.hasLaunchedBefore = true
            NSApp.activate()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
