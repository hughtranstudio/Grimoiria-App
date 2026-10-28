#!/usr/bin/env bash
# End-to-end run of the core through the CLI: phone capture → Inbox → confirm → export.
# Usage: tools/e2e-demo.sh [workdir]   (needs `swift build` first)
set -euo pipefail
cd "$(dirname "$0")/.."
B=.build/debug/grimoire
W=${1:-$(mktemp -d)}
export GRIMOIRE_STORE="$W/store.json"
mkdir -p "$W/GrimoireInbox/incoming"
cp Tests/GrimoireCoreTests/Fixtures/capture/* "$W/GrimoireInbox/incoming/"
echo "== ingest (San Francisco location for planetary hours)"
$B ingest "$W/GrimoireInbox" --stable-seconds 0 --lat 37.77 --lon -122.42 --tz America/Los_Angeles
echo "== drop the same capture again"
cp Tests/GrimoireCoreTests/Fixtures/capture/*.json "$W/GrimoireInbox/incoming/"
$B ingest "$W/GrimoireInbox" --stable-seconds 0
echo "== inbox"
$B inbox
ID=$($B inbox | head -1 | cut -d' ' -f1)
echo "== confirm with a 1 week reminder"
$B confirm "$ID" --reminder 1w
$B inquiries --open
echo "== needs outcome on 2026-11-05"
$B needs-outcome --today 2026-11-05
echo "== search 'tower'"
$B search tower
echo "== export twice (second run should change nothing)"
$B export --out "$W/vault"
$B export --out "$W/vault"
echo "workdir: $W"
