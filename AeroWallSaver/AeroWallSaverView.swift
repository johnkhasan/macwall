import ScreenSaver
import AVKit
import AVFoundation

/// A screen saver that loops the live wallpaper the user picked in AeroWall.
/// The class name is exported to Objective-C so the Info.plist `NSPrincipalClass` can find it.
@objc(AeroWallSaverView)
final class AeroWallSaverView: ScreenSaverView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerView: AVPlayerView?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        animationTimeInterval = 1.0 / 30.0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    override func startAnimation() {
        super.startAnimation()
        buildPlayer()
    }

    override func stopAnimation() {
        super.stopAnimation()
        teardown()
    }

    private func buildPlayer() {
        teardown()
        // Read the video embedded in this saver's own bundle: the sandbox blocks everything else.
        guard let loaded = ScreenSaverConfig.loadFromOwnBundle(of: AeroWallSaverView.self) else { return }
        let config = loaded.config
        let url = loaded.videoURL

        let player = AVQueuePlayer()
        player.isMuted = config.muted
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))

        // AVPlayerView renders reliably; a hand-rolled AVPlayerLayer can come up black here.
        let playerView = AVPlayerView(frame: bounds)
        playerView.player = player
        playerView.controlsStyle = .none
        playerView.videoGravity = Self.gravity(for: config.scaling)
        playerView.autoresizingMask = [.width, .height]
        addSubview(playerView)

        self.player = player
        self.playerView = playerView
        player.play()
    }

    private func teardown() {
        player?.pause()
        player = nil
        looper = nil
        playerView?.removeFromSuperview()
        playerView = nil
    }

    private static func gravity(for scaling: String) -> AVLayerVideoGravity {
        switch scaling {
        case "fit": return .resizeAspect
        case "stretch": return .resize
        default: return .resizeAspectFill
        }
    }

    // The screen saver framework has no config sheet for this saver.
    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
