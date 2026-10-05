import SwiftUI
import ServiceManagement

enum SidebarItem: String, CaseIterable, Identifiable {
    case library = "Library"
    case discover = "Discover"
    case displays = "Displays & Audio"
    case schedule = "Playlist & Schedule"
    case screensaver = "Screen Saver"
    case effects = "Overlay Effects"
    case energy = "Energy Saving"
    case general = "General"
    case about = "About AeroWall"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .library: return "photo.on.rectangle.angled"
        case .discover: return "globe"
        case .displays: return "display.2"
        case .schedule: return "clock.arrow.2.circlepath"
        case .screensaver: return "moon.stars.fill"
        case .effects: return "wand.and.stars"
        case .energy: return "leaf.fill"
        case .general: return "gearshape.fill"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .library: return .blue
        case .discover: return .teal
        case .displays: return .indigo
        case .schedule: return .orange
        case .screensaver: return .indigo
        case .effects: return .purple
        case .energy: return .green
        case .general: return .gray
        case .about: return .pink
        }
    }
}

struct SettingsView: View {
    @AppStorage("settingsPane") private var selection: SidebarItem = .library

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                NavigationLink(value: item) {
                    Label {
                        Text(item.rawValue)
                    } icon: {
                        SettingsIcon(systemName: item.icon, color: item.color)
                    }
                    .padding(.vertical, 3)
                }
            }
            .safeAreaInset(edge: .bottom) {
                SidebarNowPlaying()
            }
            .navigationTitle("AeroWall")
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } detail: {
            switch selection {
            case .library: LibraryView()
            case .discover: CatalogView()
            case .displays: DisplaySettingsView()
            case .schedule: ScheduleSettingsView()
            case .screensaver: ScreenSaverSettingsView()
            case .effects: EffectsSettingsView()
            case .energy: EnergySettingsView()
            case .general: GeneralSettingsView()
            case .about: AboutView()
            }
        }
        .frame(minWidth: 850, minHeight: 600)
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title).font(.headline)
    }
}

private struct SectionFooter: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

/// Picker over the library, with an optional "none" entry.
private struct VideoPicker: View {
    let title: String
    let noneTitle: String
    @Binding var selection: String?
    @ObservedObject private var library = VideoLibrary.shared

    var body: some View {
        Picker(title, selection: $selection) {
            Text(noneTitle).tag(String?.none)
            if !library.videos.isEmpty { Divider() }
            ForEach(library.videos) { video in
                Text(video.title).tag(Optional(video.name))
            }
        }
    }
}

// MARK: - Displays & Audio

struct DisplaySettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var screens = ScreenManager.shared
    @ObservedObject private var library = VideoLibrary.shared

    var body: some View {
        Form {
            if !screens.displays.isEmpty {
                Section {
                    ViewThatFits(in: .horizontal) {
                        displayRow
                        ScrollView(.horizontal, showsIndicators: false) { displayRow }
                    }
                }
            }

            Section {
                Toggle("Show the same wallpaper on every display", isOn: $settings.sameOnAllDisplays)
                Picker("Scaling", selection: $settings.videoScaling) {
                    ForEach(VideoScaling.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                SectionHeader(title: "Arrangement")
            } footer: {
                SectionFooter(text: "With one video on all displays it is decoded only once, which is the most energy-efficient setup.")
            }

            Section {
                VideoPicker(title: "Default wallpaper", noneTitle: "None (system wallpaper)", selection: $settings.wallpaper)
                if !settings.sameOnAllDisplays {
                    ForEach(screens.displays) { display in
                        VideoPicker(
                            title: display.isMain ? "\(display.name) (main)" : display.name,
                            noneTitle: "Use default",
                            selection: Binding(
                                get: { settings.displayAssignments[display.id] },
                                set: { settings.displayAssignments[display.id] = $0 }
                            )
                        )
                    }
                }
            } header: {
                SectionHeader(title: "Wallpapers")
            } footer: {
                if settings.appearanceSwitching || settings.playlistEnabled {
                    SectionFooter(text: "Light/Dark switching and the playlist take priority over these choices. Configure them in Playlist & Schedule.")
                }
            }

            Section {
                Toggle("Use a still frame as the desktop & lock screen picture", isOn: $settings.syncDesktopPicture)
            } header: {
                SectionHeader(title: "Lock Screen")
            } footer: {
                SectionFooter(text: "macOS does not allow apps to put video on the lock screen, the login window or Mission Control. AeroWall sets the first frame of each wallpaper as the desktop picture so those places match.")
            }

            Section {
                Toggle("Mute wallpaper audio", isOn: $settings.muteAudio)
                LabeledContent("Volume") {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundColor(.secondary)
                        Slider(value: $settings.volume, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill").foregroundColor(.secondary)
                    }
                }
                .disabled(settings.muteAudio)
            } header: {
                SectionHeader(title: "Audio")
            } footer: {
                SectionFooter(text: "Only the wallpaper on the main display plays sound.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SidebarItem.displays.rawValue)
    }

    private var displayRow: some View {
        HStack(alignment: .top, spacing: 28) {
            ForEach(screens.displays) { display in
                DisplayPreview(display: display, url: screens.displayURLs[display.id])
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }
}

private struct DisplayPreview: View {
    let display: DisplayInfo
    let url: URL?

    var body: some View {
        VStack(spacing: 0) {
            VideoThumbnail(url: url)
                .frame(width: 200, height: 125)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.1)))
            // Monitor stand.
            Rectangle()
                .fill(Color(white: 0.45).gradient)
                .frame(width: 36, height: 14)
            Capsule()
                .fill(Color(white: 0.5))
                .frame(width: 80, height: 5)
            HStack(spacing: 6) {
                Text(display.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if display.isMain {
                    Text("MAIN")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.top, 10)
            Text(url?.deletingPathExtension().lastPathComponent ?? "System wallpaper")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 200)
        }
    }
}

// MARK: - Playlist & Schedule

struct ScheduleSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var library = VideoLibrary.shared
    @ObservedObject private var playlist = PlaylistManager.shared

    private let intervals: [(String, TimeInterval)] = [
        ("1 minute", 60), ("5 minutes", 300), ("15 minutes", 900), ("30 minutes", 1800),
        ("1 hour", 3600), ("3 hours", 10_800), ("6 hours", 21_600), ("12 hours", 43_200), ("Daily", 86_400),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Rotate wallpapers automatically", isOn: $settings.playlistEnabled)
                Picker("Change every", selection: $settings.playlistInterval) {
                    ForEach(intervals, id: \.1) { Text($0.0).tag($0.1) }
                }
                .disabled(!settings.playlistEnabled)
                Toggle("Shuffle", isOn: $settings.playlistShuffle)
                    .disabled(!settings.playlistEnabled)
                if let next = playlist.nextChange {
                    LabeledContent("Next change") {
                        HStack {
                            Text(next, style: .relative)
                            Button("Skip Now") { playlist.advance() }
                        }
                    }
                }
            } header: {
                SectionHeader(title: "Playlist")
            } footer: {
                SectionFooter(text: "Videos crossfade smoothly. When displays show different wallpapers, each display starts at a different point in the playlist.")
            }

            Section {
                if settings.playlist.isEmpty {
                    Text("No videos yet. Add them below or from the ⋯ menu on a video in the Library.")
                        .foregroundColor(.secondary)
                }
                ForEach(Array(settings.playlist.enumerated()), id: \.offset) { index, name in
                    HStack {
                        Text("\(index + 1).").foregroundColor(.secondary).monospacedDigit()
                        Text(library.item(named: name)?.title ?? name)
                        Spacer()
                        Button {
                            settings.playlist.swapAt(index, index - 1)
                        } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0)
                        Button {
                            settings.playlist.swapAt(index, index + 1)
                        } label: { Image(systemName: "chevron.down") }
                            .disabled(index == settings.playlist.count - 1)
                        Button {
                            settings.playlist.remove(at: index)
                        } label: { Image(systemName: "minus.circle.fill").foregroundColor(.red) }
                    }
                    .buttonStyle(.borderless)
                }
                let available = library.videos.filter { !settings.playlist.contains($0.name) }
                if !available.isEmpty {
                    Menu("Add Video") {
                        Button("Add All") { settings.playlist.append(contentsOf: available.map(\.name)) }
                        Divider()
                        ForEach(available) { video in
                            Button(video.title) { settings.playlist.append(video.name) }
                        }
                    }
                    .fixedSize()
                }
            } header: {
                SectionHeader(title: "Playlist Videos")
            }

            Section {
                Toggle("Switch wallpaper with Light & Dark Mode", isOn: $settings.appearanceSwitching)
                VideoPicker(title: "Light Mode", noneTitle: "None", selection: $settings.lightWallpaper)
                    .disabled(!settings.appearanceSwitching)
                VideoPicker(title: "Dark Mode", noneTitle: "None", selection: $settings.darkWallpaper)
                    .disabled(!settings.appearanceSwitching)
            } header: {
                SectionHeader(title: "Day & Night")
            } footer: {
                SectionFooter(text: "Follows System Settings → Appearance, including Auto. When on, it takes priority over the playlist.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SidebarItem.schedule.rawValue)
    }
}

// MARK: - Effects

struct EffectsSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var weather = WeatherService.shared

    @State private var query = ""
    @State private var results: [WeatherService.Place] = []
    @State private var isSearching = false
    @State private var searchError: String?

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 14)], spacing: 14) {
                    ForEach(OverlayEffect.allCases) { effect in
                        EffectTile(effect: effect, isSelected: settings.effect == effect) {
                            withAnimation(.easeInOut(duration: 0.15)) { settings.effect = effect }
                        }
                    }
                }
                .padding(.vertical, 6)
            } header: {
                SectionHeader(title: "Interactive Overlays")
            } footer: {
                SectionFooter(text: "Effects are rendered over the video wallpaper. Live Weather shows rain or snow when it is raining or snowing where you are.")
            }

            Section {
                LabeledContent("Intensity") {
                    Slider(value: $settings.effectIntensity, in: 0.1...1)
                }
                Toggle("Particles move away from the pointer", isOn: $settings.mouseInteraction)
            } header: {
                SectionHeader(title: "Behavior")
            }
            .disabled(settings.effect == .none)

            if settings.effect == .weather {
                weatherSection
            }

            Section {
                Toggle("Parallax: the wallpaper drifts gently with the pointer", isOn: $settings.parallax)
            } header: {
                SectionHeader(title: "Motion")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SidebarItem.effects.rawValue)
    }

    private var weatherSection: some View {
        Section {
            LabeledContent("Location") {
                Text(settings.weatherPlace ?? "Not set")
                    .foregroundColor(settings.weatherPlace == nil ? .secondary : .primary)
            }
            if let condition = weather.condition {
                LabeledContent("Now") {
                    HStack(spacing: 6) {
                        Image(systemName: condition.symbol)
                        Text(condition.title)
                        if let temperature = weather.temperature {
                            Text("\(Int(temperature.rounded()))°C").foregroundColor(.secondary)
                        }
                        Button {
                            weather.refreshNow()
                        } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless)
                            .disabled(weather.isLoading)
                    }
                }
            }
            if let error = weather.errorMessage {
                Text(error).font(.caption).foregroundColor(.red)
            }
            HStack {
                TextField("Search city", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(search)
                Button("Search", action: search)
                    .disabled(query.trimmingCharacters(in: .whitespaces).count < 2 || isSearching)
                if isSearching { ProgressView().controlSize(.small) }
            }
            if let searchError {
                Text(searchError).font(.caption).foregroundColor(.red)
            }
            ForEach(results) { place in
                Button {
                    weather.select(place)
                    results = []
                    query = ""
                } label: {
                    Label(place.displayName, systemImage: "mappin.and.ellipse")
                }
                .buttonStyle(.borderless)
            }
        } header: {
            SectionHeader(title: "Live Weather")
        } footer: {
            SectionFooter(text: "Weather data by Open-Meteo.com, refreshed every 30 minutes.")
        }
    }

    private func search() {
        let current = query
        isSearching = true
        searchError = nil
        Task {
            defer { isSearching = false }
            do {
                results = try await weather.searchPlaces(current)
                if results.isEmpty { searchError = "No places found for “\(current)”." }
            } catch {
                searchError = error.localizedDescription
            }
        }
    }
}

// MARK: - Energy

struct EnergySettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var screens = ScreenManager.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Label(screens.statusText, systemImage: screens.isPaused ? "pause.circle.fill" : "play.circle.fill")
                        .foregroundColor(screens.isPaused ? .orange : .green)
                }
            }

            Section {
                Toggle("Pause when the desktop is covered (full-screen apps)", isOn: $settings.pauseOnOcclusion)
                Toggle("Pause when the screen is locked", isOn: $settings.pauseOnSleep)
                Toggle("Pause on battery power", isOn: $settings.pauseOnBattery)
                Toggle("Pause in Low Power Mode", isOn: $settings.pauseOnLowPower)
                Toggle("Pause when the Mac is running hot", isOn: $settings.pauseOnThermal)
            } header: {
                SectionHeader(title: "Smart Pause")
            } footer: {
                SectionFooter(text: "Playback always stops while the display is asleep. AeroWall resumes automatically as soon as the reason goes away.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SidebarItem.energy.rawValue)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var library = VideoLibrary.shared

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch AeroWall at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundColor(.red)
                }
            } header: {
                SectionHeader(title: "Startup")
            }

            Section {
                Toggle("Optimize videos when importing (HEVC)", isOn: $settings.convertOnImport)
            } header: {
                SectionHeader(title: "Import")
            } footer: {
                SectionFooter(text: "Converts videos to HEVC and scales them down to your largest display. Apple Silicon decodes HEVC in hardware, keeping CPU use and battery drain minimal.")
            }

            Section {
                LabeledContent("Videos") {
                    Text("\(library.videos.count) · \(ByteCountFormatter.string(fromByteCount: library.totalSize, countStyle: .file))")
                }
                LabeledContent("Location") {
                    Button("Show in Finder") { library.revealInFinder() }
                }
            } header: {
                SectionHeader(title: "Library")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SidebarItem.general.rawValue)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let isEnabled = SMAppService.mainApp.status == .enabled
        guard enabled != isEnabled else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription). Move AeroWall to the Applications folder and try again."
            launchAtLogin = isEnabled
        }
    }
}

// MARK: - About

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
                .shadow(radius: 10)

            Text("AeroWall")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                )

            Text(version)
                .font(.headline)
                .foregroundColor(.secondary)

            Text("The native live wallpaper engine for macOS.")
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Text("Weather data by Open-Meteo.com · MIT License")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Made with ❤️ for macOS")
                .font(.caption)
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
        }
        .padding(60)
        .navigationTitle(SidebarItem.about.rawValue)
    }
}
