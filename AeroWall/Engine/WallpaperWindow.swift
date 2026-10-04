import AppKit
import AVFoundation
import SpriteKit

/// Borderless window pinned to the desktop level of one screen: below the icons,
/// above the system wallpaper. Holds two player layers so videos can crossfade.
final class WallpaperWindow: NSWindow {
    private static let crossfadeDuration: CFTimeInterval = 1.2
    private static let parallaxMargin: CGFloat = 28

    private let videoHost = CALayer()
    private let playerLayers = [AVPlayerLayer(), AVPlayerLayer()]
    private var activeIndex = 0
    private var isRevealPending = false
    private var readyObservation: NSKeyValueObservation?

    private let effectsView: SKView
    private var effectsScene: ParticleScene?

    private var parallaxEnabled = false
    private var parallaxOffset = CGPoint.zero

    /// Whether System Settings → Menu Bar → "Show menu bar background" is on. With it on,
    /// macOS 26 turns the bar solid black over any window beneath it; with it off the bar is
    /// fully transparent and the video can run underneath.
    static var menuBarHasBackground: Bool {
        let key = "SLSMenuBarUseBlurredAppearance" as CFString
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        return CFPreferencesCopyAppValue(key, kCFPreferencesAnyApplication) as? Bool ?? false
    }

    /// The whole screen, or the screen minus the menu bar strip when the bar has a background
    /// (it then shows the desktop picture, which `DesktopPictureSync` keeps in step with the video).
    static func wallpaperFrame(for screen: NSScreen, menuBarHasBackground: Bool) -> NSRect {
        guard menuBarHasBackground else { return screen.frame }
        let menuBarInset = max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top)
        var frame = screen.frame
        frame.size.height -= menuBarInset
        return frame
    }

    init(screen: NSScreen, menuBarHasBackground: Bool) {
        let frame = Self.wallpaperFrame(for: screen, menuBarHasBackground: menuBarHasBackground)
        let bounds = CGRect(origin: .zero, size: frame.size)
        effectsView = SKView(frame: bounds)
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)

        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        hasShadow = false
        animationBehavior = .none
        backgroundColor = .black
        isOpaque = true

        let root = NSView(frame: bounds)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor
        root.layer?.addSublayer(videoHost)
        for layer in playerLayers {
            layer.videoGravity = .resizeAspectFill
            layer.opacity = 0
            videoHost.addSublayer(layer)
        }

        effectsView.allowsTransparency = true
        effectsView.ignoresSiblingOrder = true
        effectsView.preferredFramesPerSecond = 30
        effectsView.autoresizingMask = [.width, .height]
        effectsView.isHidden = true
        root.addSubview(effectsView)

        contentView = root
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        layoutVideo()
    }

    // MARK: Video

    /// Shows `player`, crossfading from the current video once the new one has a frame ready.
    func show(player: AVPlayer, animated: Bool) {
        if playerLayers[activeIndex].player === player { return }

        // A reveal that hasn't started yet is simply retargeted, so the visible video never blinks.
        let incomingIndex = isRevealPending ? activeIndex : 1 - activeIndex
        let incoming = playerLayers[incomingIndex]
        let outgoing = playerLayers[1 - incomingIndex]
        activeIndex = incomingIndex
        isRevealPending = true
        readyObservation = nil
        incoming.player = player

        let reveal: () -> Void = { [weak self, weak incoming, weak outgoing] in
            guard let self, let incoming, let outgoing,
                  self.isRevealPending, self.playerLayers[self.activeIndex] === incoming else { return }
            self.crossfade(to: incoming, from: outgoing, animated: animated)
        }
        if incoming.isReadyForDisplay {
            reveal()
        } else {
            readyObservation = incoming.observe(\.isReadyForDisplay, options: [.new]) { layer, _ in
                guard layer.isReadyForDisplay else { return }
                DispatchQueue.main.async(execute: reveal)
            }
        }
    }

    private func crossfade(to incoming: AVPlayerLayer, from outgoing: AVPlayerLayer, animated: Bool) {
        isRevealPending = false
        readyObservation = nil

        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(Self.crossfadeDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        CATransaction.setCompletionBlock { [weak self, weak outgoing] in
            guard let self, let outgoing, outgoing !== self.playerLayers[self.activeIndex] else { return }
            outgoing.player = nil
        }
        incoming.opacity = 1
        outgoing.opacity = 0
        CATransaction.commit()
    }

    func clear() {
        readyObservation = nil
        isRevealPending = false
        for layer in playerLayers {
            layer.player = nil
            layer.opacity = 0
        }
        effectsView.presentScene(nil)
        effectsScene = nil
    }

    func setScaling(_ scaling: VideoScaling) {
        let gravity: AVLayerVideoGravity
        switch scaling {
        case .fill: gravity = .resizeAspectFill
        case .fit: gravity = .resizeAspect
        case .stretch: gravity = .resize
        }
        for layer in playerLayers where layer.videoGravity != gravity {
            layer.videoGravity = gravity
        }
    }

    // MARK: Parallax

    func setParallaxEnabled(_ enabled: Bool) {
        guard enabled != parallaxEnabled else { return }
        parallaxEnabled = enabled
        parallaxOffset = .zero
        layoutVideo()
    }

    private func layoutVideo() {
        guard let bounds = contentView?.bounds else { return }
        let margin = parallaxEnabled ? Self.parallaxMargin : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoHost.frame = bounds
            .insetBy(dx: -margin, dy: -margin)
            .offsetBy(dx: parallaxOffset.x * margin, dy: parallaxOffset.y * margin)
        for layer in playerLayers {
            layer.frame = videoHost.bounds
        }
        CATransaction.commit()
    }

    /// Called ~30×/s with the global pointer position while effects or parallax need it.
    func trackPointer(_ globalPoint: NSPoint) {
        let onThisScreen = frame.contains(globalPoint)
        let local = CGPoint(x: globalPoint.x - frame.minX, y: globalPoint.y - frame.minY)
        effectsScene?.setRepulsor(at: onThisScreen ? local : nil)

        guard parallaxEnabled else { return }
        var target = CGPoint.zero
        if onThisScreen, frame.width > 0, frame.height > 0 {
            // The video drifts away from the pointer, as if it sat behind the desktop.
            target = CGPoint(x: 1 - 2 * local.x / frame.width, y: 1 - 2 * local.y / frame.height)
        }
        let next = CGPoint(
            x: parallaxOffset.x + (target.x - parallaxOffset.x) * 0.08,
            y: parallaxOffset.y + (target.y - parallaxOffset.y) * 0.08
        )
        guard abs(next.x - parallaxOffset.x) > 0.0005 || abs(next.y - parallaxOffset.y) > 0.0005 else { return }
        parallaxOffset = next
        layoutVideo()
    }

    // MARK: Effects

    func configureEffect(_ kind: ParticleScene.Kind?, intensity: Double, interactive: Bool) {
        guard let kind else {
            if effectsScene != nil {
                effectsView.presentScene(nil)
                effectsScene = nil
            }
            effectsView.isHidden = true
            return
        }
        let scene: ParticleScene
        if let existing = effectsScene {
            scene = existing
        } else {
            scene = ParticleScene(size: effectsView.bounds.size)
            effectsView.presentScene(scene)
            effectsScene = scene
        }
        scene.configure(kind: kind, intensity: intensity, interactive: interactive)
        effectsView.isHidden = false
    }

    func setEffectsPaused(_ paused: Bool) {
        if effectsView.isPaused != paused { effectsView.isPaused = paused }
    }
}
