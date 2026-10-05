import SwiftUI

struct ScreenSaverSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var library = VideoLibrary.shared

    @State private var isInstalled = ScreenSaverInstaller.isInstalled
    @State private var installError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Use a live wallpaper as my screen saver", isOn: $settings.screenSaverEnabled)
                Picker("Screen saver video", selection: $settings.screenSaverVideo) {
                    Text("Same as desktop wallpaper").tag(String?.none)
                    if !library.videos.isEmpty { Divider() }
                    ForEach(library.videos) { video in
                        Text(video.title).tag(Optional(video.name))
                    }
                }
                .disabled(!settings.screenSaverEnabled)
            } header: {
                Text("Screen Saver").font(.headline)
            } footer: {
                Text("Scaling and mute follow your main Displays & Audio settings. The screen saver plays from the local file, so it works offline.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                HStack {
                    Image(systemName: isInstalled ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(isInstalled ? .green : .secondary)
                    Text(isInstalled ? "AeroWall screen saver is installed." : "Not installed yet.")
                    Spacer()
                }

                HStack {
                    Button(isInstalled ? "Reinstall / Update" : "Install Screen Saver…") {
                        install()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Open Screen Saver Settings") {
                        ScreenSaverInstaller.openSystemSettings()
                    }

                    if isInstalled {
                        Spacer()
                        Button("Remove", role: .destructive) {
                            ScreenSaverInstaller.uninstall()
                            isInstalled = ScreenSaverInstaller.isInstalled
                        }
                    }
                }
            } header: {
                Text("Installation").font(.headline)
            } footer: {
                Text("After installing, open Screen Saver settings and choose “AeroWall”. macOS may ask you to approve the screen saver the first time because it is not notarized.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Label {
                    Text("A live lock-screen wallpaper is not possible: macOS runs the lock screen in a separate, protected process that third-party apps cannot draw into.")
                } icon: {
                    Image(systemName: "lock.fill")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            } header: {
                Text("Lock Screen").font(.headline)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Screen Saver")
        .onAppear { isInstalled = ScreenSaverInstaller.isInstalled }
        .alert("Could not install the screen saver", isPresented: Binding(
            get: { installError != nil }, set: { if !$0 { installError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(installError ?? "")
        }
    }

    private var selectedVideoURL: URL? {
        let name = settings.screenSaverVideo ?? settings.wallpaper
        return name.flatMap { library.url(for: $0) }
    }

    private func install() {
        do {
            try ScreenSaverInstaller.install(
                videoURL: selectedVideoURL,
                scaling: settings.videoScaling.rawValue,
                muted: settings.muteAudio
            )
            isInstalled = ScreenSaverInstaller.isInstalled
            if !settings.screenSaverEnabled { settings.screenSaverEnabled = true }
            ScreenSaverInstaller.openSystemSettings()
        } catch {
            installError = error.localizedDescription
        }
    }
}
