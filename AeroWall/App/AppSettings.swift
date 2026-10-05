import Foundation
import Combine

enum OverlayEffect: String, CaseIterable, Identifiable {
    case none = "None"
    case rain = "Rain"
    case snow = "Snow"
    case particles = "Particles"
    case weather = "Weather"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .rain: return "Rain"
        case .snow: return "Snow"
        case .particles: return "Fireflies"
        case .weather: return "Live Weather"
        }
    }

    var icon: String {
        switch self {
        case .none: return "circle.slash"
        case .rain: return "cloud.rain"
        case .snow: return "snowflake"
        case .particles: return "sparkles"
        case .weather: return "cloud.sun"
        }
    }
}

enum VideoScaling: String, CaseIterable, Identifiable {
    case fill, fit, stretch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: return "Fill Screen"
        case .fit: return "Fit to Screen"
        case .stretch: return "Stretch"
        }
    }
}

/// Single source of truth for user preferences. Every property persists to `UserDefaults`.
/// Videos are referenced by file name inside the library folder so the library can move safely.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let wallpaper = "wallpaper"
        static let legacyVideoPath = "lastVideoPath"
        static let sameOnAllDisplays = "sameOnAllDisplays"
        static let displayAssignments = "displayAssignments"
        static let videoScaling = "videoScaling"
        static let muteAudio = "muteAudio"
        static let volume = "volume"
        static let syncDesktopPicture = "syncDesktopPicture"
        static let pauseOnBattery = "pauseOnBattery"
        static let pauseOnOcclusion = "pauseOnOcclusion"
        static let pauseOnSleep = "pauseOnSleep"
        static let pauseOnLowPower = "pauseOnLowPower"
        static let pauseOnThermal = "pauseOnThermal"
        static let playlistEnabled = "playlistEnabled"
        static let playlist = "playlist"
        static let playlistInterval = "playlistInterval"
        static let playlistShuffle = "playlistShuffle"
        static let appearanceSwitching = "appearanceSwitching"
        static let lightWallpaper = "lightWallpaper"
        static let darkWallpaper = "darkWallpaper"
        static let effect = "activeEffect"
        static let effectIntensity = "effectIntensity"
        static let mouseInteraction = "mouseInteraction"
        static let parallax = "parallax"
        static let weatherPlace = "weatherPlace"
        static let weatherLatitude = "weatherLatitude"
        static let weatherLongitude = "weatherLongitude"
        static let convertOnImport = "convertOnImport"
        static let catalogDownloads = "catalogDownloads"
        static let screenSaverEnabled = "screenSaverEnabled"
        static let screenSaverVideo = "screenSaverVideo"
        static let hasLaunchedBefore = "hasLaunchedBefore"
    }

    private let defaults = UserDefaults.standard

    // MARK: Wallpaper

    @Published var wallpaper: String? { didSet { store(wallpaper, Keys.wallpaper) } }
    @Published var sameOnAllDisplays: Bool { didSet { store(sameOnAllDisplays, Keys.sameOnAllDisplays) } }
    /// Display UUID → video file name.
    @Published var displayAssignments: [String: String] { didSet { store(displayAssignments, Keys.displayAssignments) } }
    @Published var videoScaling: VideoScaling { didSet { store(videoScaling.rawValue, Keys.videoScaling) } }
    @Published var syncDesktopPicture: Bool { didSet { store(syncDesktopPicture, Keys.syncDesktopPicture) } }

    // MARK: Audio

    @Published var muteAudio: Bool { didSet { store(muteAudio, Keys.muteAudio) } }
    @Published var volume: Double { didSet { store(volume, Keys.volume) } }

    // MARK: Energy

    @Published var pauseOnBattery: Bool { didSet { store(pauseOnBattery, Keys.pauseOnBattery) } }
    @Published var pauseOnOcclusion: Bool { didSet { store(pauseOnOcclusion, Keys.pauseOnOcclusion) } }
    @Published var pauseOnSleep: Bool { didSet { store(pauseOnSleep, Keys.pauseOnSleep) } }
    @Published var pauseOnLowPower: Bool { didSet { store(pauseOnLowPower, Keys.pauseOnLowPower) } }
    @Published var pauseOnThermal: Bool { didSet { store(pauseOnThermal, Keys.pauseOnThermal) } }

    // MARK: Schedule

    @Published var playlistEnabled: Bool { didSet { store(playlistEnabled, Keys.playlistEnabled) } }
    @Published var playlist: [String] { didSet { store(playlist, Keys.playlist) } }
    @Published var playlistInterval: TimeInterval { didSet { store(playlistInterval, Keys.playlistInterval) } }
    @Published var playlistShuffle: Bool { didSet { store(playlistShuffle, Keys.playlistShuffle) } }
    @Published var appearanceSwitching: Bool { didSet { store(appearanceSwitching, Keys.appearanceSwitching) } }
    @Published var lightWallpaper: String? { didSet { store(lightWallpaper, Keys.lightWallpaper) } }
    @Published var darkWallpaper: String? { didSet { store(darkWallpaper, Keys.darkWallpaper) } }

    // MARK: Effects

    @Published var effect: OverlayEffect { didSet { store(effect.rawValue, Keys.effect) } }
    @Published var effectIntensity: Double { didSet { store(effectIntensity, Keys.effectIntensity) } }
    @Published var mouseInteraction: Bool { didSet { store(mouseInteraction, Keys.mouseInteraction) } }
    @Published var parallax: Bool { didSet { store(parallax, Keys.parallax) } }
    @Published var weatherPlace: String? { didSet { store(weatherPlace, Keys.weatherPlace) } }
    @Published var weatherLatitude: Double? { didSet { store(weatherLatitude, Keys.weatherLatitude) } }
    @Published var weatherLongitude: Double? { didSet { store(weatherLongitude, Keys.weatherLongitude) } }

    // MARK: General

    @Published var convertOnImport: Bool { didSet { store(convertOnImport, Keys.convertOnImport) } }
    /// Online catalog wallpaper id → video file name it was saved as.
    @Published var catalogDownloads: [String: String] { didSet { store(catalogDownloads, Keys.catalogDownloads) } }

    // MARK: Screen saver

    @Published var screenSaverEnabled: Bool { didSet { store(screenSaverEnabled, Keys.screenSaverEnabled) } }
    /// Video file name to use as the screen saver, or nil to follow the current wallpaper.
    @Published var screenSaverVideo: String? { didSet { store(screenSaverVideo, Keys.screenSaverVideo) } }
    @Published var hasLaunchedBefore: Bool { didSet { store(hasLaunchedBefore, Keys.hasLaunchedBefore) } }

    private init() {
        defaults.register(defaults: [
            Keys.sameOnAllDisplays: true,
            Keys.videoScaling: VideoScaling.fill.rawValue,
            Keys.syncDesktopPicture: true,
            Keys.muteAudio: true,
            Keys.volume: 0.5,
            Keys.pauseOnBattery: true,
            Keys.pauseOnOcclusion: true,
            Keys.pauseOnSleep: true,
            Keys.pauseOnLowPower: true,
            Keys.pauseOnThermal: true,
            Keys.playlistInterval: 1800.0,
            Keys.effect: OverlayEffect.none.rawValue,
            Keys.effectIntensity: 0.5,
            Keys.mouseInteraction: true,
            Keys.convertOnImport: true,
        ])

        var wallpaper = defaults.string(forKey: Keys.wallpaper)
        if wallpaper == nil, let legacyPath = defaults.string(forKey: Keys.legacyVideoPath) {
            wallpaper = URL(fileURLWithPath: legacyPath).lastPathComponent
            defaults.set(wallpaper, forKey: Keys.wallpaper)
        }
        self.wallpaper = wallpaper
        sameOnAllDisplays = defaults.bool(forKey: Keys.sameOnAllDisplays)
        displayAssignments = defaults.dictionary(forKey: Keys.displayAssignments) as? [String: String] ?? [:]
        videoScaling = VideoScaling(rawValue: defaults.string(forKey: Keys.videoScaling) ?? "") ?? .fill
        syncDesktopPicture = defaults.bool(forKey: Keys.syncDesktopPicture)
        muteAudio = defaults.bool(forKey: Keys.muteAudio)
        volume = defaults.double(forKey: Keys.volume)
        pauseOnBattery = defaults.bool(forKey: Keys.pauseOnBattery)
        pauseOnOcclusion = defaults.bool(forKey: Keys.pauseOnOcclusion)
        pauseOnSleep = defaults.bool(forKey: Keys.pauseOnSleep)
        pauseOnLowPower = defaults.bool(forKey: Keys.pauseOnLowPower)
        pauseOnThermal = defaults.bool(forKey: Keys.pauseOnThermal)
        playlistEnabled = defaults.bool(forKey: Keys.playlistEnabled)
        playlist = defaults.stringArray(forKey: Keys.playlist) ?? []
        playlistInterval = defaults.double(forKey: Keys.playlistInterval)
        playlistShuffle = defaults.bool(forKey: Keys.playlistShuffle)
        appearanceSwitching = defaults.bool(forKey: Keys.appearanceSwitching)
        lightWallpaper = defaults.string(forKey: Keys.lightWallpaper)
        darkWallpaper = defaults.string(forKey: Keys.darkWallpaper)
        effect = OverlayEffect(rawValue: defaults.string(forKey: Keys.effect) ?? "") ?? .none
        effectIntensity = defaults.double(forKey: Keys.effectIntensity)
        mouseInteraction = defaults.bool(forKey: Keys.mouseInteraction)
        parallax = defaults.bool(forKey: Keys.parallax)
        weatherPlace = defaults.string(forKey: Keys.weatherPlace)
        weatherLatitude = defaults.object(forKey: Keys.weatherLatitude) as? Double
        weatherLongitude = defaults.object(forKey: Keys.weatherLongitude) as? Double
        convertOnImport = defaults.bool(forKey: Keys.convertOnImport)
        catalogDownloads = defaults.dictionary(forKey: Keys.catalogDownloads) as? [String: String] ?? [:]
        screenSaverEnabled = defaults.bool(forKey: Keys.screenSaverEnabled)
        screenSaverVideo = defaults.string(forKey: Keys.screenSaverVideo)
        hasLaunchedBefore = defaults.bool(forKey: Keys.hasLaunchedBefore)
    }

    private func store(_ value: Any?, _ key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: Library references

    func togglePlaylist(_ name: String) {
        if let index = playlist.firstIndex(of: name) {
            playlist.remove(at: index)
        } else {
            playlist.append(name)
        }
    }

    /// Points every reference to `old` at `new`, or drops it when `new` is nil (file deleted).
    func replaceReferences(to old: String, with new: String?) {
        if wallpaper == old { wallpaper = new }
        if lightWallpaper == old { lightWallpaper = new }
        if darkWallpaper == old { darkWallpaper = new }
        if screenSaverVideo == old { screenSaverVideo = new }
        if displayAssignments.values.contains(old) {
            displayAssignments = displayAssignments.compactMapValues { $0 == old ? new : $0 }
        }
        if playlist.contains(old) {
            playlist = playlist.compactMap { $0 == old ? new : $0 }
        }
        if catalogDownloads.values.contains(old) {
            catalogDownloads = catalogDownloads.compactMapValues { $0 == old ? new : $0 }
        }
    }
}
