import SwiftUI

@main
struct AeroWallApp: App {
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var screens = ScreenManager.shared

    var body: some Scene {
        Window("AeroWall", id: Self.mainWindowID) {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            AppMenu()
        } label: {
            Image(systemName: screens.isPaused ? "tv" : "play.tv")
        }
    }
}

struct AppMenu: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var screens = ScreenManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var library = VideoLibrary.shared
    @ObservedObject private var playlist = PlaylistManager.shared

    var body: some View {
        Text(screens.statusText)
        ForEach(library.videos.filter { screens.activeURLs.contains($0.url) }) { video in
            Text("  \(video.title)")
        }

        Divider()

        Button(screens.isUserPaused ? "Resume" : "Pause") {
            screens.togglePause()
        }
        .keyboardShortcut("p")
        .disabled(screens.activeURLs.isEmpty)

        if playlist.isActive {
            Button("Next Wallpaper") {
                playlist.advance()
            }
            .keyboardShortcut("n")
        }

        if !library.videos.isEmpty {
            Menu("Wallpaper") {
                ForEach(library.videos) { video in
                    Toggle(video.title, isOn: Binding(
                        get: { screens.activeURLs.contains(video.url) },
                        set: { _ in screens.setWallpaper(video) }
                    ))
                }
            }
        }

        Picker("Effect", selection: $settings.effect) {
            ForEach(OverlayEffect.allCases) { effect in
                Text(effect.title).tag(effect)
            }
        }

        Toggle("Mute Audio", isOn: $settings.muteAudio)

        Divider()

        Button("Open AeroWall…") {
            openWindow(id: AeroWallApp.mainWindowID)
            NSApp.activate()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit AeroWall") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
