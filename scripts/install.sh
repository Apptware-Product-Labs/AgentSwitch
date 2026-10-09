#!/usr/bin/env bash
# Builds AgentSwitch, backs up your existing agent config, installs to /Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build_app.sh

# Back up anything real (not already a symlink) that the first run will adopt.
STAMP=$(date +%Y%m%d-%H%M%S)
BK="$HOME/AgentSwitch-backup-$STAMP"
for p in .claude .claude.json .codex; do
  if [ -e "$HOME/$p" ] && [ ! -L "$HOME/$p" ]; then
    mkdir -p "$BK"
    cp -R "$HOME/$p" "$BK/"
  fi
done
[ -d "$BK" ] && echo "Backed up existing config to $BK"

DEST="/Applications/AgentSwitch.app"
pkill -x AgentSwitch 2>/dev/null || true
rm -rf "$DEST"
cp -R "build/AgentSwitch.app" "$DEST"
open "$DEST"
echo "Installed and launched $DEST"
