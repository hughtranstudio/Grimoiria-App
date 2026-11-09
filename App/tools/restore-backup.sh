#!/bin/bash
# Opens the locked backup into a new folder on the Desktop. Changes nothing in Grimoire or the vault.
#   bash App/tools/restore-backup.sh ["<vault>/Grimoire Backup"] [key file]
# Then, to use it: quit Grimoire and copy the restored Grimoire.store, Definitions, settings and Attachments
# into ~/Library/Application Support/Grimoire/ (keep the old folder until you have checked it).
set -euo pipefail
export PATH="${GRIMOIRE_PATH:-/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin}"
EXPORT="$(defaults read studio.htd.grimoire vault.path 2>/dev/null || echo "$HOME/HT-Press-Vault/Grimoire")"
SRC="${1:-$(dirname "$EXPORT")/Grimoire Backup}"
KEY="${2:-$HOME/.config/grimoire/backup-key.txt}"
DEST="${GRIMOIRE_RESTORE_TO:-$HOME/Desktop/Grimoire restored $(date +%Y-%m-%d-%H%M)}"
command -v age >/dev/null || { echo "Install age first: brew install age"; exit 1; }
[[ -f "$SRC/grimoire.tar.age" ]] || { echo "No backup at $SRC"; exit 1; }
[[ -f "$KEY" ]] || { echo "No key at $KEY. Paste the key from your password manager into a file and pass its path."; exit 1; }
umask 077
mkdir -p "$DEST"
age -d -i "$KEY" "$SRC/grimoire.tar.age" | tar -C "$DEST" -xf -
mv "$DEST/grimoire"/* "$DEST/" && rmdir "$DEST/grimoire"
n=0; missing=0
while IFS=$'\t' read -r id rel; do
  [[ -n "$id" ]] || continue
  if [[ -f "$SRC/attachments/$id.age" ]]; then
    mkdir -p "$DEST/Attachments/$(dirname "$rel")"
    age -d -i "$KEY" -o "$DEST/Attachments/$rel" "$SRC/attachments/$id.age"; n=$((n + 1))
  else missing=$((missing + 1)); fi
done < "$DEST/attachments-index.tsv"
note=""; (( missing )) && note=" ($missing not in the backup yet)"
echo "Restored to $DEST: database, settings, Definitions and $n attachment(s)$note."
