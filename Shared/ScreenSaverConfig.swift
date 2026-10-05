import Foundation

/// Written into the installed screen saver's own Resources at install time, and read back by the
/// saver from its own bundle. The saver runs sandboxed (legacyScreenSaver) and can only read files
/// inside its loaded bundle, so the chosen video is embedded there rather than referenced by path.
struct ScreenSaverConfig: Codable {
    /// File name of the video embedded alongside this config in the saver's Resources.
    var videoFileName: String
    /// "fill" | "fit" | "stretch".
    var scaling: String
    var muted: Bool

    static let fileName = "config.json"

    /// Loads the config sitting next to the saver binary, and the video it points at.
    static func loadFromOwnBundle(of anyClass: AnyClass) -> (config: ScreenSaverConfig, videoURL: URL)? {
        let bundle = Bundle(for: anyClass)
        guard let resources = bundle.resourceURL,
              let data = try? Data(contentsOf: resources.appendingPathComponent(fileName)),
              let config = try? JSONDecoder().decode(ScreenSaverConfig.self, from: data) else {
            return nil
        }
        let videoURL = resources.appendingPathComponent(config.videoFileName)
        guard FileManager.default.fileExists(atPath: videoURL.path) else { return nil }
        return (config, videoURL)
    }
}
