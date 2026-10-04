import AVFoundation
import AppKit

@MainActor
final class ThumbnailGenerator {
    static let shared = ThumbnailGenerator()

    private let cache = NSCache<NSURL, NSImage>()

    func thumbnail(for url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        let time = duration.isFinite && duration > 0 ? min(1, duration / 2) : 0
        guard let cgImage = await Self.frame(for: url, at: time, maxSize: CGSize(width: 520, height: 520)) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    func invalidate(_ url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    nonisolated static func frame(for url: URL, at seconds: Double, maxSize: CGSize?) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        if let maxSize { generator.maximumSize = maxSize }
        if seconds == 0 {
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
        }
        do {
            return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        } catch {
            return nil
        }
    }
}
