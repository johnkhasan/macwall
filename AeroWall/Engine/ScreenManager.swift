import AppKit
import AVFoundation

class ScreenManager {
    static let shared = ScreenManager()
    
    private var windows: [CGDirectDisplayID: WallpaperWindow] = [:]
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    
    func playVideo(at url: URL) {
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
            }
        }
        
        for (displayID, window) in windows {
            if !activeDisplays.contains(displayID) {
                window.close()
                windows.removeValue(forKey: displayID)
            }
        }
    }
}
