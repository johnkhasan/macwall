import AppKit

/// Installs a copy of the bundled `.saver` with the chosen video embedded in its Resources, then
/// opens the system pane. The video is embedded (not referenced by path) because the installed
/// saver runs sandboxed and can only read files inside its own bundle.
enum ScreenSaverInstaller {
    static let installedName = "AeroWall.saver"

    enum InstallError: LocalizedError {
        case bundleMissing
        case noVideo
        case signingFailed(String)

        var errorDescription: String? {
            switch self {
            case .bundleMissing: return "The screen saver component is missing from this build."
            case .noVideo: return "Pick a screen saver video first (or set a desktop wallpaper)."
            case .signingFailed(let detail): return "Could not sign the screen saver.\n\(detail)"
            }
        }
    }

    /// The `.saver` template embedded inside the app bundle (Contents/PlugIns).
    static var bundledSaver: URL? {
        guard let plugins = Bundle.main.builtInPlugInsURL else { return nil }
        let url = plugins.appendingPathComponent("AeroWallSaver.saver")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static var destination: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Screen Savers", isDirectory: true)
            .appendingPathComponent(installedName)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: destination.path)
    }

    @discardableResult
    static func install(videoURL: URL?, scaling: String, muted: Bool) throws -> URL {
        guard let template = bundledSaver else { throw InstallError.bundleMissing }
        guard let videoURL, FileManager.default.fileExists(atPath: videoURL.path) else { throw InstallError.noVideo }
        let fm = FileManager.default

        let staging = fm.temporaryDirectory.appendingPathComponent("AeroWall-saver-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let work = staging.appendingPathComponent(installedName)
        try fm.copyItem(at: template, to: work)

        let resources = work.appendingPathComponent("Contents/Resources", isDirectory: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        let ext = videoURL.pathExtension.isEmpty ? "mov" : videoURL.pathExtension.lowercased()
        let embeddedName = "wallpaper.\(ext)"
        try fm.copyItem(at: videoURL, to: resources.appendingPathComponent(embeddedName))

        let config = ScreenSaverConfig(videoFileName: embeddedName, scaling: scaling, muted: muted)
        try JSONEncoder().encode(config).write(to: resources.appendingPathComponent(ScreenSaverConfig.fileName))

        // The bundle contents changed, so its signature is stale; re-sign ad-hoc or it won't load.
        try codesign(work)

        let destination = destination
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: work, to: destination)
        return destination
    }

    static func uninstall() {
        try? FileManager.default.removeItem(at: destination)
    }

    /// Opens System Settings at the Screen Saver pane (falls back to the legacy pane).
    static func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.desktopscreeneffect",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    private static func codesign(_ bundle: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--deep", "--sign", "-", bundle.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        do {
            try process.run()
        } catch {
            throw InstallError.signingFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw InstallError.signingFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
