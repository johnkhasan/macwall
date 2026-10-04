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
    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 210, maximum: 300), spacing: 22)]

    private var filteredVideos: [VideoItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return library.videos }
        return library.videos.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !library.importJobs.isEmpty {
                ImportProgressView(jobs: library.importJobs)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if searchText.isEmpty {
                        NowPlayingBanner()
                    }
                    if !library.videos.isEmpty {
                        libraryHeader
                    }
                LazyVGrid(columns: columns, spacing: 26) {
                    ForEach(filteredVideos) { video in
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
                }
                .padding(28)
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
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search wallpapers")
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

    private var libraryHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Library")
                .font(.system(size: 22, weight: .bold))
            Text(searchText.isEmpty ? "\(library.videos.count) videos" : "\(filteredVideos.count) of \(library.videos.count)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text("Double-click to set · Right-click for more")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
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

    @State private var metadata: VideoMetadata?

    private var isHovered: Bool { hoveredURL == video.url }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay(VideoThumbnail(url: video.url))
                .overlay {
                    if isHovered {
                        Color.black.opacity(0.3)
                    }
                }
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 4) {
                        ForEach(badges, id: \.self) { badge in
                            Image(systemName: badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    .padding(8)
                }
                .overlay(alignment: .topTrailing) {
                    if isHovered {
                        Menu {
                            menuItems()
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .padding(8)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isPlaying {
                        Label("Live", systemImage: "dot.radiowaves.left.and.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor))
                            .padding(8)
                    }
                }
                .overlay {
                    if isHovered && !isPlaying {
                        Button(action: onPlay) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 46, height: 46)
                                .background(Circle().fill(.white))
                                .shadow(color: .black.opacity(0.3), radius: 6)
                        }
                        .buttonStyle(.plain)
                        .help("Set as wallpaper")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isPlaying ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isPlaying ? 3 : 1)
                )
                .shadow(color: .black.opacity(isHovered ? 0.3 : 0.15), radius: isHovered ? 12 : 5, y: isHovered ? 6 : 2)
                .scaleEffect(isHovered ? 1.025 : 1)
                .onTapGesture(count: 2, perform: onPlay)

            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(metadata.map { "\($0.resolutionLabel) · \($0.durationLabel)\($0.isHEVC ? " · HEVC" : "")" } ?? " ")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .onHover { hovering in
            withAnimation(.spring(duration: 0.25)) {
                if hovering {
                    hoveredURL = video.url
                } else if hoveredURL == video.url {
                    hoveredURL = nil
                }
            }
        }
        .task(id: video.url) {
            metadata = await VideoLibrary.shared.metadata(for: video.url)
        }
    }
}
