import AppKit
import AVKit
import AVFoundation

/// A borderless window that can still become key, so it receives the keystroke that dismisses it.
private final class PreviewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Plays a catalog preview full screen, over everything, until any key (or Esc) is pressed.
/// Uses AppKit's `AVPlayerView` (not SwiftUI `VideoPlayer`, which crashes on launch here).
@MainActor
final class CatalogPreviewController {
    static let shared = CatalogPreviewController()

    private var window: PreviewWindow?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var keyMonitor: Any?

    private init() {}

    func show(url: URL, title: String) {
        close()
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))

        let window = PreviewWindow(
            contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen
        )
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false

        let container = NSView(frame: screen.frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        let playerView = AVPlayerView(frame: screen.frame)
        playerView.player = player
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        playerView.autoresizingMask = [.width, .height]
        container.addSubview(playerView)
        container.addSubview(makeHint(title: title, width: screen.frame.width))
        window.contentView = container

        self.window = window
        self.player = player
        self.looper = looper

        // Any key press, a click anywhere, or Esc dismisses. Returning nil swallows the event (no beep).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] _ in
            self?.close()
            return nil
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        player.play()
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
        window?.orderOut(nil)
        window = nil
    }

    private func makeHint(title: String, width: CGFloat) -> NSView {
        let label = NSTextField(labelWithString: "\(title)   ·   Press any key or Esc to exit")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()

        let pill = NSView(frame: NSRect(
            x: (width - label.frame.width - 40) / 2, y: 48,
            width: label.frame.width + 40, height: label.frame.height + 20
        ))
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        pill.layer?.cornerRadius = (label.frame.height + 20) / 2
        pill.autoresizingMask = [.minXMargin, .maxXMargin]
        label.frame = NSRect(x: 20, y: 10, width: label.frame.width, height: label.frame.height)
        pill.addSubview(label)

        // Fade the hint out after a few seconds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.8
                pill.animator().alphaValue = 0
            }
        }
        return pill
    }
}
