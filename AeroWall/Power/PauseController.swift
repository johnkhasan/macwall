import AppKit
import Foundation

class PauseController {
    static let shared = PauseController()
    
    var pauseOnBattery = true
    var pauseOnSleep = true
    var pauseOnLowPowerMode = true
    var pauseOnThermal = true
    
    init() {
        setupObservers()
    }
    
    private func setupObservers() {
        let ws = NSWorkspace.shared
        ws.notificationCenter.addObserver(self, selector: #selector(sleepHandler), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.notificationCenter.addObserver(self, selector: #selector(wakeHandler), name: NSWorkspace.screensDidWakeNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(powerModeChanged), name: Notification.Name("NSProcessInfoPowerStateDidChangeNotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(thermalStateChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
    }
    
    @objc private func sleepHandler() {
        if pauseOnSleep {
            ScreenManager.shared.pause()
        }
    }
    
    @objc private func wakeHandler() {
        checkAndResume()
    }
    
    @objc private func powerModeChanged() {
        checkAndResume()
    }
    
    @objc private func thermalStateChanged() {
        checkAndResume()
    }
    
    func checkAndResume() {
        var shouldPause = false
        
        if pauseOnLowPowerMode && ProcessInfo.processInfo.isLowPowerModeEnabled {
            shouldPause = true
        }
        
        let thermalState = ProcessInfo.processInfo.thermalState
        if pauseOnThermal && (thermalState == .serious || thermalState == .critical) {
            shouldPause = true
        }
        
        if shouldPause {
            ScreenManager.shared.pause()
        } else {
            ScreenManager.shared.resume()
        }
    }
}
