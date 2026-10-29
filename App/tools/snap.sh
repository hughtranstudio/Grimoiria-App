#!/bin/zsh
# Snapshots of every page in light and dark, with seed data, on a fresh test store.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=today,settings tools/snap.sh
set -u
app=~/Applications/Grimoire.app/Contents/MacOS/Grimoire
store=/tmp/Grimoire-test.store
shots=/tmp/Grimoire-shots
rm -rf ~/Library/Saved\ Application\ State/studio.htd.grimoire.savedState
rm -rf $store $store-shm $store-wal /tmp/Grimoire-test-files
rm -rf $shots
APP_STORE=$store APP_SEED=1 APP_SNAPSHOT=$shots $app
