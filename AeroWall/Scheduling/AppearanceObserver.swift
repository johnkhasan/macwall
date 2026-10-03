import AppKit

class AppearanceObserver: NSObject {
    static let shared = AppearanceObserver()
    private var observerContext = 0
    
    func startObserving() {
        NSApp.addObserver(self, forKeyPath: "effectiveAppearance", options: [.new, .initial], context: &observerContext)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "effectiveAppearance" {
            let isDark = NSApp.effectiveAppearance.name == .darkAqua || NSApp.effectiveAppearance.name == .vibrantDark
            print("Appearance changed: isDark = \(isDark)")
        }
    }
    
    deinit {
        NSApp.removeObserver(self, forKeyPath: "effectiveAppearance", context: &observerContext)
    }
}
