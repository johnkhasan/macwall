import AppKit
import AVFoundation

class ScreenManager {
    static let shared = ScreenManager()
    
    private var windows: [CGDirectDisplayID: WallpaperWindow] = [:]
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged), name: NSWindow.didChangeOcclusionStateNotification, object: nil)
    }
    
    func playVideo(at url: URL) {
        UserDefaults.standard.set(url.path, forKey: "lastVideoPath")
        let player = AVQueuePlayer()
        player.isMuted = true
        self.player = player
        
        let item = AVPlayerItem(url: url)
        self.looper = AVPlayerLooper(player: player, templateItem: item)
        
        updateWindows()
        player.play()
    }
    
    @objc private func handleScreenChange() {
        updateWindows()
    }
    
    @objc private func occlusionChanged(notification: Notification) {
        var anyVisible = false
        for window in windows.values {
            if window.occlusionState.contains(.visible) {
                anyVisible = true
                break
            }
        }
        if anyVisible {
            player?.play()
        } else {
            player?.pause()
        }
    }
    
    func pause() {
        player?.pause()
    }
    
    func resume() {
        player?.play()
    }
    
    private func updateWindows() {
        guard let player = player else { return }
        
        let currentScreens = NSScreen.screens
        var activeDisplays: Set<CGDirectDisplayID> = []
        
        for screen in currentScreens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            activeDisplays.insert(displayID)
            
            if windows[displayID] == nil {
                let window = WallpaperWindow(screen: screen, player: player)
                window.makeKeyAndOrderFront(nil)
                windows[displayID] = window
            } else {
                windows[displayID]?.setFrame(screen.frame, display: true)
                windows[displayID]?.playerLayer.player = player
            }
            
            if let url = (player.currentItem?.asset as? AVURLAsset)?.url {
                setDesktopImage(from: url, for: screen)
            }
        }
        
        for (displayID, window) in windows {
            if !activeDisplays.contains(displayID) {
                window.close()
                windows.removeValue(forKey: displayID)
            }
        }
    }
    
    private func setDesktopImage(from videoURL: URL, for screen: NSScreen) {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        do {
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: .zero)
            
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent("aerowall-bg-\(UUID().uuidString).jpg")
            
            if let tiff = nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                try data.write(to: tempFile)
                try NSWorkspace.shared.setDesktopImageURL(tempFile, for: screen, options: [:])
            }
        } catch {
            print("Failed to set desktop image: \(error)")
        }
    }
}
