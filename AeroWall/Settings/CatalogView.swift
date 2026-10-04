import SwiftUI

/// Browses the macwall.app online catalog and saves wallpapers into the local library.
struct CatalogView: View {
    @ObservedObject private var downloader = CatalogDownloader.shared
    @ObservedObject private var library = VideoLibrary.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var screens = ScreenManager.shared

    @AppStorage("catalogSort") private var sort: CatalogSort = .popular
    @State private var category: CatalogCategory?
    @State private var searchText = ""

    @State private var wallpapers: [CatalogWallpaper] = []
    @State private var total: Int?
    @State private var nextPage = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var hoveredID: String?

    private let columns = [GridItem(.adaptive(minimum: 210, maximum: 300), spacing: 22)]

    private struct Query: Equatable {
        var category: CatalogCategory?
        var search: String
        var sort: CatalogSort
    }

    private var query: Query {
        Query(category: category, search: searchText.trimmingCharacters(in: .whitespaces), sort: sort)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                categoryBar
                LazyVGrid(columns: columns, spacing: 26) {
                    ForEach(wallpapers) { wallpaper in
                        card(for: wallpaper)
                            .onAppear {
                                if wallpaper.id == wallpapers.last?.id { Task { await loadMore() } }
                            }
                    }
                }
                footer
            }
            .padding(28)
        }
        .background(Color(NSColor.underPageBackgroundColor))
        .navigationTitle("Discover")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search online wallpapers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Sort", selection: $sort) {
                    ForEach(CatalogSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Sort the catalog")
            }
        }
        .task(id: query) {
            // Debounce typing; changing the query cancels the previous task.
            if !wallpapers.isEmpty || loadError != nil {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
            }
            await reload()
        }
        .alert("Download failed", isPresented: Binding(
            get: { downloader.lastError != nil },
            set: { if !$0 { downloader.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloader.lastError ?? "")
        }
    }

    // MARK: Sections

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(title: "All", isSelected: category == nil) { category = nil }
                ForEach(CatalogCategory.allCases) { item in
                    CategoryChip(title: item.rawValue, isSelected: category == item) { category = item }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
            } else if let loadError {
                VStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text(loadError).foregroundStyle(.secondary)
                    Button("Try Again") { Task { await loadMore() } }
                }
                .padding(.top, wallpapers.isEmpty ? 80 : 0)
            } else if wallpapers.isEmpty {
                Text("No wallpapers match your search.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 80)
            } else if !hasMore {
                Text("Wallpapers from macwall.app")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private func card(for wallpaper: CatalogWallpaper) -> some View {
        let localItem = downloader.localItem(for: wallpaper)
        return CatalogCardView(
            wallpaper: wallpaper,
            download: downloader.active[wallpaper.id],
            isSaved: localItem != nil,
            isPlaying: localItem.map { screens.activeURLs.contains($0.url) } ?? false,
            hoveredID: $hoveredID,
            onPreview: { CatalogPreviewController.shared.show(url: wallpaper.videoUrl, title: wallpaper.name) },
            onDownload: { downloader.download(wallpaper, setAsWallpaper: false) },
            onSet: { downloader.download(wallpaper, setAsWallpaper: true) },
            onCancel: { downloader.cancel(wallpaper) }
        )
    }

    // MARK: Loading

    private func reload() async {
        wallpapers = []
        total = nil
        nextPage = 1
        hasMore = true
        loadError = nil
        isLoading = false
        await loadMore()
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        let current = query
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let page = try await CatalogClient.fetchPage(
                nextPage, category: current.category, query: current.search, sort: current.sort
            )
            guard current == query else { return }
            // Ordering can shift between pages while new uploads arrive: skip duplicates.
            let known = Set(wallpapers.map(\.id))
            wallpapers += page.wallpapers.filter { !known.contains($0.id) }
            total = page.total
            hasMore = page.hasMore
            nextPage += 1
        } catch {
            guard current == query, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Category chip

private struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Remote thumbnail

private struct RemoteThumbnail: View {
    let url: URL

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
            }
        }
        .clipped()
        .task(id: url) {
            let loaded = await CatalogClient.image(at: url)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

// MARK: - Card

private struct CatalogCardView: View {
    let wallpaper: CatalogWallpaper
    let download: CatalogDownload?
    let isSaved: Bool
    let isPlaying: Bool
    @Binding var hoveredID: String?
    let onPreview: () -> Void
    let onDownload: () -> Void
    let onSet: () -> Void
    let onCancel: () -> Void

    private var isHovered: Bool { hoveredID == wallpaper.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay(RemoteThumbnail(url: wallpaper.thumbUrl))
                .overlay {
                    if isHovered || download != nil { Color.black.opacity(0.35) }
                }
                .overlay { centerContent }
                .overlay(alignment: .topTrailing) {
                    if isHovered && download == nil {
                        HStack(spacing: 6) {
                            if !isSaved {
                                smallButton("arrow.down", help: "Download to Library", action: onDownload)
                            }
                            smallButton("eye", help: "Preview", action: onPreview)
                        }
                        .padding(8)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isPlaying {
                        tag("Live", systemImage: "dot.radiowaves.left.and.right", color: .accentColor)
                    } else if isSaved {
                        tag("In Library", systemImage: "checkmark", color: .green)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isPlaying ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isPlaying ? 3 : 1)
                )
                .shadow(color: .black.opacity(isHovered ? 0.3 : 0.15), radius: isHovered ? 12 : 5, y: isHovered ? 6 : 2)
                .scaleEffect(isHovered ? 1.025 : 1)
                .onTapGesture(count: 2, perform: onSet)

            VStack(alignment: .leading, spacing: 2) {
                Text(wallpaper.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .onHover { hovering in
            withAnimation(.spring(duration: 0.25)) {
                if hovering {
                    hoveredID = wallpaper.id
                } else if hoveredID == wallpaper.id {
                    hoveredID = nil
                }
            }
        }
    }

    private var subtitle: String {
        var parts = [wallpaper.category]
        if let likes = wallpaper.likeCount, likes > 0 { parts.append("♥ \(likes)") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var centerContent: some View {
        if let download {
            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: max(0.02, download.progress))
                        .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: download.progress)
                    if download.isOptimizing {
                        Image(systemName: "wand.and.rays")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Button(action: onCancel) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Cancel download")
                    }
                }
                .frame(width: 44, height: 44)
                Text(download.isOptimizing ? "Optimizing…" : "\(Int(download.progress * 100))%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
        } else if isHovered && !isPlaying {
            Button(action: onSet) {
                Image(systemName: isSaved ? "play.fill" : "arrow.down.to.line")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.3), radius: 6)
            }
            .buttonStyle(.plain)
            .help(isSaved ? "Set as wallpaper" : "Download and set as wallpaper")
            .transition(.scale.combined(with: .opacity))
        }
    }

    private func smallButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func tag(_ title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color))
            .padding(8)
    }
}

// MARK: - Preview

