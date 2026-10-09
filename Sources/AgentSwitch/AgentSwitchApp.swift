import AppKit

/// Entry point. We deliberately avoid SwiftUI's `App` lifecycle: it would create a
/// main window. A bare `NSApplication` with the `.accessory` policy gives us a
/// menu-bar-only app (no Dock icon, no window on launch).
@main
struct AgentSwitchApp {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run() // never returns, so `delegate` stays alive
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = ProfileEngine()
    private lazy var watcher = WorkspaceWatcher(engine: engine)
    private lazy var menu = MenuManager(engine: engine, watcher: watcher)

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try engine.bootstrap()
        } catch {
            MenuManager.presentError("AgentSwitch couldn't initialise", error)
        }
        menu.install()
        watcher.start()
    }
}
