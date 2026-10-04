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
            MenuBarPanel()
        } label: {
            Image(systemName: screens.isPaused ? "tv" : "play.tv")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarPanel: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var screens = ScreenManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var library = VideoLibrary.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            nowPlaying

            if !library.videos.isEmpty {
                section("Wallpapers") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(library.videos) { video in
                                wallpaperButton(video)
                            }
                        }
                    }
                    // Pin the strip to the panel's inner width. Without this the horizontal
                    // ScrollView reports its full content width and MenuBarExtra(.window) grows
                    // the popover past `panelWidth`, clipping the content on both sides.
                    .frame(width: Self.panelWidth - 28)
                }
            }

            section("Effect") {
                HStack(spacing: 6) {
                    ForEach(OverlayEffect.allCases) { effect in
                        let selected = settings.effect == effect
                        Button {
                            settings.effect = effect
                        } label: {
                            Image(systemName: effect.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 30)
                                .foregroundStyle(selected ? .white : .primary)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                                )
                        }
                        .buttonStyle(.plain)
                        .help(effect.title)
                    }
                }
            }

            Divider()

            HStack {
                Button {
                    openWindow(id: AeroWallApp.mainWindowID)
                    NSApp.activate()
                } label: {
                    Label("Open AeroWall", systemImage: "macwindow")
                }
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
        }
        .padding(14)
        .frame(width: Self.panelWidth)
    }

    static let panelWidth: CGFloat = 320

    private var nowPlaying: some View {
        ZStack(alignment: .bottomLeading) {
            // A hard width (not maxWidth:.infinity): a wide thumbnail must be clipped to the panel,
            // never allowed to stretch MenuBarExtra(.window) wider than `panelWidth`.
            VideoThumbnail(url: screens.primaryURL)
                .frame(width: Self.panelWidth - 28, height: 150)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(screens.primaryURL?.deletingPathExtension().lastPathComponent ?? "No wallpaper")
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(screens.statusText)
                        .font(.system(size: 11))
                        .opacity(0.8)
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                Spacer()
                if !screens.activeURLs.isEmpty {
                    HStack(spacing: 6) {
                        CircleIconButton(systemName: settings.muteAudio ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                         help: settings.muteAudio ? "Unmute" : "Mute") {
                            settings.muteAudio.toggle()
                        }
                        if screens.canShowNext {
                            CircleIconButton(systemName: "forward.fill", help: "Next wallpaper") {
                                screens.showNext()
                            }
                        }
                        CircleIconButton(systemName: screens.isUserPaused ? "play.fill" : "pause.fill",
                                         help: screens.isUserPaused ? "Resume" : "Pause",
                                         prominent: true) {
                            screens.togglePause()
                        }
                    }
                }
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func wallpaperButton(_ video: VideoItem) -> some View {
        let active = screens.activeURLs.contains(video.url)
        return Button {
            screens.setWallpaper(video)
        } label: {
            VideoThumbnail(url: video.url)
                .frame(width: 88, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(active ? Color.accentColor : .clear, lineWidth: 2.5)
                )
        }
        .buttonStyle(.plain)
        .help(video.title)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
