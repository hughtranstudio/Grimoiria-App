#!/bin/bash
# Keeps Grimoire on this Mac up to date by itself (Hugh, 9 Nov 2026: "make it easy for me to sync").
# Pulls GitHub main, rebuilds and installs ~/Applications/Grimoire.app when the code changed, and says
# whether the Brand Codex on the site has moved on. Installed by install-update.sh; runs every 30 minutes.
#   App/tools/update.sh          only when main changed (what the timer runs)
#   App/tools/update.sh --now    rebuild even if nothing changed
# Never quits a running Grimoire (you may be mid-session): the new build opens the next time you open it,
# and a notification says so. No keys here; it uses this Mac's git login. Log: ~/Library/Logs/grimoire-update.log
set -euo pipefail
export PATH="${GRIMOIRE_PATH:-/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
STATE="${GRIMOIRE_STATE:-$HOME/.grimoire-update}"
LOCK="$STATE.lock"
SITE="${MY_WEBSITE:-$HOME/Desktop/my-website}"
NOW=0; [[ "${1:-}" == "--now" ]] && NOW=1
mkdir -p "$STATE"
say() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M')" "$*"; }
notify() { osascript -e "display notification \"$1\" with title \"Grimoire\"" >/dev/null 2>&1 || true; }
# One run at a time: a build takes a few minutes.
if ! mkdir "$LOCK" 2>/dev/null; then
  if [[ -n "$(find "$LOCK" -maxdepth 0 -mmin +60 2>/dev/null)" ]]; then rmdir "$LOCK"; mkdir "$LOCK"; else exit 0; fi
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

cd "$REPO"
git fetch --quiet origin main || { say "GitHub not reachable; trying again next time."; exit 0; }
HEAD_MAIN=$(git rev-parse origin/main)
BUILT=$(cat "$STATE/built-commit" 2>/dev/null || echo none)

if [[ "$(git rev-parse HEAD)" != "$HEAD_MAIN" ]]; then
  if ! git merge --quiet --ff-only origin/main; then
    say "Could not fast-forward $REPO to main (local edits or another branch checked out). Nothing installed."
    exit 1
  fi
fi

if (( NOW )) || [[ "$BUILT" != "$HEAD_MAIN" ]]; then
  if "$REPO/App/build.sh" > "$STATE/last-build.log" 2>&1; then
    echo "$HEAD_MAIN" > "$STATE/built-commit"
    printf '%s %s built\n' "$(date '+%F %H:%M')" "$(git rev-parse --short HEAD)" >> "$STATE/log"
    if pgrep -x Grimoire >/dev/null; then
      say "Grimoire $(git rev-parse --short HEAD) installed; it opens the next time you open Grimoire."
      notify "Updated. Quit and reopen Grimoire when you are done to use the new version."
    else
      say "Grimoire $(git rev-parse --short HEAD) installed."
    fi
  else
    say "Build of $(git rev-parse --short HEAD) failed; the installed Grimoire was left as it was. See $STATE/last-build.log"
    notify "An update failed to build; the installed Grimoire is unchanged."
    exit 1
  fi
fi

# The locked backup, once a day, pushed to its private GitHub repo (backup.sh); a failure is logged, never stops the update.
bash "$REPO/App/tools/backup.sh" || say "Locked backup failed; see above."

# The Brand Codex: report a newer version on the site, never apply it here (brand changes wait for your yes).
# Best effort only: macOS can refuse a background job access to the Desktop, and that must never stop the run.
codex_note() {
  local pin="$REPO/App/Design/codex/tokens.json" ours theirs
  [[ -f "$pin" ]] || return 0
  theirs=$(sed -nE 's/^  "version": "([0-9.]+)".*/\1/p' "$SITE/brand/seed.json" 2>/dev/null | head -1) || return 0
  ours=$(sed -nE 's/.*Brand Codex ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' "$pin" | head -1)
  if [[ -n "$ours" && -n "$theirs" && "$ours" != "$theirs" && "$(cat "$STATE/codex-told" 2>/dev/null)" != "$theirs" ]]; then
    say "Brand Codex $theirs is in $SITE; Grimoire uses $ours. Ask Claude to take it (App/tools/sync-codex.py)."
    echo "$theirs" > "$STATE/codex-told"
  fi
}
codex_note || true
