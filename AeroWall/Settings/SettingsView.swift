import SwiftUI
import ServiceManagement

struct VideoItem {
    let url: URL
    var thumbnail: NSImage?
}

struct SettingsView: View {
    @State private var videos: [VideoItem] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var experimentalLockScreen = false
    @State private var isTargeted = false
    @State private var hoveredURL: URL? = nil
    @AppStorage("lastVideoPath") private var lastVideoPath: String = ""

    let columns = [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 20)]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AeroWall")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                        )
                    Text("Manage your live wallpapers")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { newValue in
                            do {
                                if newValue { try SMAppService.mainApp.register() }
                                else { try SMAppService.mainApp.unregister() }
                            } catch { print("Failed to change login item: \(error)") }
                        }
                    
                    Toggle("Lock Screen Sync", isOn: $experimentalLockScreen)
                        .toggleStyle(.switch)
                }
            }
            .padding(24)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(videos, id: \.url) { video in
                        let isPlaying = (video.url.path == lastVideoPath)
                        VideoCardView(
                            video: video,
                            hoveredURL: $hoveredURL,
                            isPlaying: isPlaying
                        ) {
                            ScreenManager.shared.playVideo(at: video.url)
                        } onDelete: {
                            VideoImporter.shared.deleteVideo(at: video.url)
                            loadVideos()
                        }
                    }
                }
                .padding(24)
            }
            .background(Color(NSColor.underPageBackgroundColor))
            .dropDestination(for: URL.self) { items, _ in
                handleDrop(items: items)
            } isTargeted: { targeted in
                withAnimation { isTargeted = targeted }
            }
            .overlay {
                if videos.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                        Text("Drop video files here")
                            .font(.headline)
                        Text("Supports MP4 and MOV formats")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if isTargeted {
                    ZStack {
                        Color.blue.opacity(0.1)
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, dash: [10]))
                            .padding(12)
                        VStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.blue)
                            Text("Drop to Add")
                                .font(.title3.bold())
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            loadVideos()
        }
    }
    
    private func handleDrop(items: [URL]) -> Bool {
        var imported = false
        for url in items {
            if let _ = VideoImporter.shared.importVideo(from: url) {
                imported = true
            }
        }
        if imported { loadVideos() }
        return true
    }
    
    private func loadVideos() {
        let urls = VideoImporter.shared.getImportedVideos()
        self.videos = urls.map { VideoItem(url: $0, thumbnail: nil) }
        
        for i in self.videos.indices {
            let url = self.videos[i].url
            Task {
                if let thumb = await VideoImporter.shared.generateThumbnail(for: url) {
                    await MainActor.run {
                        if let index = self.videos.firstIndex(where: { $0.url == url }) {
                            self.videos[index].thumbnail = thumb
                        }
                    }
                }
            }
        }
    }
}

struct VideoCardView: View {
    let video: VideoItem
    @Binding var hoveredURL: URL?
    let isPlaying: Bool
    let onPlay: () -> Void
    let onDelete: () -> Void
    
    var isHovered: Bool { hoveredURL == video.url }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let thumb = video.thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(height: 120)
                        .overlay(ProgressView())
                }
                
                // Currently playing indicator
                if isPlaying && !isHovered {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.green)
                                .background(Circle().fill(Color.white))
                                .padding(8)
                        }
                    }
                }
                
                // Overlay actions
                if isHovered {
                    Color.black.opacity(0.4)
                    Button(action: onPlay) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: onDelete) {
                                Image(systemName: "trash.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.red)
                                    .background(Circle().fill(Color.white).shadow(radius: 1))
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                        }
                        Spacer()
                    }
                }
            }
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 2)
            
            Text(video.url.lastPathComponent)
                .font(.callout)
                .fontWeight(isPlaying ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 4)
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
    }
}
