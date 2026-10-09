# AgentSwitch

**One menu bar app. Multiple Claude Code and Codex accounts. The right one, automatically, for every project.**

If you use one Claude or Codex account for client work and another for your own projects, you know the routine: log out, log in, repeat every time you change folders. AgentSwitch ends that. You tell it which folders belong to which account, and it switches for you the moment you open one in VS Code or Zed.

---

## What you get

- **Profiles.** Each profile is a separate login for Claude Code and Codex. Create as many as you need.
- **Automatic switching.** Link a project folder to a profile. When that folder is open in VS Code or Zed, AgentSwitch switches to it.
- **One-click manual switching** from the menu bar when you want to override.
- **Your setup stays yours.** Custom commands, skills, plugins and settings are shared across all profiles. Only the login changes.
- **Nothing is deleted, ever.** Your existing setup becomes the first profile. Uninstalling puts everything back the way it was.

---

## Requirements

- macOS 13 or newer
- Xcode Command Line Tools. If you don't have them, run:
  ```bash
  xcode-select --install
  ```
- VS Code or Zed, if you want automatic switching

---

## Install

Open Terminal and run these four commands:

```bash
git clone https://github.com/Apptware-Product-Labs/AgentSwitch.git
cd AgentSwitch
./scripts/make_signing_cert.sh
./scripts/install.sh
```

What happens:

1. `make_signing_cert.sh` creates a local signing certificate (one time). macOS asks for your password once. This keeps the Accessibility permission working across updates.
2. `install.sh` builds the app, backs up your current `~/.claude` and `~/.codex` folders to `~/AgentSwitch-backup-<date>`, installs to `/Applications`, and launches it.

When the app starts, macOS asks for **Accessibility** access. Click **Open System Settings** and turn on the toggle for AgentSwitch. This lets the app see which folder your editor has open. Without it, automatic switching is off (the app tells you so in its panel).

---

## First-time setup

Click the AgentSwitch icon in your menu bar. Your current login is already there as the **Default** profile.

### 1. Add a profile for your other account

Click **New Profile…**, type a name (for example, "Client" or "Personal") and press Enter. The new profile becomes active and shows an orange dot next to each tool, meaning not signed in yet.

### 2. Sign in

Click **Sign in to Claude Code…**. A Terminal window opens. Log in with the account you want for this profile, then close the window. Do the same for **Sign in to Codex…** if you use Codex. The dots turn green.

### 3. Link your projects

Click the **+** next to **Projects** and choose the folders that belong to this profile. You can ⌘-click to select several at once. Each folder appears in the panel with the profile it belongs to. To change a folder's profile later, click its label in the panel.

That's it. Open one of those folders in VS Code or Zed and watch the name in the menu bar change.

---

## Everyday use

| Want to… | Do this |
|---|---|
| See which account is active | Look at the name next to the menu bar icon |
| Switch manually | Click the icon, then click a profile |
| Add a project to a profile | Click **+** next to Projects (the active profile is pre-selected) |
| Move a project to another profile | Click the profile label on that project row |
| Remove a project | Click its label, then **Unlink** |
| Rename or delete a profile | **Preferences… ▸ Profiles** |
| Start at login | **Preferences… ▸ General ▸ Launch at login** |

**Good to know:** a Claude or Codex session that's already running keeps the account it started with. The switch applies when you start a new one.

---

## Updating

```bash
cd AgentSwitch
git pull
./scripts/install.sh
```

Your profiles, logins and project links are stored outside the app and survive updates.

---

## Uninstall

```bash
cd AgentSwitch
./scripts/uninstall.sh
```

This removes the app and puts your currently active profile back as a normal `~/.claude` and `~/.codex`, exactly as the tools expect. Your other profiles stay saved in `~/.config/agentswitch` in case you reinstall. To delete those too:

```bash
./scripts/uninstall.sh --purge
```

---

## Troubleshooting

**The panel says "Auto-switching is off" even though Accessibility is turned on.**
macOS is remembering an older build. Run this, then relaunch the app and grant access again:
```bash
tccutil reset Accessibility dev.agentswitch.app
```

**My custom commands or skills disappeared after creating a profile.**
Update to the latest version. Early builds kept these per profile. They are now shared across all profiles.

**The editor is in front, but the profile doesn't switch.**
Open the panel. The row near the bottom shows what AgentSwitch sees in the editor window and whether it matched a linked folder. If the folder is shown but not linked, link it with **+**.

**macOS says the app can't be opened or is from an unidentified developer.**
This happens with pre-built downloads that haven't been notarized. Right-click the app, choose **Open**, then confirm. Installing from source with `install.sh` avoids this.

---

## How it works

For the curious.

- Each profile lives in `~/.config/agentswitch/profiles/<id>/`.
- `~/.claude`, `~/.claude.json` and `~/.codex` are symbolic links that point at the active profile. Switching repoints the links atomically.
- Claude Code stores its login token in the macOS Keychain under a name tied to the `~/.claude` path, so changing the link alone isn't enough. AgentSwitch parks each profile's token in the Keychain and swaps it on every switch, using the same `security` tool Claude Code uses.
- Shared configuration (`commands/`, `skills/`, `agents/`, `plugins/`, `hooks/`, `settings.json`, `CLAUDE.md` for Claude; `AGENTS.md`, `config.toml`, `skills/`, `rules/`, `prompts/` for Codex) lives in `~/.config/agentswitch/shared/` and every profile links to it.
- To detect the open project, the app reads the focused editor window through the Accessibility API: the document path in VS Code, the window title in Zed.

### Project layout

```
Sources/AgentSwitch/
  AgentSwitchApp.swift        entry point, menu-bar-only app
  MenuManager.swift           status item, popover panel, Preferences window
  ProfileEngine.swift         profiles, symlink swap, shared config, Keychain swap
  KeychainTool.swift          wrapper over /usr/bin/security
  Tool.swift                  what each tool stores where (add a case to support another CLI)
  WorkspaceWatcher.swift      detects the open folder in VS Code / Zed
  Views/MenuPanelView.swift   the dropdown
  Views/PreferencesView.swift
scripts/
  install.sh  uninstall.sh  build_app.sh  release.sh  make_signing_cert.sh  sandbox_test.sh
```

`scripts/sandbox_test.sh` runs the app against a throwaway home folder and prints the result. Use it when changing the engine.

### Building a release

`scripts/release.sh` produces a zip in `build/`. For a download that opens without warnings, set `CODESIGN_IDENTITY` to a Developer ID certificate and `NOTARY_PROFILE` to a notarytool profile; see the script header.

---

## License

MIT
