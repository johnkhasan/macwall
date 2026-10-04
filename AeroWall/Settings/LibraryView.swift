import SwiftUI

struct LibraryView: View {
    @ObservedObject private var library = VideoLibrary.shared
    @ObservedObject private var screens = ScreenManager.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var isTargeted = false
    @State private var hoveredURL: URL?
    @State private var renaming: VideoItem?
    @State private var renameText = ""
    @State private var deleting: VideoItem?

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 24)]

    var body: some View {
        VStack(spacing: 0) {
            if !library.importJobs.isEmpty {
                ImportProgressView(jobs: library.importJobs)
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(library.videos) { video in
                        VideoCardView(
                            video: video,
                            isPlaying: screens.activeURLs.contains(video.url),
                            badges: badges(for: video),
                            hoveredURL: $hoveredURL
                        ) {
                            screens.setWallpaper(video)
                        } menuItems: {
                            menuItems(for: video)
                        }
                        .contextMenu { menuItems(for: video) }
                    }
                }
                .padding(30)
            }
            .background(Color(NSColor.underPageBackgroundColor))
            .dropDestination(for: URL.self) { items, _ in
                library.importFiles(items)
                return true
            } isTargeted: { targeted in
                withAnimation { isTargeted = targeted }
            }
            .overlay { overlay }
        }
        .navigationTitle("Wallpaper Library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: openFilePanel) {
                    Label("Add Wallpaper", systemImage: "plus")
                }
                .help("Add videos to the library")
            }
        }
        .alert("Rename Wallpaper", isPresented: isPresented($renaming)) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let item = renaming {
                    do {
                        try library.rename(item, to: renameText)
                    } catch {
                        library.lastError = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete “\(deleting?.title ?? "")”?",
            isPresented: isPresented($deleting),
            presenting: deleting
        ) { item in
            Button("Move to Trash", role: .destructive) { library.delete(item) }
        } message: { _ in
            Text("The video is moved to the Trash and removed from playlists and displays.")
        }
        .alert("Something went wrong", isPresented: isPresented($library.lastError)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.lastError ?? "")
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if isTargeted {
            ZStack {
                Color.accentColor.opacity(0.15)
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, dash: [12]))
                    .padding(16)
                VStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 64))
                    Text("Drop to Add Wallpaper")
                        .font(.title.bold())
                }
                .foregroundColor(.accentColor)
            }
        } else if library.videos.isEmpty && library.importJobs.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
                Text("No Wallpapers Yet")
                    .font(.title2.bold())
                Text("Drag and drop .mp4, .mov or .m4v files (or a folder of them) here to add them to your library.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button("Choose Videos…", action: openFilePanel)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func badges(for video: VideoItem) -> [String] {
        var badges: [String] = []
        if settings.playlist.contains(video.name) { badges.append("list.bullet") }
        if settings.lightWallpaper == video.name { badges.append("sun.max.fill") }
        if settings.darkWallpaper == video.name { badges.append("moon.fill") }
        return badges
    }

    @ViewBuilder
    private func menuItems(for video: VideoItem) -> some View {
        Button("Set as Wallpaper") { screens.setWallpaper(video) }
        if !settings.sameOnAllDisplays && screens.displays.count > 1 {
            Menu("Set on Display") {
                ForEach(screens.displays) { display in
                    Button(display.name) { screens.setWallpaper(video, displayUUID: display.id) }
                }
            }
        }
        Divider()
        Button(settings.playlist.contains(video.name) ? "Remove from Playlist" : "Add to Playlist") {
            settings.togglePlaylist(video.name)
        }
        Button(settings.lightWallpaper == video.name ? "Stop Using in Light Mode" : "Use in Light Mode") {
            settings.lightWallpaper = settings.lightWallpaper == video.name ? nil : video.name
        }
        Button(settings.darkWallpaper == video.name ? "Stop Using in Dark Mode" : "Use in Dark Mode") {
            settings.darkWallpaper = settings.darkWallpaper == video.name ? nil : video.name
        }
        Divider()
        Button("Rename…") {
            renameText = video.title
            renaming = video
        }
        Button("Show in Finder") { library.revealInFinder(video) }
        Divider()
        Button("Delete…", role: .destructive) { deleting = video }
    }

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            library.importFiles(panel.urls)
        }
    }

    private func isPresented<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }
}

// MARK: - Import progress

private struct ImportProgressView: View {
    let jobs: [ImportJob]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(jobs) { job in
                HStack(spacing: 12) {
                    Image(systemName: job.isConverting ? "wand.and.rays" : "square.and.arrow.down")
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.isConverting ? "Optimizing “\(job.name)” for smooth playback…" : "Importing “\(job.name)”…")
                            .font(.callout)
                            .lineLimit(1)
                        ProgressView(value: job.progress)
                            .progressViewStyle(.linear)
                    }
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 14)
        .background(.bar)
    }
}

// MARK: - Video Card

struct VideoCardView<MenuItems: View>: View {
    let video: VideoItem
    let isPlaying: Bool
    let badges: [String]
    @Binding var hoveredURL: URL?
    let onPlay: () -> Void
    @ViewBuilder let menuItems: () -> MenuItems

    @State private var thumbnail: NSImage?
    @State private var metadata: VideoMetadata?

    private var isHovered: Bool { hoveredURL == video.url }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 140)
                        .frame(maxWidth: .infinity)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(height: 140)
                        .overlay(ProgressView().controlSize(.small))
                }

                if isHovered {
                    Color.black.opacity(0.35)
                }

                VStack {
                    HStack(spacing: 4) {
                        ForEach(badges, id: \.self) { badge in
                            Image(systemName: badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(5)
                                .background(Circle().fill(.black.opacity(0.55)))
                        }
                        Spacer()
                        if isHovered {
                            Menu {
                                menuItems()
                            } label: {
                                Image(systemName: "ellipsis.circle.fill")
                                    .font(.system(size: 22))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.black.opacity(0.75), .white)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                    }
                    Spacer()
                    HStack {
                        if let metadata {
                            Text("\(metadata.resolutionLabel) · \(metadata.durationLabel)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.black.opacity(0.55)))
                        }
                        Spacer()
                        if isPlaying {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.green)
                                .background(Circle().fill(Color.white))
                        }
                    }
                }
                .padding(8)

                if isHovered && !isPlaying {
                    Button(action: onPlay) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                    .help("Set as wallpaper")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isPlaying ? Color.accentColor : .clear, lineWidth: 3)
            )
            .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
            .onTapGesture(count: 2, perform: onPlay)

            Text(video.title)
                .font(.system(size: 14, weight: isPlaying ? .bold : .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 6)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                if hovering {
                    hoveredURL = video.url
                } else if hoveredURL == video.url {
                    hoveredURL = nil
                }
            }
        }
        .task(id: video.url) {
            thumbnail = await ThumbnailGenerator.shared.thumbnail(for: video.url)
            metadata = await VideoLibrary.shared.metadata(for: video.url)
        }
    }
}
