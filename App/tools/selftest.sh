#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp, then relaunches to
# check that everything is still there. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/studio.htd.grimoire.savedState
store=/tmp/Grimoire-self.store
rm -rf $store $store-shm $store-wal /tmp/Grimoire-self-files
app=~/Applications/Grimoire.app/Contents/MacOS/Grimoire
APP_STORE=$store $app --selftest || exit 1
APP_STORE=$store $app --selftest-reopen
