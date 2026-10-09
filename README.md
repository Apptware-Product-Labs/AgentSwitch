# AgentSwitch

A small macOS menu bar app that keeps separate **Claude Code** and **Codex** accounts per profile and switches between them automatically when you open a linked project in **VS Code** or **Zed**. No `claude /logout`, no `direnv`, no environment variables.

## Why

If you keep client work and personal work on different subscriptions, switching accounts in the CLI is a logout/login dance every time you change project. AgentSwitch makes the account follow the project.

## How it works

- Each profile has its own folder under `~/.config/agentswitch/profiles/`.
- `~/.claude`, `~/.claude.json` and `~/.codex` are symlinks to the active profile. Swaps are atomic (temp symlink + `rename(2)`).
- Claude Code keeps its OAuth token in the Keychain, keyed by the literal `~/.claude` path, so AgentSwitch parks that token per profile (`AgentSwitch-claude-<id>`) and swaps it on every switch, using the same `/usr/bin/security` tool Claude Code uses.
- Link a folder to a profile. While VS Code or Zed is frontmost, the app reads the focused window (Accessibility API) and switches when the folder matches.

### Per profile vs shared

| Per profile (account state) | Shared across profiles (your config) |
|---|---|
| Claude login, `~/.claude.json`, history, sessions, projects | `commands/`, `skills/`, `agents/`, `plugins/`, `hooks/`, `settings.json`, `CLAUDE.md` |
| Codex `auth.json`, sessions, logs | `AGENTS.md`, `config.toml`, `skills/`, `rules/`, `prompts/` |

Shared items live in `~/.config/agentswitch/shared/<tool>/`; every profile symlinks to them, so a command you add in one profile is in all of them. New profiles also inherit MCP servers and trusted projects from `~/.claude.json` (minus the account identity).

## Install from source

Requires macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not needed.

```bash
git clone https://github.com/Apptware-Product-Labs/AgentSwitch.git
cd AgentSwitch
./scripts/make_signing_cert.sh   # once; keeps the Accessibility grant across rebuilds
./scripts/install.sh             # builds, backs up ~/.claude & ~/.codex, installs to /Applications, launches
```

Then:

1. Grant **Accessibility** when prompted (System Settings ▸ Privacy & Security ▸ Accessibility). This is what lets the app see which folder your editor has open.
2. Click the menu bar icon ▸ **New Profile…**, then **Sign in to Claude Code…** / **Sign in to Codex…**. A Terminal window opens with the login command for that profile.
3. Click **+** next to **Projects** and pick the folders that belong to each profile (⌘-click for several).

Your existing login becomes the **Default** profile. Nothing is deleted; `install.sh` also copies `~/.claude`, `~/.claude.json` and `~/.codex` to `~/AgentSwitch-backup-<date>` first.

### Updating

```bash
git pull && ./scripts/install.sh
```

Profiles, logins and project links live outside the app bundle and survive updates.

## Uninstall

```bash
./scripts/uninstall.sh           # restores the active profile into ~/.claude etc.; keeps other profiles
./scripts/uninstall.sh --purge   # also deletes ~/.config/agentswitch and parked Keychain tokens
```

Shared config (commands, skills…) is copied back into `~/.claude` as real folders, so nothing depends on AgentSwitch afterwards.

## Project layout

```
Sources/AgentSwitch/
  AgentSwitchApp.swift      entry point, .accessory activation policy (no Dock icon)
  MenuManager.swift         NSStatusItem, popover panel, Preferences window
  ProfileEngine.swift       profiles, atomic symlink swap, shared config, Keychain swap
  KeychainTool.swift        thin wrapper over /usr/bin/security
  Tool.swift                what each tool stores where (add a case to support another CLI)
  WorkspaceWatcher.swift    NSWorkspace + Accessibility: which folder is open in VS Code / Zed
  Views/MenuPanelView.swift SwiftUI dropdown
  Views/PreferencesView.swift
scripts/
  install.sh  uninstall.sh  build_app.sh  release.sh  make_signing_cert.sh  sandbox_test.sh
```

`scripts/sandbox_test.sh` runs the app against a throwaway `$HOME` and prints the resulting layout — handy when changing the engine.

## Releasing a signed build

`scripts/release.sh` produces `build/AgentSwitch-<version>.zip`. For a Gatekeeper-clean download it needs a Developer ID certificate and notarization (see the script header). Without them, recipients must right-click ▸ Open the app the first time.

## Known limitations

- Running `claude` / `codex` sessions keep the account they started with; the switch applies to new sessions.
- Workspace detection matches the focused window's document path (VS Code) or title segments (Zed) against linked folder names, so two linked folders with the same name are ambiguous.
- Tested with the Claude Code and Codex versions current as of October 2026. If a future Claude Code release changes how it stores its token, the Keychain swap will need updating (`KeychainTool.swift`).
- Ad-hoc signed builds lose the Accessibility grant on every rebuild — run `make_signing_cert.sh` once to avoid that.

## License

MIT
