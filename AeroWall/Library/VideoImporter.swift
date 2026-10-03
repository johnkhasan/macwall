import AVFoundation
import AppKit

class VideoImporter {
    static let shared = VideoImporter()
    
    var appSupportDir: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appDir = paths[0].appendingPathComponent("AeroWall/Videos")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
        return appDir
    }
    
    func importVideo(from sourceURL: URL) -> URL? {
        let destURL = appSupportDir.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return destURL
        } catch {
            print("Error importing video: \(error)")
            return nil
        }
    }
    
    func generateThumbnail(for url: URL) async -> NSImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        
        do {
            let (cgImage, _) = try await generator.image(at: time)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            print("Failed to generate thumbnail: \(error)")
            return nil
        }
    }
    
    func getImportedVideos() -> [URL] {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: appSupportDir, includingPropertiesForKeys: nil)
            return files.filter { $0.pathExtension.lowercased() == "mp4" || $0.pathExtension.lowercased() == "mov" }
        } catch {
            return []
        }
    }
    
    func deleteVideo(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
