# Phone library: the Mac → phone half of the sync folder

The Pixel app was capture-only: files went one way, phone → Mac, through `incoming/`. To make the
phone a grimoire you can read from, the Mac now also writes into the same Syncthing folder. The
folder stays the only link between the two; the phone still has no internet permission.

```
GrimoireInbox/                (Syncthing, phone <-> Mac)
  incoming/                   phone -> Mac: captures, sessions, outcomes (sidecar contract v1)
  processed/  failed/         Mac only
  library/                    Mac -> phone, read-only on the phone
    grimoire.jsonl            filed entries, inquiries, volumes, reminders (export-record v1)
    tag-vocabulary.json       the controlled tag vocabulary (for tag pickers)
    manifest.json             written last; the phone reloads when its checksum changes
```

## What the Mac writes

`PhoneLibrary` (GrimoireCore/Export/PhoneLibrary.swift) writes the same `grimoire.jsonl` lines as
the JSONL export, so there is one record format, documented in
`schemas/export-record.v1.schema.json`. Only filed records go; the Inbox stays on the Mac. Audio,
photos and other attachments stay on the Mac too (the phone sees that an entry has them).

The Mac app rewrites `library/` a few seconds after any change, and at launch, into every ingest
folder that is **not** in iCloud Drive (Settings > Inbox > "Share a read-only library with the
phone", on by default). Files are only rewritten when their bytes change, so Syncthing stays quiet.

`manifest.json`:

```json
{ "library_version": 1, "exported_at": "2026-10-29T21:30:00-07:00",
  "entries": 412, "inquiries": 230, "reminders": 61, "checksum": "183220-9f0c…" }
```

## What the phone sends back

Everything the phone makes still goes through `incoming/` and the Mac's Inbox confirm step.

- **Captures and readings**: unchanged (sidecar v1 with `transcript` and `draft`).
- **Sessions**: sidecar with a `session` block (docs/session-recording.md).
- **Outcomes** (new, additive): `kind_hint: "outcome"`, the reading's `inquiry_id`, the outcome in
  `text` (or `audio`/`transcript`), and how it turned out:

  ```json
  { "contract_version": 1, "id": "20261110-090000-1234", "captured_at": "2026-11-10T09:00:00-08:00",
    "kind_hint": "outcome", "inquiry_id": "01JBQ8Y5X0AAAAAAAAAAAAAAAA",
    "text": "Moved in on the 9th.", "outcome": { "fulfilled": "yes" } }
  ```

  The Mac puts it in the Inbox (never parsed as a reading). Confirm stacks it on the reading as a
  new Outcome, completes the check-in it answers, and files nothing else. `fulfilled` is one of
  `yes`, `partly`, `no`, `unclear`.

## Interop rules

- The phone never edits `library/`; it is replaced by the Mac. Phone-side state (outcomes sent but
  not yet confirmed, reminders already notified) is kept in the phone's own storage.
- Both readers ignore unknown keys, so either side can add fields without breaking the other.
- `android/core` decodes `Tests/GrimoireCoreTests/Fixtures/phone-library/grimoire.jsonl`, which the
  Swift tests write from a sample grimoire, so a format change fails one side's tests.
