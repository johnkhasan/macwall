import AVFoundation

/// One looping, decoded video. Every window showing the same file shares a controller,
/// so the video is decoded only once no matter how many displays show it.
final class PlayerController {
    let url: URL
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private(set) var isPlaying = false

    init(url: URL) {
        self.url = url
        player.isMuted = true
        // A wallpaper must never keep the display awake.
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: AVURLAsset(url: url)))
    }

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        player.play()
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        player.pause()
    }

    func setAudio(muted: Bool, volume: Float) {
        if player.isMuted != muted { player.isMuted = muted }
        if player.volume != volume { player.volume = volume }
    }

    func stop() {
        pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
    }
}
