---
name: grimoire
description: Read and add to Hugh's Grimoire (practice records, divinations, Inbox captures, physical notebook pages) through the running Grimoire Mac app. Use when asked about journal entries, rituals, dreams, omens, tarot or Yi Jing readings, outcomes, or what is on a notebook page.
---

# Grimoire

Grimoire is Hugh's native Mac master record of his magical practice. The
`grimoire` command (linked to `~/.local/bin/grimoire` by `App/build.sh`) talks
to the running app; it opens it in the background if needed, and the window
updates live. Always pass `--json`.

## Safety

- Read commands (`status`, `search`, `show`, `entries list`, `inquiries list`, `inbox list`, `needs-outcome`, `validate`, `parse`, `cast`, `timing`) are safe any time.
- Write commands add records. Only run them when Hugh asked for that record.
- `delete` and `inbox confirm` only report what they would do until `--yes`. Ask Hugh before adding `--yes`. Inbox captures should normally be checked by Hugh in the window (`grimoire open <id>`): nothing is filed until he confirms.
- Testing: set `APP_STORE=/tmp/Grimoire-test.store` so a test copy runs on its own data. Never test on the real store.

## Main commands

```bash
grimoire search "Volume III pp. 40–50" --json      # pages in a notebook
grimoire search "#entity/ally tower" --json        # tags (parents include children) + text and card names
grimoire show <id> --json                          # one record in full, with backlinks
grimoire entries add --type omen --text "Three crows" --tags entity/ally/crow --json
grimoire inquiries add --question "…" --draw "3 cups r, tower, page of wands" --cast 789677 --remind 1w --json
grimoire outcomes add <inquiry-id> --text "…" --fulfilled partly --json
grimoire needs-outcome --json
grimoire export --json                             # Obsidian + grimoire.jsonl, only changed files
```

Ids are ULIDs; any unique part of one works. Run `grimoire help` for the rest,
and `grimoire help <command>` for its options.
