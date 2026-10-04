import AppKit
import AVFoundation

/// Sets a still frame of the live wallpaper as the macOS desktop picture, so the lock screen,
/// login window and Mission Control (which never show our window) match the video.
@MainActor
final class DesktopPictureSync {
    static let shared = DesktopPictureSync()

    private let directory: URL
    private var tasks: [String: Task<Void, Never>] = [:]

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("AeroWall/Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func update(displayUUID: String, video: URL) {
        tasks[displayUUID]?.cancel()
        tasks[displayUUID] = Task { [directory] in
            // Many clips open on a black fade-in; a frame a quarter in represents the video better
            // and is what the translucent menu bar shows on top of.
            let duration = (try? await AVURLAsset(url: video).load(.duration).seconds) ?? 0
            let time = duration.isFinite && duration > 0 ? duration * 0.25 : 0
            guard let frame = await ThumbnailGenerator.frame(for: video, at: time, maxSize: nil),
                  !Task.isCancelled else { return }

            // macOS caches pictures by URL, so every snapshot needs a fresh file name.
            let prefix = "\(displayUUID)-"
            let file = directory.appendingPathComponent("\(prefix)\(UUID().uuidString.prefix(8)).jpg")
            let written = await Task.detached(priority: .utility) {
                guard let data = NSBitmapImageRep(cgImage: frame)
                    .representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return false }
                return (try? data.write(to: file, options: .atomic)) != nil
            }.value
            guard written, !Task.isCancelled,
                  let screen = NSScreen.screens.first(where: { $0.displayUUID == displayUUID }) else { return }

            do {
                try NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                    .allowClipping: true,
                ])
            } catch {
                return
            }

            let stale = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for old in stale where old.lastPathComponent.hasPrefix(prefix) && old != file {
                try? FileManager.default.removeItem(at: old)
            }
        }
    }
}
