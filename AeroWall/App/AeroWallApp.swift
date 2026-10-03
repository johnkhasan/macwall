import SwiftUI

@main
struct AeroWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            Text("AeroWall Settings")
                .padding()
                .frame(width: 300, height: 150)
        }
    }
}
