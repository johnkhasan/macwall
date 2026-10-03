import AppKit

class PlaylistManager {
    static let shared = PlaylistManager()
    
    var playlist: [URL] = []
    var currentIndex = 0
    var interval: TimeInterval = 3600 // 1 hour
    private var timer: Timer?
    
    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.nextVideo()
        }
    }
    
    func nextVideo() {
        guard !playlist.isEmpty else { return }
        currentIndex = (currentIndex + 1) % playlist.count
        let nextURL = playlist[currentIndex]
        
        ScreenManager.shared.playVideo(at: nextURL)
        updateLockScreen(with: nextURL)
    }
    
    func updateLockScreen(with url: URL) {
        Task {
            if let image = await VideoImporter.shared.generateThumbnail(for: url) {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("lockscreen.png")
                if let tiffData = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiffData), let pngData = bitmap.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: tempURL)
                    
                    if let screen = NSScreen.main {
                        try? NSWorkspace.shared.setDesktopImageURL(tempURL, for: screen, options: [:])
                    }
                }
            }
        }
    }
}
