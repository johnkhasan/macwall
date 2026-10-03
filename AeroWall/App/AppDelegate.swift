import Cocoa
import SwiftUI
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let lastVideoPath = UserDefaults.standard.string(forKey: "lastVideoPath") {
            let url = URL(fileURLWithPath: lastVideoPath)
            if FileManager.default.fileExists(atPath: url.path) {
                ScreenManager.shared.playVideo(at: url)
            }
        }
    }
}
