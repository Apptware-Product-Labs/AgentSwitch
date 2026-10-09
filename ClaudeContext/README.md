# Claude Switch

A tiny macOS menu bar app that switches your Claude Code account when you switch projects in **VS Code** or **Zed** — no `claude /logout`, no `direnv`, no env vars.

## How it works

- Each profile lives in `~/.config/claudecontext/profiles/profile_N/`.
- The active profile is exposed by symlinking `~/.claude` (and `~/.claude.json`) to it. Swaps are atomic (temp symlink + `rename(2)`).
- Link a folder to a profile once. When VS Code/Zed is frontmost and its window's file/title matches a linked folder, the symlink is swapped.

```
Sources/ClaudeContext/
  ClaudeContextApp.swift   entry point, .accessory activation policy
  MenuManager.swift        NSStatusItem + menu
  ProfileEngine.swift      config, profiles, atomic symlink swapping
  WorkspaceWatcher.swift   NSWorkspace + Accessibility workspace detection
  PreferencesView.swift    SwiftUI profile / project-map manager
```

## Build

**Xcode:** `File ▸ Open…` the repo folder (it's a Swift Package), pick the `ClaudeContext` scheme, ⌘R.
**Terminal:** `./scripts/build_app.sh` → `"build/Claude Switch.app"`, then `open build/Claude Switch.app`.

Requires macOS 13+. Grant **Accessibility** access when prompted (System Settings ▸ Privacy & Security ▸ Accessibility) — it's needed to read the editor's window title/document.

## First run

Your existing `~/.claude` and `~/.claude.json` are **moved** (not deleted) into a profile called "Default". Claude Switch refuses to overwrite a real file or folder at those paths.

## Known limitations

- **Keychain credentials:** on macOS, Claude Code may store login tokens in the Keychain rather than in `~/.claude`. If so, swapping the folder alone won't switch accounts. Verify with `claude` after switching; see the issue tracker.
- Running `claude` sessions keep using the profile they started with; the swap affects new sessions.
- Workspace detection uses the focused window's `AXDocument` / title. Titles are matched by folder name, so two linked folders with the same name are ambiguous.
- Ad-hoc signed builds lose the Accessibility grant after each rebuild; re-add the app.

## License

MIT
