import AppKit
import AVFoundation
import UniformTypeIdentifiers

struct VideoItem: Identifiable, Hashable {
    let url: URL

    var id: URL { url }
    /// File name; the key settings use to reference this video.
    var name: String { url.lastPathComponent }
    var title: String { url.deletingPathExtension().lastPathComponent }
}

struct ImportJob: Identifiable {
    let id = UUID()
    let name: String
    var progress: Double = 0
    var isConverting = false
}

@MainActor
final class VideoLibrary: ObservableObject {
    static let shared = VideoLibrary()
    static let supportedExtensions: Set<String> = ["mp4", "mov", "m4v"]

    @Published private(set) var videos: [VideoItem] = []
    @Published private(set) var importJobs: [ImportJob] = []
    @Published var lastError: String?

    let directory: URL
    private var metadataCache: [URL: VideoMetadata] = [:]

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("AeroWall/Videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        let keys: [URLResourceKey] = [.creationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )) ?? []
        videos = files
            .filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
            .map { ($0, (try? $0.resourceValues(forKeys: Set(keys)).creationDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .map { VideoItem(url: $0.0) }
    }

    func url(for name: String) -> URL? {
        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func item(named name: String?) -> VideoItem? {
        guard let name else { return nil }
        return videos.first { $0.name == name }
    }

    var totalSize: Int64 {
        videos.reduce(0) { total, item in
            total + Int64((try? item.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func metadata(for url: URL) async -> VideoMetadata? {
        if let cached = metadataCache[url] { return cached }
        let metadata = try? await VideoImporter.inspect(AVURLAsset(url: url))
        metadataCache[url] = metadata
        return metadata
    }

    // MARK: Import

    func importFiles(_ urls: [URL]) {
        let videoURLs = urls.flatMap(Self.expandVideos)
        if videoURLs.isEmpty && !urls.isEmpty {
            lastError = "No supported videos found. AeroWall accepts .mp4, .mov and .m4v files."
        }
        for url in videoURLs {
            importFile(url)
        }
    }

    private func importFile(_ source: URL) {
        let job = ImportJob(name: source.deletingPathExtension().lastPathComponent)
        importJobs.append(job)
        let convert = AppSettings.shared.convertOnImport
        let longestSide = NSScreen.screens
            .map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }
            .max() ?? 3840

        Task {
            let accessing = source.startAccessingSecurityScopedResource()
            defer {
                if accessing { source.stopAccessingSecurityScopedResource() }
                importJobs.removeAll { $0.id == job.id }
            }
            do {
                let imported = try await VideoImporter.importVideo(
                    from: source,
                    into: directory,
                    convert: convert,
                    displayLongestSide: longestSide
                ) { progress, converting in
                    Task { @MainActor in self.updateJob(job.id, progress: progress, converting: converting) }
                }
                reload()
                // First video ever: show it straight away.
                if AppSettings.shared.wallpaper == nil {
                    AppSettings.shared.wallpaper = imported.lastPathComponent
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func updateJob(_ id: UUID, progress: Double, converting: Bool) {
        guard let index = importJobs.firstIndex(where: { $0.id == id }) else { return }
        importJobs[index].progress = progress
        importJobs[index].isConverting = converting
    }

    private static func expandVideos(_ url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else {
            return supportedExtensions.contains(url.pathExtension.lowercased()) ? [url] : []
        }
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return (enumerator?.allObjects as? [URL] ?? [])
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
    }

    // MARK: Editing

    func rename(_ item: VideoItem, to newTitle: String) throws {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !trimmed.isEmpty, trimmed != item.title else { return }
        let destination = VideoImporter.uniqueURL(in: directory, baseName: trimmed, extension: item.url.pathExtension)
        try FileManager.default.moveItem(at: item.url, to: destination)
        forget(item.url)
        AppSettings.shared.replaceReferences(to: item.name, with: destination.lastPathComponent)
        reload()
    }

    func delete(_ item: VideoItem) {
        AppSettings.shared.replaceReferences(to: item.name, with: nil)
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        } catch {
            try? FileManager.default.removeItem(at: item.url)
        }
        forget(item.url)
        reload()
    }

    func revealInFinder(_ item: VideoItem? = nil) {
        if let item {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        } else {
            NSWorkspace.shared.open(directory)
        }
    }

    private func forget(_ url: URL) {
        metadataCache[url] = nil
        ThumbnailGenerator.shared.invalidate(url)
    }
}
