import AppKit
import AVFoundation
import Combine

enum PauseReason: String, CaseIterable {
    case sleep, battery, lowPower, thermal

    var description: String {
        switch self {
        case .sleep: return "display asleep or locked"
        case .battery: return "on battery power"
        case .lowPower: return "Low Power Mode"
        case .thermal: return "Mac is running hot"
        }
    }
}

struct DisplayInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let isMain: Bool
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Stable across reboots and reconnects, unlike `CGDirectDisplayID`.
    var displayUUID: String? {
        guard let id = displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

/// Owns one `WallpaperWindow` per screen and decides what each one plays.
/// `reload()` is idempotent: every change (settings, screens, playlist, appearance) just calls it.
@MainActor
final class ScreenManager: ObservableObject {
    static let shared = ScreenManager()

    @Published private(set) var isUserPaused = false
    @Published private(set) var systemPauseReasons: Set<PauseReason> = []
    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var activeURLs: Set<URL> = []

    private struct Slot {
        let window: WallpaperWindow
        let uuid: String
        var url: URL?
        var syncedURL: URL?
    }

    private var slots: [CGDirectDisplayID: Slot] = [:]
    private var controllers: [URL: PlayerController] = [:]
    private var pointerTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let settings = AppSettings.shared
    private let library = VideoLibrary.shared

    private init() {}

    func start() {
        guard cancellables.isEmpty else { return }

        let center = NotificationCenter.default
        center.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
        center.publisher(for: NSWindow.didChangeOcclusionStateNotification)
            .filter { $0.object is WallpaperWindow }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updatePlayback() }
            .store(in: &cancellables)

        Publishers.MergeMany(
            settings.objectWillChange.eraseToAnyPublisher(),
            library.objectWillChange.eraseToAnyPublisher(),
            AppearanceObserver.shared.objectWillChange.eraseToAnyPublisher(),
            PlaylistManager.shared.objectWillChange.eraseToAnyPublisher(),
            WeatherService.shared.objectWillChange.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(60), scheduler: DispatchQueue.main)
        .sink { [weak self] in self?.reload() }
        .store(in: &cancellables)

        reload()
    }

    // MARK: Public controls

    var isPaused: Bool { isUserPaused || !systemPauseReasons.isEmpty }

    var statusText: String {
        if slots.isEmpty { return "No wallpaper selected" }
        if isUserPaused { return "Paused" }
        if let reason = PauseReason.allCases.first(where: systemPauseReasons.contains) {
            return "Paused — \(reason.description)"
        }
        return "Playing"
    }

    func togglePause() {
        isUserPaused.toggle()
        updatePlayback()
    }

    func setSystemPauseReasons(_ reasons: Set<PauseReason>) {
        guard reasons != systemPauseReasons else { return }
        systemPauseReasons = reasons
        updatePlayback()
    }

    /// Shows `item` on one display, or on every display when `displayUUID` is nil.
    func setWallpaper(_ item: VideoItem, displayUUID: String? = nil) {
        if let displayUUID {
            settings.displayAssignments[displayUUID] = item.name
        } else {
            settings.wallpaper = item.name
            if !settings.displayAssignments.isEmpty { settings.displayAssignments = [:] }
        }
        // An explicit pick wins over the rotation unless it is part of the playlist.
        if settings.playlistEnabled {
            if let index = settings.playlist.firstIndex(of: item.name) {
                PlaylistManager.shared.jump(to: index)
            } else {
                settings.playlistEnabled = false
            }
        }
        isUserPaused = false
        reload()
    }

    // MARK: Resolution

    private func resolveWallpaper(displayUUID: String, index: Int) -> URL? {
        if settings.appearanceSwitching,
           let name = AppearanceObserver.shared.isDark ? settings.darkWallpaper : settings.lightWallpaper,
           let url = library.url(for: name) {
            return url
        }
        if settings.playlistEnabled {
            let items = settings.playlist.compactMap(library.url(for:))
            if !items.isEmpty {
                let offset = settings.sameOnAllDisplays ? 0 : index
                return items[(PlaylistManager.shared.index + offset) % items.count]
            }
        }
        if !settings.sameOnAllDisplays,
           let name = settings.displayAssignments[displayUUID],
           let url = library.url(for: name) {
            return url
        }
        return settings.wallpaper.flatMap(library.url(for:))
    }

    // MARK: Reload

    func reload() {
        let screens = NSScreen.screens
        var seen = Set<CGDirectDisplayID>()
        var info: [DisplayInfo] = []

        for (index, screen) in screens.enumerated() {
            guard let id = screen.displayID else { continue }
            let uuid = screen.displayUUID ?? String(id)
            seen.insert(id)
            info.append(DisplayInfo(id: uuid, name: screen.localizedName, isMain: index == 0))

            guard let url = resolveWallpaper(displayUUID: uuid, index: index) else {
                removeSlot(id)
                continue
            }

            var slot = slots[id] ?? makeSlot(for: screen, uuid: uuid)
            if slot.window.frame != screen.frame {
                slot.window.setFrame(screen.frame, display: true)
            }
            if slot.url != url {
                slot.window.show(player: controller(for: url).player, animated: slot.url != nil)
                slot.url = url
            }
            if settings.syncDesktopPicture && slot.syncedURL != url {
                DesktopPictureSync.shared.update(displayUUID: uuid, video: url)
                slot.syncedURL = url
            } else if !settings.syncDesktopPicture {
                slot.syncedURL = nil
            }
            slots[id] = slot
        }

        for id in slots.keys where !seen.contains(id) {
            removeSlot(id)
        }
        if info != displays { displays = info }

        retireUnusedControllers()
        applyVisualSettings()
        applyAudio(primaryDisplay: screens.first?.displayID)
        updatePlayback()

        let urls = Set(slots.values.compactMap(\.url))
        if urls != activeURLs { activeURLs = urls }
    }

    private func makeSlot(for screen: NSScreen, uuid: String) -> Slot {
        let window = WallpaperWindow(screen: screen)
        window.orderFront(nil)
        return Slot(window: window, uuid: uuid)
    }

    private func removeSlot(_ id: CGDirectDisplayID) {
        guard let slot = slots.removeValue(forKey: id) else { return }
        slot.window.orderOut(nil)
        slot.window.clear()
        slot.window.close()
    }

    private func controller(for url: URL) -> PlayerController {
        if let existing = controllers[url] { return existing }
        let controller = PlayerController(url: url)
        controllers[url] = controller
        return controller
    }

    private func retireUnusedControllers() {
        let used = Set(slots.values.compactMap(\.url))
        for (url, controller) in controllers where !used.contains(url) {
            controllers[url] = nil
            // Keep decoding until the crossfade away from it has finished.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { controller.stop() }
        }
    }

    private func applyVisualSettings() {
        let kind = currentEffectKind
        for slot in slots.values {
            slot.window.setScaling(settings.videoScaling)
            slot.window.setParallaxEnabled(settings.parallax)
            slot.window.configureEffect(kind, intensity: settings.effectIntensity, interactive: settings.mouseInteraction)
        }
    }

    private var currentEffectKind: ParticleScene.Kind? {
        switch settings.effect {
        case .none: return nil
        case .rain: return .rain
        case .snow: return .snow
        case .particles: return .fireflies
        case .weather: return WeatherService.shared.condition?.effect
        }
    }

    /// Only the video on the main display is audible, so sounds never double up.
    private func applyAudio(primaryDisplay: CGDirectDisplayID?) {
        let audibleURL = primaryDisplay.flatMap { slots[$0]?.url }
        for (url, controller) in controllers {
            controller.setAudio(muted: settings.muteAudio || url != audibleURL, volume: Float(settings.volume))
        }
    }

    // MARK: Playback

    func updatePlayback() {
        let paused = isPaused
        var visibleURLs = Set<URL>()
        for slot in slots.values {
            let visible = !settings.pauseOnOcclusion || slot.window.occlusionState.contains(.visible)
            slot.window.setEffectsPaused(paused || !visible)
            if visible, let url = slot.url { visibleURLs.insert(url) }
        }
        for (url, controller) in controllers {
            if !paused && visibleURLs.contains(url) {
                controller.play()
            } else {
                controller.pause()
            }
        }
        updatePointerTracking()
    }

    private func updatePointerTracking() {
        let wantsPointer = (settings.effect != .none && settings.mouseInteraction) || settings.parallax
        let needed = wantsPointer && !slots.isEmpty && !isPaused
        if needed, pointerTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.trackPointer() }
            }
            RunLoop.main.add(timer, forMode: .common)
            pointerTimer = timer
        } else if !needed, let timer = pointerTimer {
            timer.invalidate()
            pointerTimer = nil
        }
    }

    private func trackPointer() {
        let location = NSEvent.mouseLocation
        for slot in slots.values {
            slot.window.trackPointer(location)
        }
    }
}
