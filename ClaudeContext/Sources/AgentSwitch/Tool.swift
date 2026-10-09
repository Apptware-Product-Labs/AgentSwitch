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
