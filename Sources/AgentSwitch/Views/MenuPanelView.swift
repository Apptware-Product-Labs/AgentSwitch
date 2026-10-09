import SwiftUI

struct PanelActions {
    var addProjects: () -> Void
    var openPreferences: () -> Void
    var openAccessibilitySettings: () -> Void
    var quit: () -> Void
}

/// The dropdown shown from the menu bar icon.
struct MenuPanelView: View {
    @ObservedObject var engine: ProfileEngine
    @ObservedObject var watcher: WorkspaceWatcher
    let actions: PanelActions

    @State private var isAdding = false
    @State private var newName = ""
    @State private var errorMessage: String?
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            divider

            // Profiles
            VStack(spacing: 1) {
                SectionLabel("Profiles")
                ForEach(engine.config.profiles) { profile in
                    ProfileRow(profile: profile, isActive: profile.id == engine.activeProfile?.id) {
                        attempt { try engine.activate(profile.id) }
                    }
                }
                if isAdding { addField } else {
                    PanelRow(symbol: "plus", title: "New Profile…") {
                        isAdding = true
                        nameFieldFocused = true
                    }
                }
            }
            .padding(8)

            if !toolsNeedingSignIn.isEmpty {
                divider
                VStack(spacing: 1) {
                    SectionLabel("Set up \(engine.activeProfile?.name ?? "profile")")
                    ForEach(toolsNeedingSignIn) { tool in
                        PanelRow(symbol: "person.badge.key", title: "Sign in to \(tool.displayName)…") {
                            attempt { try engine.openSignIn(tool) }
                        }
                    }
                }
                .padding(8)
            }

            divider

            // Projects
            VStack(spacing: 1) {
                HStack {
                    SectionLabel("Projects")
                    Spacer()
                    Button(action: actions.addProjects) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.borderless)
                    .help("Link project folders")
                    .padding(.trailing, 8)
                }
                if engine.config.mappings.isEmpty {
                    Text("No projects linked. Add folders and the profile switches automatically when one is open in VS Code or Zed.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                ScrollView(.vertical) {
                    VStack(spacing: 1) {
                        ForEach(engine.config.mappings) { map in
                            ProjectRow(engine: engine, mapping: map,
                                       isDetected: watcher.detection?.mapping?.path == map.path)
                        }
                    }
                }
                .frame(maxHeight: 6 * 32)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)

            // Detection status
            if !watcher.accessibilityTrusted {
                divider
                statusRow(symbol: "exclamationmark.triangle.fill", tint: .orange,
                          title: "Auto-switching is off",
                          subtitle: "Grant Accessibility access so AgentSwitch can see which folder your editor has open.",
                          buttonTitle: "Grant", action: actions.openAccessibilitySettings)
            } else if let d = watcher.detection {
                divider
                statusRow(symbol: "scope", tint: .secondary,
                          title: d.label,
                          subtitle: d.mapping.flatMap { engine.profile(id: $0.profileID) }.map { "\(d.editorName) · linked to \($0.name)" }
                                    ?? "\(d.editorName) · not linked",
                          buttonTitle: d.mapping == nil ? "Link…" : nil, action: actions.addProjects)
            }

            divider

            VStack(spacing: 1) {
                PanelRow(symbol: "gearshape", title: "Preferences…", shortcut: "⌘,", action: actions.openPreferences)
                    .keyboardShortcut(",", modifiers: .command)
                PanelRow(symbol: "power", title: "Quit AgentSwitch", shortcut: "⌘Q", action: actions.quit)
                    .keyboardShortcut("q", modifiers: .command)
            }
            .padding(8)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: 320)
    }

    private var divider: some View { Divider().padding(.horizontal, 12) }

    // MARK: Derived

    private func isSignedIn(_ tool: Tool) -> Bool {
        guard let p = engine.activeProfile else { return false }
        return engine.isSignedIn(tool, profile: p)
    }

    private var toolsNeedingSignIn: [Tool] {
        engine.config.enabledTools.filter { !isSignedIn($0) }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ACTIVE PROFILE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(engine.activeProfile?.name ?? "No profile")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .lineLimit(1)
            HStack(spacing: 6) {
                ForEach(engine.config.enabledTools) { tool in
                    ToolChip(tool: tool, signedIn: isSignedIn(tool))
                }
            }
            .padding(.top, 2)
        }
    }

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .frame(width: 18)
                .foregroundStyle(.secondary)
            TextField("Profile name", text: $newName)
                .textFieldStyle(.plain)
                .focused($nameFieldFocused)
                .onSubmit(commitAdd)
                .onExitCommand(perform: cancelAdd)
            Button("Add", action: commitAdd)
                .controlSize(.small)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func statusRow(symbol: String, tint: Color, title: String, subtitle: String,
                           buttonTitle: String?, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            if let buttonTitle {
                Button(buttonTitle, action: action).controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    // MARK: Actions

    private func commitAdd() {
        let name = newName
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        attempt {
            let p = try engine.addProfile(named: name)
            try engine.activate(p.id)
        }
        cancelAdd()
    }

    private func cancelAdd() {
        isAdding = false
        newName = ""
    }

    private func attempt(_ body: () throws -> Void) {
        do { try body(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}

// MARK: - Components

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 3)
    }
}

struct ToolChip: View {
    let tool: Tool
    var signedIn = true
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tool.symbol).font(.system(size: 9, weight: .semibold))
            Text(tool.displayName).font(.system(size: 11, weight: .medium))
            Circle()
                .fill(signedIn ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
                .padding(.leading, 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
        .foregroundStyle(Color.accentColor)
        .help(signedIn ? "\(tool.displayName): signed in" : "\(tool.displayName): not signed in for this profile")
    }
}

struct ProfileRow: View {
    let profile: Profile
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .strokeBorder(isActive ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1.5)
                        .background(Circle().fill(isActive ? Color.accentColor : .clear))
                        .frame(width: 16, height: 16)
                    if isActive {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 18)
                Text(profile.name)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
    }
}

/// A linked folder with an inline profile picker.
struct ProjectRow: View {
    @ObservedObject var engine: ProfileEngine
    let mapping: ProjectMapping
    var isDetected = false
    @State private var hovering = false

    private var name: String { (mapping.path as NSString).lastPathComponent }
    private var profileName: String { engine.profile(id: mapping.profileID)?.name ?? "?" }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isDetected ? "folder.fill.badge.checkmark" : "folder.fill")
                .font(.system(size: 12))
                .frame(width: 18)
                .foregroundStyle(isDetected ? Color.accentColor : .secondary)
            Text(name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Menu {
                ForEach(engine.config.profiles) { p in
                    Button {
                        try? engine.link(directory: mapping.path, to: p.id)
                    } label: {
                        if p.id == mapping.profileID { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                    }
                }
                Divider()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: mapping.path)])
                }
                Button("Unlink", role: .destructive) { try? engine.unlink(directory: mapping.path) }
            } label: {
                HStack(spacing: 3) {
                    Text(profileName).font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(hovering ? 0.05 : 0)))
        .onHover { hovering = $0 }
        .help(mapping.path.replacingOccurrences(of: engine.home.path, with: "~"))
    }
}

struct PanelRow: View {
    let symbol: String
    let title: String
    var shortcut: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(title).font(.system(size: 13))
                Spacer(minLength: 0)
                if let shortcut {
                    Text(shortcut).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
    }
}

/// Menu-like row highlight on hover / press.
struct HoverRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.07 : 0))
                )
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}
