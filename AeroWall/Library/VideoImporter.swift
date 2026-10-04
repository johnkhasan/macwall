import AVFoundation
import AppKit

struct VideoMetadata: Equatable {
    var duration: Double
    var pixelSize: CGSize
    var isHEVC: Bool

    var resolutionLabel: String {
        let shortSide = Int(min(pixelSize.width, pixelSize.height).rounded())
        switch shortSide {
        case 2160...: return "4K"
        case 1440...: return "1440p"
        case 1080...: return "1080p"
        case 720...: return "720p"
        default: return "\(shortSide)p"
        }
    }

    var durationLabel: String {
        guard duration.isFinite else { return "--:--" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

enum VideoImporter {
    enum ImportError: LocalizedError {
        case notAVideo(String)

        var errorDescription: String? {
            switch self {
            case .notAVideo(let name): return "“\(name)” is not a playable video."
            }
        }
    }

    static func inspect(_ asset: AVAsset) async throws -> VideoMetadata? {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        let (naturalSize, transform, formats) = try await track.load(.naturalSize, .preferredTransform, .formatDescriptions)
        let duration = try await asset.load(.duration).seconds
        let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform).size
        let isHEVC = formats.contains {
            let codec = CMFormatDescriptionGetMediaSubType($0)
            return codec == kCMVideoCodecType_HEVC || codec == kCMVideoCodecType_HEVCWithAlpha
        }
        return VideoMetadata(
            duration: duration,
            pixelSize: CGSize(width: abs(oriented.width), height: abs(oriented.height)),
            isHEVC: isHEVC
        )
    }

    /// Copies (or converts to HEVC when that saves decode work) a video into the library folder.
    /// Never overwrites an existing file: duplicates get a numbered name.
    static func importVideo(
        from source: URL,
        into directory: URL,
        convert: Bool,
        displayLongestSide: CGFloat,
        progress: @escaping @Sendable (Double, Bool) -> Void
    ) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard try await asset.load(.isPlayable), let metadata = try await inspect(asset) else {
            throw ImportError.notAVideo(source.lastPathComponent)
        }

        let baseName = source.deletingPathExtension().lastPathComponent
        let oversized = max(metadata.pixelSize.width, metadata.pixelSize.height) > displayLongestSide * 1.2
        if convert && (!metadata.isHEVC || oversized) {
            let destination = uniqueURL(in: directory, baseName: baseName, extension: "mov")
            let preset = HEVCConverter.preset(videoSize: metadata.pixelSize, displayLongestSide: displayLongestSide)
            do {
                try await HEVCConverter.convert(asset: asset, to: destination, preset: preset) { progress($0, true) }
                return destination
            } catch {
                try? FileManager.default.removeItem(at: destination)
                // Fall through to a plain copy: a playable original beats no wallpaper.
            }
        }

        let destination = uniqueURL(in: directory, baseName: baseName, extension: source.pathExtension.lowercased())
        progress(0, false)
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.copyItem(at: source, to: destination)
        }.value
        progress(1, false)
        return destination
    }

    static func uniqueURL(in directory: URL, baseName: String, extension ext: String) -> URL {
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }
}
