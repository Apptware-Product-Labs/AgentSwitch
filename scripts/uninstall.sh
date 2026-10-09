#!/usr/bin/env bash
# Removes AgentSwitch and puts the ACTIVE profile back as plain folders/files in $HOME,
# exactly as the tools expect. Other profiles stay in ~/.config/agentswitch/profiles
# unless you pass --purge.
#
#   scripts/uninstall.sh            keep other profiles and parked logins
#   scripts/uninstall.sh --purge    also delete ~/.config/agentswitch and parked Keychain tokens
set -euo pipefail

CFG="$HOME/.config/agentswitch"
APP="${AGENTSWITCH_APP:-/Applications/AgentSwitch.app}"
PURGE=0; [ "${1:-}" = "--purge" ] && PURGE=1

if [ ! -f "$CFG/config.json" ]; then
  echo "No AgentSwitch config found at $CFG — nothing to restore."
else
  ACTIVE=$(python3 -c "import json;print(json.load(open('$CFG/config.json'))['activeProfileID'])")
  SLOT="$CFG/profiles/$ACTIVE"
  echo "Restoring active profile ($ACTIVE) into \$HOME…"

  pkill -x AgentSwitch 2>/dev/null || true
  sleep 0.5

  # home path → slot path (keep in sync with Tool.swift)
  restore() {
    local home="$HOME/$1" slot="$SLOT/$2"
    if [ -L "$home" ]; then
      rm "$home"
    elif [ -e "$home" ]; then
      echo "  $home is already a real file/folder — leaving it alone."
      return
    fi
    [ -e "$slot" ] || return 0
    mv "$slot" "$home"
    echo "  restored $home"
  }
  restore .claude       claude
  restore .claude.json  claude.json
  restore .codex        codex

  # Shared config items are symlinks into $CFG/shared; turn them into real copies so
  # they survive --purge and don't depend on AgentSwitch any more.
  for dir in "$HOME/.claude" "$HOME/.codex"; do
    [ -d "$dir" ] || continue
    for item in "$dir"/* "$dir"/.[!.]*; do
      [ -L "$item" ] || continue
      target=$(readlink "$item")
      case "$target" in "$CFG/shared/"*)
        rm "$item"; cp -R "$target" "$item"; echo "  materialised $(basename "$item")";;
      esac
    done
  done
fi

[ -e "$APP" ] && rm -rf "$APP" && echo "Removed $APP"

if [ $PURGE -eq 1 ]; then
  rm -rf "$CFG"
  echo "Deleted $CFG (other profiles are gone)."
  # Parked Claude tokens for non-active profiles.
  for i in $(seq 1 50); do security delete-generic-password -s "AgentSwitch-claude-profile_$i" >/dev/null 2>&1 || true; done
  echo "Removed parked Keychain tokens."
else
  echo "Kept $CFG (other profiles + parked logins). Re-run with --purge to delete them."
fi
echo "Done. Your current Claude Code / Codex login is unchanged."
