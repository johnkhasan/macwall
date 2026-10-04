import AppKit
import Combine
import IOKit.ps

/// Watches power, sleep, lock and thermal state and tells `ScreenManager` why it should pause.
/// Occlusion (full-screen apps covering the desktop) is handled per window by `ScreenManager`.
@MainActor
final class PauseController {
    static let shared = PauseController()

    private let settings = AppSettings.shared
    private var screensAsleep = false
    private var systemAsleep = false
    private var screenLocked = false
    private var sessionInactive = false
    private var onBattery = false
    private var powerSource: CFRunLoopSource?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func start() {
        guard cancellables.isEmpty else { return }

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.systemAsleep = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.systemAsleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.screenLocked = false }

        observe(NotificationCenter.default, .NSProcessInfoPowerStateDidChange) { _ in }
        observe(NotificationCenter.default, ProcessInfo.thermalStateDidChangeNotification) { _ in }

        settings.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.evaluate() }
            .store(in: &cancellables)

        startPowerSourceMonitoring()
        evaluate()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, update: @escaping (PauseController) -> Void) {
        center.publisher(for: name)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                update(self)
                self.evaluate()
            }
            .store(in: &cancellables)
    }

    private func startPowerSourceMonitoring() {
        onBattery = Self.isOnBatteryPower()
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let controller = Unmanaged<PauseController>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                controller.onBattery = PauseController.isOnBatteryPower()
                controller.evaluate()
            }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSource = source
    }

    nonisolated static func isOnBatteryPower() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }

    private func evaluate() {
        var reasons = Set<PauseReason>()
        // When nobody can see the desktop there is nothing to gain from decoding video.
        if screensAsleep || systemAsleep || sessionInactive || (settings.pauseOnSleep && screenLocked) {
            reasons.insert(.sleep)
        }
        if settings.pauseOnBattery && onBattery {
            reasons.insert(.battery)
        }
        if settings.pauseOnLowPower && ProcessInfo.processInfo.isLowPowerModeEnabled {
            reasons.insert(.lowPower)
        }
        let thermal = ProcessInfo.processInfo.thermalState
        if settings.pauseOnThermal && (thermal == .serious || thermal == .critical) {
            reasons.insert(.thermal)
        }
        ScreenManager.shared.setSystemPauseReasons(reasons)
    }
}
