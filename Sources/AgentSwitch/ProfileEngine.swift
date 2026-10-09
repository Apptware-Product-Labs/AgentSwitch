import AppKit
import Foundation

// MARK: - Models

struct Profile: Codable, Identifiable, Hashable {
    let id: String          // directory name, e.g. "profile_1"
    var name: String        // friendly nickname
}

struct ProjectMapping: Codable, Identifiable, Hashable {
    var path: String
    var profileID: String
    var id: String { path }
}

struct Config: Codable {
    var profiles: [Profile] = []
    var activeProfileID: String?
    var mappings: [ProjectMapping] = []
    var enabledTools: [Tool] = [.claude]
    var showNameInMenuBar = true

    init() {}

    // Tolerate missing keys so older config files keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
        activeProfileID = try c.decodeIfPresent(String.self, forKey: .activeProfileID)
        mappings = try c.decodeIfPresent([ProjectMapping].self, forKey: .mappings) ?? []
        enabledTools = try c.decodeIfPresent([Tool].self, forKey: .enabledTools) ?? [.claude]
        showNameInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showNameInMenuBar) ?? true
    }
}

enum EngineError: LocalizedError {
    case unmanagedSymlink(String)
    case realDirectoryInTheWay(String)
    case unknownProfile(String)
    case emptyName
    case cannotDeleteActive
    case cannotDisableLastTool

    var errorDescription: String? {
        switch self {
        case .unmanagedSymlink(let p):
            "\(p) is a symlink that AgentSwitch didn't create. Remove or move it, then try again."
        case .realDirectoryInTheWay(let p):
            "\(p) is a real folder, not a symlink. AgentSwitch never deletes real data; move it aside and retry."
        case .unknownProfile(let id):
            "Unknown profile “\(id)”."
        case .emptyName:
            "Please enter a name."
        case .cannotDeleteActive:
            "Switch to another profile before deleting this one."
        case .cannotDisableLastTool:
            "At least one tool must stay enabled."
        }
    }
}

// MARK: - Engine

/// Owns the on-disk layout under `~/.config/agentswitch/` and swaps the home-directory
/// symlinks (`~/.claude`, `~/.claude.json`, `~/.codex`, …) to point at the active profile.
///
/// Layout:
/// ```
/// ~/.config/agentswitch/
///   config.json
///   profiles/profile_1/claude/        ← ~/.claude
///   profiles/profile_1/claude.json    ← ~/.claude.json
///   profiles/profile_1/codex/         ← ~/.codex
/// ```
@MainActor
final class ProfileEngine: ObservableObject {
    @Published private(set) var config = Config()
    /// Cached sign-in state per profile (profileID → tool → signed in). Refreshed on changes.
    @Published private(set) var signInStatus: [String: [Tool: Bool]] = [:]

    private let fm = FileManager.default
    /// Honors $HOME so the app can be tested against a throwaway home directory.
    let home: URL
    let baseDir: URL
    var profilesDir: URL { baseDir.appendingPathComponent("profiles", isDirectory: true) }
    var sharedDir: URL { baseDir.appendingPathComponent("shared", isDirectory: true) }
    private var configURL: URL { baseDir.appendingPathComponent("config.json") }

    init() {
        home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory(), isDirectory: true)
        baseDir = home.appendingPathComponent(".config/agentswitch", isDirectory: true)
    }

    var activeProfile: Profile? { config.profiles.first { $0.id == config.activeProfileID } }
    func profile(id: String) -> Profile? { config.profiles.first { $0.id == id } }
    func profileDirectory(_ profile: Profile) -> URL { profilesDir.appendingPathComponent(profile.id, isDirectory: true) }

    // MARK: Bootstrap

    /// Creates the base directories, loads config, and on first run *adopts* whatever is
    /// already in `$HOME` as the "Default" profile instead of deleting it.
    func bootstrap() throws {
        try fm.createDirectory(at: profilesDir, withIntermediateDirectories: true)
        loadConfig()

        if config.profiles.isEmpty {
            // Enable Codex automatically if the user already has it set up.
            var tools: [Tool] = [.claude]
            if kind(at: home.appendingPathComponent(".codex")) == .real { tools.append(.codex) }
            config.enabledTools = tools

            let first = Profile(id: nextProfileID(), name: "Default")
            try fm.createDirectory(at: profileDirectory(first), withIntermediateDirectories: true)
            for tool in tools { try adopt(tool, into: first) }
            config.profiles = [first]
            config.activeProfileID = first.id
            try saveConfig()
        }

        if let active = activeProfile { try activate(active.id) }
        for tool in config.enabledTools { try ensureShared(tool) }
        refreshSignInStatus()
    }

    // MARK: Profiles

    @discardableResult
    func addProfile(named rawName: String) throws -> Profile {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw EngineError.emptyName }
        let profile = Profile(id: nextProfileID(), name: name)
        try fm.createDirectory(at: profileDirectory(profile), withIntermediateDirectories: true)
        for tool in config.enabledTools {
            try ensureSlots(tool, in: profile)
            if let active = activeProfile { seedConfigFile(tool, from: active, to: profile) }
        }
        config.profiles.append(profile)
        for tool in config.enabledTools { try ensureShared(tool) }
        try saveConfig()
        refreshSignInStatus()
        return profile
    }

    func renameProfile(id: String, to rawName: String) throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw EngineError.emptyName }
        guard let i = config.profiles.firstIndex(where: { $0.id == id }) else { throw EngineError.unknownProfile(id) }
        guard config.profiles[i].name != name else { return }
        config.profiles[i].name = name
        try saveConfig()
    }

    /// Moves the profile's data to the Trash (recoverable) and forgets it.
    func deleteProfile(id: String) throws {
        guard id != config.activeProfileID else { throw EngineError.cannotDeleteActive }
        guard let profile = profile(id: id) else { throw EngineError.unknownProfile(id) }
        let dir = profileDirectory(profile)
        if fm.fileExists(atPath: dir.path) { try fm.trashItem(at: dir, resultingItemURL: nil) }
        KeychainTool.delete(service: KeychainTool.profileService(.claude, id))
        config.profiles.removeAll { $0.id == id }
        config.mappings.removeAll { $0.profileID == id }
        try saveConfig()
        refreshSignInStatus()
    }

    // MARK: Switching

    /// Points every enabled tool's home paths at the given profile. Idempotent.
    func activate(_ profileID: String) throws {
        guard let profile = profile(id: profileID) else { throw EngineError.unknownProfile(profileID) }

        let isSwitch = config.activeProfileID != profileID
        if isSwitch, config.enabledTools.contains(.claude) {
            try swapClaudeKeychain(from: activeProfile, to: profile)
        }

        for tool in config.enabledTools {
            try ensureSlots(tool, in: profile)
            for link in tool.links {
                let linkURL = home.appendingPathComponent(link.homeName)
                let target = slotURL(link, in: profile).path

                switch kind(at: linkURL) {
                case .real:
                    // Tools that save via temp-file + rename (Claude Code does this for
                    // ~/.claude.json) replace our symlink with a real file. That file is the
                    // latest state of whichever profile was active, so reclaim it.
                    if !link.isDirectory, let owner = activeProfile {
                        _ = try fm.replaceItemAt(slotURL(link, in: owner), withItemAt: linkURL)
                    } else {
                        throw EngineError.realDirectoryInTheWay(linkURL.path)
                    }
                case .symlink:
                    if (try? fm.destinationOfSymbolicLink(atPath: linkURL.path)) == target { continue }
                case .missing:
                    break
                }
                try atomicSymlink(at: linkURL.path, to: target)
            }
        }

        if isSwitch {
            config.activeProfileID = profileID
            try saveConfig()
        }
        refreshSignInStatus()
    }

    /// Claude Code keeps its OAuth token in the Keychain, keyed by the literal config
    /// path, so it must be parked per profile: stash the live token under the outgoing
    /// profile, then restore the incoming profile's token (or clear it so Claude asks
    /// to log in).
    private func swapClaudeKeychain(from outgoing: Profile?, to incoming: Profile) throws {
        let live = KeychainTool.claudeLiveService
        if let outgoing {
            let park = KeychainTool.profileService(.claude, outgoing.id)
            if let token = KeychainTool.read(service: live) {
                try KeychainTool.write(service: park, value: token)
            } else {
                KeychainTool.delete(service: park)
            }
        }
        if let token = KeychainTool.read(service: KeychainTool.profileService(.claude, incoming.id)) {
            try KeychainTool.write(service: live, value: token)
        } else {
            KeychainTool.delete(service: live)
        }
    }

    /// Creates a temp symlink then `rename(2)`s it over the destination, so the home
    /// path is never missing or half-written. `rename` replaces a symlink or file in
    /// place but refuses to replace a non-empty directory (which we never want anyway).
    private func atomicSymlink(at linkPath: String, to target: String) throws {
        let tmp = "\(linkPath).agentswitch-\(getpid())"
        try? fm.removeItem(atPath: tmp)
        try fm.createSymbolicLink(atPath: tmp, withDestinationPath: target)
        if rename(tmp, linkPath) != 0 {
            let code = errno
            try? fm.removeItem(atPath: tmp)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code),
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't swap \(linkPath): \(String(cString: strerror(code)))"])
        }
    }

    // MARK: Tools

    func setTool(_ tool: Tool, enabled: Bool) throws {
        if enabled {
            guard !config.enabledTools.contains(tool), let active = activeProfile else { return }
            try adopt(tool, into: active)
            for p in config.profiles { try ensureSlots(tool, in: p) }
            config.enabledTools.append(tool)
            try saveConfig()
            try activate(active.id)
            try ensureShared(tool)
        } else {
            guard config.enabledTools.contains(tool) else { return }
            guard config.enabledTools.count > 1 else { throw EngineError.cannotDisableLastTool }
            // Put the active profile's data back where the tool expects it.
            if let active = activeProfile {
                for link in tool.links {
                    let linkURL = home.appendingPathComponent(link.homeName)
                    if kind(at: linkURL) == .symlink, isOurs(linkURL) { try fm.removeItem(at: linkURL) }
                    let slot = slotURL(link, in: active)
                    if kind(at: linkURL) == .missing, fm.fileExists(atPath: slot.path) {
                        try fm.moveItem(at: slot, to: linkURL)
                    }
                }
            }
            config.enabledTools.removeAll { $0 == tool }
            try saveConfig()
        }
    }

    /// Moves any real data at a tool's home paths into the profile's slots (never deletes).
    private func adopt(_ tool: Tool, into profile: Profile) throws {
        for link in tool.links {
            let src = home.appendingPathComponent(link.homeName)
            let dst = slotURL(link, in: profile)
            switch kind(at: src) {
            case .real:
                if fm.fileExists(atPath: dst.path) { try fm.trashItem(at: dst, resultingItemURL: nil) }
                try fm.moveItem(at: src, to: dst)
            case .symlink:
                if !isOurs(src) { throw EngineError.unmanagedSymlink(src.path) }
            case .missing:
                break
            }
        }
        try ensureSlots(tool, in: profile)
    }

    private func ensureSlots(_ tool: Tool, in profile: Profile) throws {
        for link in tool.links {
            let slot = slotURL(link, in: profile)
            guard !fm.fileExists(atPath: slot.path) else { continue }
            if link.isDirectory {
                try fm.createDirectory(at: slot, withIntermediateDirectories: true)
            } else {
                try Data(link.emptyContents.utf8).write(to: slot)
            }
        }
    }

    /// Moves each shared item into `shared/<tool>/` (seeded from the first profile that
    /// has a real copy) and symlinks it from every profile. Pre-existing copies in other
    /// profiles are set aside as `<name>.before-shared-<time>`, never deleted.
    func ensureShared(_ tool: Tool) throws {
        guard let dirLink = tool.links.first(where: { $0.isDirectory }) else { return }
        let shared = sharedDir.appendingPathComponent(tool.rawValue, isDirectory: true)
        try fm.createDirectory(at: shared, withIntermediateDirectories: true)

        for item in tool.sharedItems {
            let sharedItem = shared.appendingPathComponent(item)
            if kind(at: sharedItem) == .missing {
                for p in config.profiles {
                    let candidate = slotURL(dirLink, in: p).appendingPathComponent(item)
                    if kind(at: candidate) == .real {
                        try fm.moveItem(at: candidate, to: sharedItem)
                        break
                    }
                }
            }
            guard kind(at: sharedItem) != .missing else { continue }

            for p in config.profiles {
                let target = slotURL(dirLink, in: p).appendingPathComponent(item)
                switch kind(at: target) {
                case .symlink:
                    if (try? fm.destinationOfSymbolicLink(atPath: target.path)) == sharedItem.path { continue }
                    try fm.removeItem(at: target)
                case .real:
                    let aside = target.deletingLastPathComponent()
                        .appendingPathComponent("\(item).before-shared-\(Int(Date().timeIntervalSince1970))")
                    try fm.moveItem(at: target, to: aside)
                case .missing:
                    break
                }
                try fm.createSymbolicLink(at: target, withDestinationURL: sharedItem)
            }
        }
    }

    /// Copies the tool's JSON config file into a new profile minus the account keys, so
    /// MCP servers, trusted projects and preferences carry over. Best effort.
    private func seedConfigFile(_ tool: Tool, from source: Profile, to dest: Profile) {
        for link in tool.links where !link.isDirectory {
            guard let data = try? Data(contentsOf: slotURL(link, in: source)),
                  var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            for key in tool.accountKeysInConfigFile { obj.removeValue(forKey: key) }
            if let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
                try? out.write(to: slotURL(link, in: dest))
            }
        }
    }

    private func slotURL(_ link: ManagedLink, in profile: Profile) -> URL {
        profileDirectory(profile).appendingPathComponent(link.slotName, isDirectory: link.isDirectory)
    }

    // MARK: Sign-in

    func isSignedIn(_ tool: Tool, profile: Profile) -> Bool {
        signInStatus[profile.id]?[tool] ?? false
    }

    /// Recomputes `signInStatus`. Claude's token lives in the Keychain (live item for the
    /// active profile, parked copies for the others); Codex keeps a file in its slot.
    func refreshSignInStatus() {
        var result: [String: [Tool: Bool]] = [:]
        for profile in config.profiles {
            var byTool: [Tool: Bool] = [:]
            for tool in config.enabledTools {
                let dir = profileDirectory(profile)
                var ok = tool.signInMarkers.contains { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }
                if tool == .claude, !ok {
                    let service = profile.id == config.activeProfileID
                        ? KeychainTool.claudeLiveService
                        : KeychainTool.profileService(.claude, profile.id)
                    ok = KeychainTool.exists(service: service)
                }
                byTool[tool] = ok
            }
            result[profile.id] = byTool
        }
        signInStatus = result
    }

    /// Opens Terminal running the tool's login command. Writes a `.command` file so no
    /// Automation permission is needed. The tool writes into whatever profile is active.
    func openSignIn(_ tool: Tool) throws {
        let bin = baseDir.appendingPathComponent("bin", isDirectory: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        let file = bin.appendingPathComponent("signin-\(tool.rawValue).command")
        let script = """
        #!/bin/zsh
        clear
        echo "AgentSwitch · signing in to \(tool.displayName) for profile: \(activeProfile?.name ?? "?")"
        echo "When you're done, close this window."
        echo
        \(tool.loginCommand)
        """
        try Data(script.utf8).write(to: file)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        NSWorkspace.shared.open(file)
    }

    // MARK: Settings

    func setShowNameInMenuBar(_ show: Bool) {
        config.showNameInMenuBar = show
        try? saveConfig()
    }

    // MARK: Mappings

    func link(directory: String, to profileID: String) throws {
        guard profile(id: profileID) != nil else { throw EngineError.unknownProfile(profileID) }
        let path = Self.normalize(directory)
        config.mappings.removeAll { $0.path == path }
        config.mappings.append(ProjectMapping(path: path, profileID: profileID))
        config.mappings.sort { $0.path < $1.path }
        try saveConfig()
    }

    func unlink(directory: String) throws {
        config.mappings.removeAll { $0.path == directory }
        try saveConfig()
    }

    /// Most specific (longest) mapped directory containing `path`.
    func mapping(forPath path: String) -> ProjectMapping? {
        let p = Self.normalize(path)
        return config.mappings
            .filter { p == $0.path || p.hasPrefix($0.path + "/") }
            .max { $0.path.count < $1.path.count }
    }

    static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .resolvingSymlinksInPath().standardizedFileURL.path
    }

    // MARK: Helpers

    private enum Kind { case missing, symlink, real }

    private func kind(at url: URL) -> Kind {
        // attributesOfItem uses lstat, so symlinks are reported as symlinks.
        guard let type = (try? fm.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType else { return .missing }
        return type == .typeSymbolicLink ? .symlink : .real
    }

    private func isOurs(_ symlink: URL) -> Bool {
        guard let dest = try? fm.destinationOfSymbolicLink(atPath: symlink.path) else { return false }
        return dest.hasPrefix(profilesDir.path + "/")
    }

    private func nextProfileID() -> String {
        var n = 1
        while fm.fileExists(atPath: profilesDir.appendingPathComponent("profile_\(n)").path)
                || config.profiles.contains(where: { $0.id == "profile_\(n)" }) { n += 1 }
        return "profile_\(n)"
    }

    private func loadConfig() {
        guard let data = try? Data(contentsOf: configURL),
              let decoded = try? JSONDecoder().decode(Config.self, from: data) else { return }
        config = decoded
    }

    private func saveConfig() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(config).write(to: configURL, options: .atomic)
    }
}
