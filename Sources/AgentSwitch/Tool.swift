import Foundation

/// A CLI agent whose per-account state lives in the home directory.
/// Adding a tool means adding a case here and describing its paths.
enum Tool: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex:  "Codex"
        }
    }

    var symbol: String {
        switch self {
        case .claude: "sparkles"
        case .codex:  "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Human-readable list of what gets swapped, shown in Preferences.
    var summary: String {
        links.map { "~/\($0.homeName)" }.joined(separator: " · ")
    }

    /// Shell command that signs this tool in to the *active* profile.
    var loginCommand: String {
        switch self {
        case .claude: "claude"
        case .codex:  "codex login"
        }
    }

    /// Files (relative to the profile directory) whose presence means "signed in".
    var signInMarkers: [String] {
        switch self {
        case .claude: ["claude/.credentials.json"]
        case .codex:  ["codex/auth.json"]
        }
    }

    /// Items inside the tool's directory that are *your* configuration rather than
    /// account state. They live once in `shared/<tool>/` and every profile links to them,
    /// so a command or skill added in one profile is there in all of them.
    var sharedItems: [String] {
        switch self {
        case .claude: ["commands", "skills", "agents", "plugins", "hooks", "dev-mods",
                       "settings.json", "settings.local.json", "CLAUDE.md", "keybindings.json"]
        case .codex:  ["AGENTS.md", "config.toml", "skills", "rules", "prompts", "plugins"]
        }
    }

    /// Keys in `~/.claude.json` that identify the account; everything else (MCP servers,
    /// project trust, preferences) is copied into new profiles.
    var accountKeysInConfigFile: [String] {
        switch self {
        case .claude: ["oauthAccount", "userID"]
        case .codex:  []
        }
    }

    /// Paths in $HOME this tool reads, and the slot inside a profile that backs each.
    var links: [ManagedLink] {
        switch self {
        case .claude:
            [ManagedLink(homeName: ".claude", slotName: "claude", isDirectory: true),
             ManagedLink(homeName: ".claude.json", slotName: "claude.json", isDirectory: false, emptyContents: "{}")]
        case .codex:
            [ManagedLink(homeName: ".codex", slotName: "codex", isDirectory: true)]
        }
    }
}

struct ManagedLink {
    let homeName: String        // e.g. ".claude"
    let slotName: String        // e.g. "claude" (relative to the profile directory)
    let isDirectory: Bool
    var emptyContents = ""      // what to write when creating an empty file slot
}
