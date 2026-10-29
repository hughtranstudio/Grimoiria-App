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
echo "== confirm (outcome check-ins at 7, 30 and 90 days)"
$B confirm "$ID"
$B inquiries --open
echo "== needs outcome on 2026-11-05"
$B needs-outcome --today 2026-11-05
INQ=$($B inquiries | head -1 | cut -d' ' -f1)
echo "== log an outcome; the ladder rolls on to the 30-day check-in"
$B outcome "$INQ" "Plans changed as the reading suggested" --fulfilled partly --date 2026-11-05T09:00:00-08:00
$B needs-outcome --today 2026-11-05
echo "== fill astro context on a manual entry"
$B add journal "Evening LBRP, felt settled"
$B timing-fill --lat 37.77 --lon -122.42
echo "== search 'tower'"
$B search tower
echo "== export twice (second run should change nothing)"
$B export --out "$W/vault"
$B export --out "$W/vault"
echo "workdir: $W"
