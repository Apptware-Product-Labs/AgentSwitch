import AppKit
import ServiceManagement
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var engine: ProfileEngine
    @ObservedObject var watcher: WorkspaceWatcher

    var body: some View {
        TabView {
            GeneralTab(engine: engine, watcher: watcher)
                .tabItem { Label("General", systemImage: "gearshape") }
            ProfilesTab(engine: engine)
                .tabItem { Label("Profiles", systemImage: "person.2") }
            ProjectsTab(engine: engine)
                .tabItem { Label("Projects", systemImage: "folder") }
        }
        .frame(width: 540, height: 440)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var engine: ProfileEngine
    @ObservedObject var watcher: WorkspaceWatcher
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var accessibilityTrusted = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Menu Bar") {
                Toggle("Show active profile name", isOn: Binding(
                    get: { engine.config.showNameInMenuBar },
                    set: { engine.setShowNameInMenuBar($0) }))
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in
                        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                        catch { errorMessage = error.localizedDescription }
                    }
            }

            Section {
                ForEach(Tool.allCases) { tool in
                    Toggle(isOn: Binding(
                        get: { engine.config.enabledTools.contains(tool) },
                        set: { on in
                            do { try engine.setTool(tool, enabled: on); errorMessage = nil }
                            catch { errorMessage = error.localizedDescription }
                        })) {
                        HStack(spacing: 10) {
                            Image(systemName: tool.symbol).frame(width: 18).foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tool.displayName)
                                Text(tool.summary).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: { Text("Tools") } footer: {
                Text("Enabling a tool moves its existing files into the active profile. Disabling moves them back. Nothing is deleted.")
            }

            Section("Workspace Detection") {
                HStack {
                    Image(systemName: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityTrusted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(accessibilityTrusted ? "Accessibility access granted" : "Accessibility access needed")
                        Text("Required to read which folder VS Code or Zed has open.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !accessibilityTrusted {
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
            }

            Section("Storage") {
                LabeledContent("Profiles folder") {
                    Text(engine.profilesDir.path.replacingOccurrences(of: engine.home.path, with: "~"))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([engine.profilesDir]) }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshTrust)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshTrust() }
    }

    private func refreshTrust() { accessibilityTrusted = watcher.isAccessibilityTrusted }
}

// MARK: - Profiles

private struct ProfilesTab: View {
    @ObservedObject var engine: ProfileEngine
    @State private var errorMessage: String?
    @State private var pendingDelete: Profile?

    var body: some View {
        Form {
            Section {
                ForEach(engine.config.profiles) { profile in
                    ProfileEditRow(engine: engine, profile: profile,
                                   isActive: profile.id == engine.activeProfile?.id,
                                   onError: { errorMessage = $0 },
                                   onDelete: { pendingDelete = profile })
                }
            } header: { Text("Profiles") } footer: {
                Text("Each profile is a separate login for every enabled tool. Green = signed in, orange = not yet. Switch to a profile to sign in.")
            }

            Section {
                Button {
                    do { try engine.addProfile(named: "Profile \(engine.config.profiles.count + 1)"); errorMessage = nil }
                    catch { errorMessage = error.localizedDescription }
                } label: { Label("Add Profile", systemImage: "plus") }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete “\(pendingDelete?.name ?? "")”?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { profile in
            Button("Move to Trash", role: .destructive) {
                do { try engine.deleteProfile(id: profile.id); errorMessage = nil }
                catch { errorMessage = error.localizedDescription }
            }
        } message: { _ in
            Text("Its login and settings are moved to the Trash, not erased. Folders linked to it are unlinked.")
        }
    }
}

private struct ProfileEditRow: View {
    @ObservedObject var engine: ProfileEngine
    let profile: Profile
    let isActive: Bool
    let onError: (String) -> Void
    let onDelete: () -> Void
    @State private var name: String
    @FocusState private var focused: Bool

    init(engine: ProfileEngine, profile: Profile, isActive: Bool,
         onError: @escaping (String) -> Void, onDelete: @escaping () -> Void) {
        self.engine = engine
        self.profile = profile
        self.isActive = isActive
        self.onError = onError
        self.onDelete = onDelete
        _name = State(initialValue: profile.name)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { if !$0 { commit() } }
            Spacer()
            HStack(spacing: 6) {
                ForEach(engine.config.enabledTools) { tool in
                    let ok = engine.isSignedIn(tool, profile: profile)
                    if ok || !isActive {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(ok ? Color.green : Color.orange)
                            .help(ok ? "\(tool.displayName): signed in" : "\(tool.displayName): not signed in — switch to this profile to sign in")
                    } else {
                        Button {
                            do { try engine.openSignIn(tool) } catch { onError(error.localizedDescription) }
                        } label: { Label("Sign in to \(tool.displayName)", systemImage: tool.symbol) }
                        .controlSize(.small)
                    }
                }
            }
            if isActive {
                Text("Active").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Switch") {
                    do { try engine.activate(profile.id) } catch { onError(error.localizedDescription) }
                }
                .controlSize(.small)
            }
            Menu {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([engine.profileDirectory(profile)])
                }
                Divider()
                Button("Delete…", role: .destructive, action: onDelete).disabled(isActive)
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
        }
    }

    private func commit() {
        do { try engine.renameProfile(id: profile.id, to: name) }
        catch { onError(error.localizedDescription); name = profile.name }
    }
}

// MARK: - Projects

private struct ProjectsTab: View {
    @ObservedObject var engine: ProfileEngine
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                if engine.config.mappings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No folders linked yet")
                        Text("Link a project folder to a profile and AgentSwitch switches automatically when that folder is open in VS Code or Zed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                ForEach(engine.config.mappings) { map in
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill").foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text((map.path as NSString).lastPathComponent).fontWeight(.medium)
                            Text(map.path.replacingOccurrences(of: engine.home.path, with: "~"))
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { map.profileID },
                            set: { id in
                                do { try engine.link(directory: map.path, to: id); errorMessage = nil }
                                catch { errorMessage = error.localizedDescription }
                            })) {
                            ForEach(engine.config.profiles) { Text($0.name).tag($0.id) }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                        Button { try? engine.unlink(directory: map.path) } label: {
                            Image(systemName: "minus.circle").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Unlink")
                    }
                }
            } header: { Text("Linked Folders") } footer: {
                Text("Subfolders inherit the link. The most specific match wins.")
            }

            Section {
                Button { addFolder() } label: { Label("Link Folder…", systemImage: "plus") }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
    }

    private func addFolder() {
        guard let active = engine.activeProfile else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Link"
        panel.message = "Choose a project folder to link to “\(active.name)”. You can change the profile afterwards."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try engine.link(directory: url.path, to: active.id); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}
