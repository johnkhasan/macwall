import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var videos: [URL] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var experimentalLockScreen = false
    
    var body: some View {
        VStack {
            HStack {
                Text("AeroWall Library")
                    .font(.title)
                Spacer()
                VStack(alignment: .trailing) {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in
                            do {
                                if newValue {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                print("Failed to change login item: \(error)")
                            }
                        }
                    Toggle("Video Lock Screen (Experimental)", isOn: $experimentalLockScreen)
                }
            }
            .padding()
            
            List {
                ForEach(videos, id: \.self) { url in
                    HStack {
                        Text(url.lastPathComponent)
                        Spacer()
                        Button("Play") {
                            ScreenManager.shared.playVideo(at: url)
                        }
                        Button("Delete") {
                            VideoImporter.shared.deleteVideo(at: url)
                            loadVideos()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .frame(minHeight: 200)
            
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray, style: StrokeStyle(lineWidth: 2, dash: [5]))
                
                Text("Drop Video Files Here")
                    .foregroundColor(.secondary)
            }
            .frame(height: 100)
            .padding()
            .dropDestination(for: URL.self) { items, location in
                var imported = false
                for url in items {
                    if let _ = VideoImporter.shared.importVideo(from: url) {
                        imported = true
                    }
                }
                if imported {
                    loadVideos()
                }
                return true
            }
        }
        .padding()
        .frame(width: 500, height: 400)
        .onAppear {
            loadVideos()
        }
    }
    
    private func loadVideos() {
        videos = VideoImporter.shared.getImportedVideos()
    }
}
