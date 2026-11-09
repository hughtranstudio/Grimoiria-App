#!/bin/bash
# Puts the locked Grimoire backup in its own private GitHub repo (Hugh, 9 Nov 2026: "Its own private repo").
# Run once; safe to run again:
#   bash ~/grimoiria-app-main/App/tools/setup-github-backup.sh
# It:
#   1. signs this Mac in to GitHub with the GitHub CLI (a browser page asks you to approve; skipped when
#      already signed in) and lets git use that sign-in,
#   2. makes the private repo hughtranstudio/grimoire-backup (skipped when it exists),
#   3. moves the backup folder out of the vault to ~/Grimoire Backup, so the vault no longer holds it,
#   4. lets only locked files (*.age) and the README into git, then pushes.
# From then on the daily backup (backup.sh, run by update.sh) pushes by itself.
# Undo: rm -rf "$HOME/Grimoire Backup/.git" ~/.grimoire-update/backup-dir  (the repo on GitHub stays until you delete it)
set -euo pipefail
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_NAME="${GRIMOIRE_BACKUP_REPO:-hughtranstudio/grimoire-backup}"
STATE="$HOME/.grimoire-update"
NEW="${GRIMOIRE_BACKUP_DIR:-$HOME/Grimoire Backup}"
EXPORT="$(defaults read studio.htd.grimoire vault.path 2>/dev/null || echo "$HOME/HT-Press-Vault/Grimoire")"
OLD="$(dirname "$EXPORT")/Grimoire Backup"
mkdir -p "$STATE"

# 1. GitHub sign-in.
command -v gh >/dev/null || { echo "Installing the GitHub CLI…"; brew install --quiet gh; }
if ! gh auth status >/dev/null 2>&1; then
  echo
  echo "Signing this Mac in to GitHub. Press Enter when asked, then approve in the browser"
  echo "(copy the 8-character code it shows into the page)."
  gh auth login --hostname github.com --git-protocol https --web
fi
gh auth setup-git

# 2. The private repo.
if gh repo view "$REPO_NAME" >/dev/null 2>&1; then echo "Repo $REPO_NAME is there."
else gh repo create "$REPO_NAME" --private --description "Locked (age-encrypted) backup of the Grimoire app. Unreadable without the key." >/dev/null
  echo "Made the private repo $REPO_NAME."
fi
[[ "$(gh repo view "$REPO_NAME" --json visibility -q .visibility)" == "PRIVATE" ]] || { echo "Stopped: $REPO_NAME is not private."; exit 1; }

# 3. The folder, out of the vault.
if [[ -d "$OLD" && ! -e "$NEW" ]]; then mv "$OLD" "$NEW"; echo "Moved the backup folder to $NEW."
elif [[ -d "$OLD" && -d "$NEW" ]]; then echo "Both $OLD and $NEW exist; using $NEW (the old one can go once this works)."
fi
mkdir -p "$NEW"
echo "$NEW" > "$STATE/backup-dir"

# 4. Only locked files go into git.
cd "$NEW"
[[ -d .git ]] || git init -q -b main
git config user.name "Grimoire backup"
git config user.email "grimoire-backup@users.noreply.github.com"
cat > .gitignore <<'GI'
# Only locked files and the README leave this Mac.
*
!.gitignore
!README.md
!*.age
!attachments/
GI
url="https://github.com/$REPO_NAME.git"
git remote get-url origin >/dev/null 2>&1 && git remote set-url origin "$url" || git remote add origin "$url"
git fetch -q origin main 2>/dev/null && ! git rev-parse -q --verify HEAD >/dev/null && git reset -q --soft origin/main || true

# Write today's backup into the new place and push it (backup.sh commits and pushes).
bash "$HERE/backup.sh" --now
echo
if git -C "$NEW" rev-list '@{u}..HEAD' >/dev/null 2>&1 && [[ -z "$(git -C "$NEW" rev-list '@{u}..HEAD')" ]]; then
  echo "Done. The locked backup is on GitHub (private): https://github.com/$REPO_NAME"
  echo "Only these files are there:"; git -C "$NEW" ls-files | sed 's/^/  /' | head -20
else
  echo "The backup is written but did not reach GitHub. Details: $STATE/backup-push.log"
  exit 1
fi
