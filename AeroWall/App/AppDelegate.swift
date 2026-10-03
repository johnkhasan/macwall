import Cocoa
import SwiftUI
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var playerController: PlayerController?
    var statusItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create Menu Bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "play.tv", accessibilityDescription: "AeroWall")
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit AeroWall", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
        
        // Create a local video URL path in Documents for testing MVP
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let testVideoURL = homeDir.appendingPathComponent("Documents/test.mp4")
        
        if let screen = NSScreen.main {
            playerController = PlayerController(screen: screen, videoURL: testVideoURL)
            playerController?.play()
        }
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
