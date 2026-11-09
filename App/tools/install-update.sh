#!/bin/bash
# One line to keep Grimoire in step with everything else. Safe to run again.
#   bash ~/grimoiria-app-main/App/tools/install-update.sh
# It:
#   1. builds and installs Grimoire now from GitHub main (update.sh --now),
#   2. checks for a new main every 30 minutes and rebuilds when it changed (update.sh),
#   3. opens Grimoire in the background when you log in, so captures, charts and the Chamber's
#      Grimoire line stay current without you opening it,
#   4. gives Claude Code on this Mac read-only access to the grimoire (grimoire mcp --read-only).
# Undo:
#   for l in com.hughtran.grimoire-update com.hughtran.grimoire-open; do launchctl bootout gui/$(id -u)/$l; rm ~/Library/LaunchAgents/$l.plist; done
#   claude mcp remove grimoire --scope user
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
UID_=$(id -u)
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
chmod +x "$HERE/update.sh" "$HERE/../build.sh"

echo "Building Grimoire from main (a few minutes)…"
bash "$HERE/update.sh" --now | tee -a "$HOME/Library/Logs/grimoire-update.log"

agent() { # label, program arguments as <string> lines, extra keys
  local label=$1 args=$2 extra=$3 plist="$HOME/Library/LaunchAgents/$1.plist"
  cat > "$plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>$args</array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin</string><key>HOME</key><string>$HOME</string></dict>
  $extra
  <key>StandardOutPath</key><string>$HOME/Library/Logs/grimoire-update.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/grimoire-update.log</string>
</dict></plist>
PL
  launchctl bootout "gui/$UID_/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$UID_" "$plist"
}
agent com.hughtran.grimoire-update "<string>/bin/bash</string><string>$HERE/update.sh</string>" \
  "<key>StartInterval</key><integer>1800</integer>"
agent com.hughtran.grimoire-open "<string>/usr/bin/open</string><string>-g</string><string>-j</string><string>$HOME/Applications/Grimoire.app</string>" \
  "<key>RunAtLoad</key><true/>"

mcp="skipped (Claude Code not found)"
if command -v claude >/dev/null 2>&1; then
  if claude mcp get grimoire >/dev/null 2>&1; then mcp="already there"
  elif claude mcp add --scope user grimoire -- "$HOME/.local/bin/grimoire" mcp --read-only >/dev/null 2>&1; then mcp="added, read-only"
  else mcp="could not be added; run: claude mcp add --scope user grimoire -- ~/.local/bin/grimoire mcp --read-only"; fi
fi

echo
echo "Done. Grimoire now keeps itself up to date (checks every 30 minutes) and opens quietly when you log in."
echo "Claude Code access to the grimoire: $mcp"
echo "Log: ~/Library/Logs/grimoire-update.log"
