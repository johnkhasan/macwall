import SwiftUI

// MARK: - Thumbnail

/// Lazily loaded video still that fills its frame.
struct VideoThumbnail: View {
    let url: URL?

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(
                LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
            )
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else if url == nil {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .clipped()
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            let loaded = await ThumbnailGenerator.shared.thumbnail(for: url)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

// MARK: - Sidebar icon

/// System Settings–style white symbol on a colored rounded square.
struct SettingsIcon: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Status

struct StatusPill: View {
    @ObservedObject private var screens = ScreenManager.shared

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(screens.statusText)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var color: Color {
        if screens.activeURLs.isEmpty { return .gray }
        return screens.isPaused ? .orange : .green
    }
}

struct CircleIconButton: View {
    let systemName: String
    let help: String
    var prominent = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: prominent ? 17 : 14, weight: .bold))
                .foregroundStyle(prominent ? .black : .white)
                .frame(width: prominent ? 44 : 36, height: prominent ? 44 : 36)
                .background(
                    Circle().fill(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.ultraThinMaterial))
                )
                .scaleEffect(isHovered ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            withAnimation(.spring(duration: 0.2)) { isHovered = hovering }
        }
    }
}

// MARK: - Now playing

/// Large banner with the current wallpaper, its status and playback controls.
struct NowPlayingBanner: View {
    @ObservedObject private var screens = ScreenManager.shared
    @ObservedObject private var library = VideoLibrary.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var metadata: VideoMetadata?

    var body: some View {
        if let url = screens.primaryURL {
            ZStack(alignment: .bottomLeading) {
                VideoThumbnail(url: url)
                    .frame(height: 230)
                    .frame(maxWidth: .infinity)

                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.25), .black.opacity(0.8)],
                    startPoint: .top, endPoint: .bottom
                )

                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusPill()
                            .foregroundStyle(.white)
                        Text(url.deletingPathExtension().lastPathComponent)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 10) {
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
                .padding(24)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            .task(id: url) {
                metadata = await library.metadata(for: url)
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let metadata {
            parts.append(metadata.resolutionLabel)
            parts.append(metadata.durationLabel)
        }
        let displayCount = screens.displayURLs.count
        if displayCount > 1 {
            parts.append(screens.activeURLs.count == 1 ? "All \(displayCount) displays" : "\(displayCount) displays")
        }
        if settings.playlistEnabled && PlaylistManager.shared.isActive {
            parts.append("Playlist")
        } else if settings.appearanceSwitching {
            parts.append("Light & Dark")
        }
        if settings.effect != .none {
            parts.append(settings.effect.title)
        }
        return parts.joined(separator: "  ·  ")
    }
}

// MARK: - Sidebar status

struct SidebarNowPlaying: View {
    @ObservedObject private var screens = ScreenManager.shared

    var body: some View {
        HStack(spacing: 10) {
            VideoThumbnail(url: screens.primaryURL)
                .frame(width: 52, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(screens.primaryURL?.deletingPathExtension().lastPathComponent ?? "No wallpaper")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(screens.statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !screens.activeURLs.isEmpty {
                Button {
                    screens.togglePause()
                } label: {
                    Image(systemName: screens.isUserPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.quaternary))
                }
                .buttonStyle(.plain)
                .help(screens.isUserPaused ? "Resume" : "Pause")
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }
}

// MARK: - Effect tile

struct EffectTile: View {
    let effect: OverlayEffect
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: effect.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 72)
                    .overlay(
                        Image(systemName: effect.icon)
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.25), radius: 3)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(6)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                    )
                    .scaleEffect(isHovered ? 1.03 : 1)
                Text(effect.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(duration: 0.2)) { isHovered = hovering }
        }
    }
}

extension OverlayEffect {
    var colors: [Color] {
        switch self {
        case .none: return [Color(white: 0.45), Color(white: 0.3)]
        case .rain: return [Color(red: 0.25, green: 0.45, blue: 0.75), Color(red: 0.12, green: 0.2, blue: 0.4)]
        case .snow: return [Color(red: 0.6, green: 0.8, blue: 0.95), Color(red: 0.35, green: 0.5, blue: 0.75)]
        case .particles: return [Color(red: 0.95, green: 0.7, blue: 0.3), Color(red: 0.45, green: 0.25, blue: 0.55)]
        case .weather: return [Color(red: 0.35, green: 0.7, blue: 0.95), Color(red: 0.95, green: 0.65, blue: 0.3)]
        }
    }
}
