#!/usr/bin/env bash
# Runs the debug binary against a throwaway $HOME and prints the resulting layout.
# Never touches your real ~/.claude / ~/.codex / keychain-parked tokens (no profile switch happens).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build >/dev/null
T=$(mktemp -d)/home; mkdir -p "$T"
CFG="$T/.config/agentswitch"; P="$CFG/profiles"
mkdir -p "$P/profile_1/claude/commands" "$P/profile_1/claude/skills/council" "$P/profile_1/codex" "$P/profile_2/claude/skills" "$P/profile_2/codex"
echo 'council cmd' > "$P/profile_1/claude/commands/council.md"
echo '{"theme":"dark"}' > "$P/profile_1/claude/settings.json"
echo '{"oauthAccount":{"email":"a@x"},"mcpServers":{"foo":{}},"userID":"u1"}' > "$P/profile_1/claude.json"
echo '{"fresh":true}' > "$P/profile_2/claude/settings.json"
echo '{"oauthAccount":{"email":"b@x"}}' > "$P/profile_2/claude.json"
echo 'agents' > "$P/profile_1/codex/AGENTS.md"
cat > "$CFG/config.json" <<JSON
{"activeProfileID":"profile_2","enabledTools":["claude","codex"],"mappings":[],
 "profiles":[{"id":"profile_1","name":"Default"},{"id":"profile_2","name":"Vinyl"}],"showNameInMenuBar":true}
JSON
HOME="$T" .build/debug/AgentSwitch & PID=$!  # killed by PID below — never pkill, that would quit the real app
sleep 3; kill $PID 2>/dev/null || true
echo "--- shared"; find "$CFG/shared" | sed "s|$CFG/||"
echo "--- profile links"; for p in profile_1 profile_2; do for i in commands skills settings.json; do printf "%s/claude/%s -> " $p $i; readlink "$P/$p/claude/$i" | sed "s|$CFG/||" || echo "(not a link)"; done; done
echo "--- set aside"; ls "$P/profile_2/claude" | grep before-shared || echo none
echo "--- active profile sees commands:"; ls "$T/.claude/commands/"
rm -rf "$(dirname "$T")"
