#!/bin/bash
# The locked GitHub backup (Hugh, 9 Nov 2026: "Locked backup (encrypted)").
# Writes an encrypted copy of the whole grimoire into "<vault>/Grimoire Backup/". The vault's own GitHub
# backup (Obsidian Git) carries it off the Mac, so GitHub only ever holds locked files.
#   App/tools/backup.sh            once a day (update.sh calls it); does nothing when nothing changed
#   App/tools/backup.sh --now      write it now
# What is inside: the database (a consistent snapshot), Definitions, your settings files, the open-format
# export (grimoire.jsonl), and every attachment (audio, photos), each encrypted on its own and only once.
# The key: ~/.config/grimoire/backup-key.txt, made by install-update.sh. Without it the backup cannot be
# opened, so keep a copy in your password manager. Restore: App/tools/restore-backup.sh
set -euo pipefail
export PATH="${GRIMOIRE_PATH:-/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin}"
DATA="${GRIMOIRE_DATA:-$HOME/Library/Application Support/Grimoire}"
KEY="${GRIMOIRE_BACKUP_KEY:-$HOME/.config/grimoire/backup-key.txt}"
STATE="${GRIMOIRE_STATE:-$HOME/.grimoire-update}"
NOW=0; [[ "${1:-}" == "--now" ]] && NOW=1
say() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M')" "$*"; }
mkdir -p "$STATE"

# Where: beside the Obsidian export folder chosen in Grimoire's Settings (…/HT-Press-Vault/Grimoire).
EXPORT="${GRIMOIRE_EXPORT:-$(defaults read studio.htd.grimoire vault.path 2>/dev/null || true)}"
[[ -n "$EXPORT" ]] || EXPORT="$HOME/HT-Press-Vault/Grimoire"
OUT="${GRIMOIRE_BACKUP_DIR:-$(dirname "$EXPORT")/Grimoire Backup}"

command -v age >/dev/null || { say "Backup skipped: age is not installed (brew install age)."; exit 0; }
[[ -f "$KEY" ]] || { say "Backup skipped: no key at $KEY (run install-update.sh)."; exit 0; }
[[ -d "$DATA" ]] || { say "Backup skipped: no Grimoire data at $DATA."; exit 0; }
(( NOW )) || [[ "$(cat "$STATE/backup-day" 2>/dev/null)" != "$(date +%F)" ]] || exit 0

RECIPIENT=$(age-keygen -y "$KEY")
umask 077
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT/attachments" "$WORK/grimoire"
hash() { if command -v shasum >/dev/null; then shasum -a 256 "$@"; else sha256sum "$@"; fi; }

# 1. The database: a consistent copy even while Grimoire is open (SQLite's own backup, WAL included).
STORE="$DATA/Grimoire.store"
if [[ -f "$STORE" ]]; then sqlite3 "$STORE" ".backup '$WORK/grimoire/Grimoire.store'"; fi
# 2. Small things, copied as they are.
for f in "$DATA"/*.json; do [[ -f "$f" ]] && cp "$f" "$WORK/grimoire/"; done
[[ -d "$DATA/Definitions" ]] && cp -R "$DATA/Definitions" "$WORK/grimoire/Definitions"
[[ -f "$EXPORT/grimoire.jsonl" ]] && cp "$EXPORT/grimoire.jsonl" "$WORK/grimoire/"

# 3. Attachments: each one encrypted once, under a name that says nothing about it.
new=0; big=0
: > "$WORK/grimoire/attachments-index.tsv"
if [[ -d "$DATA/Attachments" ]]; then
  while IFS= read -r -d '' f; do
    rel=${f#"$DATA/Attachments/"}
    id=$(printf '%s' "$rel" | hash | cut -c1-32)
    printf '%s\t%s\n' "$id" "$rel" >> "$WORK/grimoire/attachments-index.tsv"
    # GitHub refuses files over 100 MB; such a recording stays on the Mac and is named in the log.
    if (( $(wc -c < "$f") > 95000000 )); then big=$((big + 1)); say "Too big for GitHub, kept on the Mac only: $rel"; continue; fi
    if [[ ! -f "$OUT/attachments/$id.age" || "$f" -nt "$OUT/attachments/$id.age" ]]; then
      age -r "$RECIPIENT" -o "$OUT/attachments/$id.age.tmp" "$f" && mv "$OUT/attachments/$id.age.tmp" "$OUT/attachments/$id.age"
      new=$((new + 1))
    fi
  done < <(find "$DATA/Attachments" -type f ! -name '.*' -print0 | sort -z)
fi

# 4. The rest as one locked file, rewritten only when its contents changed (so git keeps few versions).
sum=$(cd "$WORK/grimoire" && find . -type f -print0 | sort -z | xargs -0 cat | hash | cut -c1-64)
if [[ "$sum" != "$(cat "$STATE/backup-sum" 2>/dev/null)" || ! -f "$OUT/grimoire.tar.age" ]]; then
  tar -C "$WORK" -cf - grimoire | age -r "$RECIPIENT" -o "$OUT/grimoire.tar.age.tmp"
  mv "$OUT/grimoire.tar.age.tmp" "$OUT/grimoire.tar.age"
  echo "$sum" > "$STATE/backup-sum"
  changed="database and settings updated"
else
  changed="database unchanged"
fi
cat > "$OUT/README.md" <<MD
# Grimoire Backup

A locked copy of the Grimoire app's data, written by \`grimoiria-app/App/tools/backup.sh\`.
Every file here is encrypted with [age](https://age-encryption.org); nothing in this folder can be read without
the key Hugh keeps in his password manager (on the Mac: \`~/.config/grimoire/backup-key.txt\`).

- \`grimoire.tar.age\`: the database, Definitions, settings and the open-format export.
- \`attachments/\`: audio and photos, one locked file each.
- Public key (safe to share): \`$RECIPIENT\`

To restore: \`bash ~/grimoiria-app-main/App/tools/restore-backup.sh\` (asks where the key is, writes to the Desktop,
changes nothing in Grimoire).
MD
date +%F > "$STATE/backup-day"
say "Locked backup written to $OUT: $changed, $new new attachment(s)$( (( big )) && echo ", $big too big for GitHub")."
