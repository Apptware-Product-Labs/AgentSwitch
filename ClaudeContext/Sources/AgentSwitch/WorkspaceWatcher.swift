import AppKit
import ApplicationServices

/// Watches for VS Code / Zed becoming frontmost, reads the focused window's document
/// path / title via the Accessibility API, and switches profiles when the workspace
/// matches a linked directory.
@MainActor
final class WorkspaceWatcher: ObservableObject {
    static let editorBundleIDs: Set<String> = ["com.microsoft.VSCode", "dev.zed.Zed"]

    struct Detection: Equatable {
        var editorName: String
        var directory: String            // best-guess folder of the open file
        var mapping: ProjectMapping?     // linked folder containing it, if any
    }

    /// What we last saw in the frontmost editor. Drives the "Detected" row in the panel.
    @Published private(set) var detection: Detection?

    /// Called after a linked workspace triggered a profile switch.
    var onSwitch: ((Profile) -> Void)?

    private let engine: ProfileEngine
    private var pollTimer: Timer?
    private var lastAppliedMapping: String?   // so a manual menu choice isn't overridden every tick
    private var observer: NSObjectProtocol?

    init(engine: ProfileEngine) {
        self.engine = engine
    }

    func start() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.frontmostChanged() }
        }
        frontmostChanged()
    }

    /// Re-reads the frontmost editor; call right before our panel steals focus.
    func refresh() {
        guard let app = Self.frontmostEditor() else { return }
        _ = inspect(app)
    }

    var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    // MARK: Private

    private static func frontmostEditor() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let id = app.bundleIdentifier, editorBundleIDs.contains(id) else { return nil }
        return app
    }

    private func frontmostChanged() {
        pollTimer?.invalidate()
        pollTimer = nil
        guard let app = Self.frontmostEditor() else {
            // Ignore our own panel/prefs taking focus; anything else resets so returning
            // to a project re-applies its profile.
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier {
                lastAppliedMapping = nil
            }
            return
        }
        check(app)
        // Window title changes when you open another folder in the same editor and there's
        // no cheap notification for that, so poll lightly while an editor is frontmost.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let app = Self.frontmostEditor() else { return }
                self.check(app)
            }
        }
    }

    private func check(_ app: NSRunningApplication) {
        guard let hit = inspect(app) else { return }
        guard hit.path != lastAppliedMapping else { return }
        lastAppliedMapping = hit.path

        guard engine.activeProfile?.id != hit.profileID, let profile = engine.profile(id: hit.profileID) else { return }
        do {
            try engine.activate(hit.profileID)
            onSwitch?(profile)
        } catch {
            NSLog("AgentSwitch: switch failed: \(error.localizedDescription)")
        }
    }

    /// Reads the focused window, updates `detection`, and returns the matching mapping.
    private func inspect(_ app: NSRunningApplication) -> ProjectMapping? {
        guard AXIsProcessTrusted() else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef else { return nil }
        let window = windowRef as! AXUIElement
        let editorName = app.localizedName ?? "Editor"

        // 1. AXDocument is a file:// URL of the active file (most precise).
        if let doc = stringAttribute(window, kAXDocumentAttribute),
           let url = URL(string: doc), url.isFileURL {
            let m = engine.mapping(forPath: url.path)
            publish(Detection(editorName: editorName, directory: url.deletingLastPathComponent().path, mapping: m))
            if let m { return m }
        }

        // 2. Fall back to the window title: VS Code "file — folder — Visual Studio Code",
        //    Zed "folder — file". Match any title segment to a linked folder's name.
        if let title = stringAttribute(window, kAXTitleAttribute) {
            let segments = title
                .components(separatedBy: CharacterSet(charactersIn: "—–-"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for seg in segments {
                if let m = engine.config.mappings.first(where: { ($0.path as NSString).lastPathComponent == seg }) {
                    publish(Detection(editorName: editorName, directory: m.path, mapping: m))
                    return m
                }
            }
        }
        return nil
    }

    private func publish(_ d: Detection) {
        if detection != d { detection = d }
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}
