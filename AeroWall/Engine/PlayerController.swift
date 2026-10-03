import AppKit
import AVFoundation

class PlayerController {
    let window: NSWindow
    var player: AVQueuePlayer?
    var looper: AVPlayerLooper?
    let playerLayer: AVPlayerLayer
    
    init(screen: NSScreen, videoURL: URL) {
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.backgroundColor = .black
        
        let player = AVQueuePlayer()
        self.player = player
        player.isMuted = true
        
        let item = AVPlayerItem(url: videoURL)
        looper = AVPlayerLooper(player: player, templateItem: item)
        
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = window.contentView!.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        
        let view = NSView(frame: window.contentView!.bounds)
        view.wantsLayer = true
        view.layer?.addSublayer(playerLayer)
        window.contentView = view
        
        window.makeKeyAndOrderFront(nil)
    }
    
    func play() {
        player?.play()
    }
    
    func pause() {
        player?.pause()
    }
}
