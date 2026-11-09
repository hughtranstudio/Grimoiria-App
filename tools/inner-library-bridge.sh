#!/bin/bash
# The Inner Library courier, for launchd (see docs/inner-library-bridge.md). Reads the bridge token from the
# Keychain so it is never in a file or on a command line, then runs one `grimoire bridge sync`.
set -euo pipefail
GRIMOIRE="${GRIMOIRE_BIN:-$HOME/grimoiria-app/.build/release/grimoire}"
INTIMA_BRIDGE_TOKEN="$(security find-generic-password -a "$USER" -s grimoiria-inner-library -w 2>/dev/null || true)"
if [ -z "$INTIMA_BRIDGE_TOKEN" ]; then
  echo "$(date '+%F %T') no token in the Keychain (service grimoiria-inner-library); see docs/inner-library-bridge.md" >&2
  exit 0
fi
export INTIMA_BRIDGE_TOKEN
echo "$(date '+%F %T') $("$GRIMOIRE" bridge sync "$@" 2>&1)"
