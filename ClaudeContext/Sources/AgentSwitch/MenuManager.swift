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
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "AgentSwitch")
            button.image?.isTemplate = true
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
                linkWorkspace: { [weak self] in self?.linkWorkspace() },
                openPreferences: { [weak self] in self?.showPreferences() },
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
            self?.statusItem?.button?.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "AgentSwitch")
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

    private func linkWorkspace() {
        guard let active = engine.activeProfile else { return }
        closePanel()
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Link"
        panel.message = "Choose the project folder to link to “\(active.name)”."
        if let hint = watcher.detection?.directory {
            panel.directoryURL = URL(fileURLWithPath: hint)   // start where the editor's file lives
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try engine.link(directory: url.path, to: active.id) }
        catch { Self.presentError("Couldn't link folder", error) }
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
