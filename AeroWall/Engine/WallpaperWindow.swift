import AppKit
import AVFoundation

class WallpaperWindow: NSWindow {
    let playerLayer: AVPlayerLayer
    
    init(screen: NSScreen, player: AVPlayer) {
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.ignoresMouseEvents = true
        self.backgroundColor = .black
        
        playerLayer.frame = self.contentView!.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        
        let view = NSView(frame: self.contentView!.bounds)
        view.wantsLayer = true
        view.layer?.addSublayer(playerLayer)
        self.contentView = view
        
        self.setFrameOrigin(screen.frame.origin)
    }
}
