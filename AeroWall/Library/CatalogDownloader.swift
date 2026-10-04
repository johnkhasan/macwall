import Foundation

struct CatalogDownload: Equatable {
    var progress: Double = 0
    var isOptimizing = false
}

/// Downloads catalog wallpapers into the regular video library, so once saved they behave
/// exactly like imported files (playlists, displays, light/dark, offline playback).
@MainActor
final class CatalogDownloader: ObservableObject {
    static let shared = CatalogDownloader()

    @Published private(set) var active: [String: CatalogDownload] = [:]
    @Published var lastError: String?

    private var tasks: [String: Task<Void, Never>] = [:]
    private let settings = AppSettings.shared
    private let library = VideoLibrary.shared

    private init() {}

    /// The library video a catalog wallpaper was saved as, if it is still there.
    func localItem(for wallpaper: CatalogWallpaper) -> VideoItem? {
        library.item(named: settings.catalogDownloads[wallpaper.id])
    }

    func download(_ wallpaper: CatalogWallpaper, setAsWallpaper: Bool) {
        if let item = localItem(for: wallpaper) {
            if setAsWallpaper { ScreenManager.shared.setWallpaper(item) }
            return
        }
        guard tasks[wallpaper.id] == nil else { return }
        active[wallpaper.id] = CatalogDownload()

        tasks[wallpaper.id] = Task {
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("AeroWall-\(UUID().uuidString)", isDirectory: true)
            defer {
                try? FileManager.default.removeItem(at: staging)
                active[wallpaper.id] = nil
                tasks[wallpaper.id] = nil
            }
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                // The staged file name becomes the library title.
                let file = staging
                    .appendingPathComponent(Self.fileName(for: wallpaper))
                    .appendingPathExtension(wallpaper.fileExtension)
                try await fetch(wallpaper, to: file)
                try Task.checkCancellation()

                let imported = try await library.importDownloadedVideo(file) { progress, converting in
                    Task { @MainActor in
                        guard self.active[wallpaper.id] != nil else { return }
                        self.active[wallpaper.id] = CatalogDownload(progress: progress, isOptimizing: converting)
                    }
                }
                settings.catalogDownloads[wallpaper.id] = imported.lastPathComponent
                if setAsWallpaper, let item = library.item(named: imported.lastPathComponent) {
                    ScreenManager.shared.setWallpaper(item)
                }
            } catch {
                if !Self.isCancellation(error) {
                    lastError = "Could not download “\(wallpaper.name)”. \(error.localizedDescription)"
                }
            }
        }
    }

    func cancel(_ wallpaper: CatalogWallpaper) {
        tasks[wallpaper.id]?.cancel()
    }

    // MARK: Fetching

    /// Tries each source URL in order. Transient network errors are retried with backoff;
    /// an HTTP error moves on to the next (lower quality) source.
    private func fetch(_ wallpaper: CatalogWallpaper, to destination: URL) async throws {
        var lastError: Error = CatalogClient.CatalogError.unavailable
        for source in CatalogClient.sourceURLs(for: wallpaper) {
            for attempt in 0..<3 {
                do {
                    try await Self.download(source, to: destination) { fraction in
                        Task { @MainActor in
                            guard self.active[wallpaper.id] != nil else { return }
                            self.active[wallpaper.id] = CatalogDownload(progress: fraction)
                        }
                    }
                    return
                } catch {
                    if Self.isCancellation(error) { throw error }
                    lastError = error
                    guard error is URLError, attempt < 2 else { break }
                    try await Task.sleep(for: .seconds(1 << attempt))
                }
            }
        }
        throw lastError
    }

    private final class TaskBox: @unchecked Sendable {
        var task: URLSessionDownloadTask?
        var observation: NSKeyValueObservation?
    }

    private nonisolated static func download(
        _ url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let box = TaskBox()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = CatalogClient.downloadSession.downloadTask(with: url) { location, response, error in
                    box.observation = nil
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard let location, (200..<300).contains(status) else {
                        continuation.resume(throwing: CatalogClient.CatalogError.http(status))
                        return
                    }
                    // The temporary file is deleted when this handler returns: move it now.
                    do {
                        try? FileManager.default.removeItem(at: destination)
                        try FileManager.default.moveItem(at: location, to: destination)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                box.observation = task.progress.observe(\.fractionCompleted) { value, _ in
                    progress(value.fractionCompleted)
                }
                box.task = task
                task.resume()
                if Task.isCancelled { task.cancel() }
            }
        } onCancel: {
            box.task?.cancel()
        }
    }

    // MARK: Helpers

    private static func fileName(for wallpaper: CatalogWallpaper) -> String {
        let cleaned = wallpaper.name
            .components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "Wallpaper" : String(cleaned.prefix(120))
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
