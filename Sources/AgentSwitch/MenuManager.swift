import AppKit
import Combine
import SwiftUI

/// Owns the `NSStatusItem`, the SwiftUI popover panel, and the Preferences window.
@MainActor
final class MenuManager: NSObject {
    private let engine: ProfileEngine
    private let watcher: WorkspaceWatcher
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var preferencesWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init(engine: ProfileEngine, watcher: WorkspaceWatcher) {
        self.engine = engine
        self.watcher = watcher
        super.init()
        watcher.onSwitch = { [weak self] profile in self?.flash(profile) }
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = StatusIcon.cards()
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePanel)
        }
        statusItem = item

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MenuPanelView(
            engine: engine,
            watcher: watcher,
            actions: PanelActions(
                addProjects: { [weak self] in self?.addProjects() },
                openPreferences: { [weak self] in self?.showPreferences() },
                openAccessibilitySettings: { [weak self] in self?.openAccessibilitySettings() },
                quit: { NSApp.terminate(nil) }
            )
        ))

        engine.$config
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &cancellables)
        updateButton()
    }

    private func updateButton() {
        guard let button = statusItem?.button else { return }
        let name = engine.activeProfile?.name ?? "—"
        button.title = engine.config.showNameInMenuBar ? " \(name)" : ""
        button.toolTip = "AgentSwitch — active profile: \(name)"
    }

    /// Brief visual confirmation when the watcher switches profiles automatically.
    private func flash(_ profile: Profile) {
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.statusItem?.button?.image = StatusIcon.cards()
        }
    }

    // MARK: Panel

    @objc private func togglePanel() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        watcher.refresh()                       // capture the editor's state before we take focus
        engine.refreshSignInStatus()
        NSApp.activate(ignoringOtherApps: true) // so the panel's text fields get keyboard input
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func closePanel() {
        if popover.isShown { popover.performClose(nil) }
    }

    // MARK: Actions

    private func addProjects() {
        guard let active = engine.activeProfile else { return }
        closePanel()
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Link"
        panel.message = "Choose project folders to link to “\(active.name)”. ⌘-click to select several; you can change the profile per folder afterwards."
        if let hint = watcher.detection?.directory {
            panel.directoryURL = URL(fileURLWithPath: hint)   // start where the editor's file lives
        }
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do { try engine.link(directory: url.path, to: active.id) }
            catch { Self.presentError("Couldn't link \(url.lastPathComponent)", error) }
        }
    }

    private func openAccessibilitySettings() {
        closePanel()
        watcher.requestAccessibility()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func showPreferences() {
        closePanel()
        if preferencesWindow == nil {
            let host = NSHostingController(rootView: PreferencesView(engine: engine, watcher: watcher))
            let window = NSWindow(contentViewController: host)
            window.title = "AgentSwitch"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.toolbarStyle = .preference
            window.center()
            preferencesWindow = window
        }
        engine.refreshSignInStatus()
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    static func presentError(_ title: String, _ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

/// The menu bar glyph: two stacked profile cards, front one filled. Drawn as a template
/// image so it follows the menu bar's light/dark appearance.
enum StatusIcon {
    static func cards() -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let img = NSImage(size: size, flipped: false) { _ in
            let w: CGFloat = 12, h: CGFloat = 8.5, r: CGFloat = 2
            let back = NSBezierPath(roundedRect: NSRect(x: 5, y: 6, width: w, height: h), xRadius: r, yRadius: r)
            back.lineWidth = 1.4
            NSColor.black.setStroke(); back.stroke()

            let frontRect = NSRect(x: 1, y: 1.5, width: w, height: h)
            // Knock out the back card where the front overlaps, so the stack reads clearly.
            NSColor.black.setFill()
            let ctx = NSGraphicsContext.current!
            ctx.compositingOperation = .destinationOut
            NSBezierPath(roundedRect: frontRect.insetBy(dx: -1.2, dy: -1.2), xRadius: r + 1, yRadius: r + 1).fill()
            ctx.compositingOperation = .sourceOver
            NSBezierPath(roundedRect: frontRect, xRadius: r, yRadius: r).fill()
            // Avatar dot knocked out of the front card.
            ctx.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: NSRect(x: 3, y: 4, width: 3.4, height: 3.4)).fill()
            ctx.compositingOperation = .sourceOver
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "AgentSwitch"
        return img
    }
}
