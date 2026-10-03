import Cocoa
import SwiftUI
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create a local video URL path in Documents for testing MVP
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let testVideoURL = homeDir.appendingPathComponent("Documents/test.mp4")
        
        ScreenManager.shared.playVideo(at: testVideoURL)
    }
}
