# Grimoire

A native Mac master record of a magical practice: journals, rituals, meditations, visions, contacts, omens, dreams and divination, with compound readings under one question, outcomes recorded later, physical notebooks indexed by page, voice captures from the phone, and an open Obsidian export. Full product spec: `grimoire-v1-spec-brief.md` (rev 2). The domain core is already written and tested as the `GrimoireCore` Swift package in this repository; the app is a SwiftUI shell over it.

To build: put this repository in the app folder, then tell the agent:

```text
Build the app in docs/bama-spec.md with BAMA. GrimoireCore is a local package in this repo; depend on it, don't rewrite it.
```

## Brief

```markdown
# Grimoire

A local-first Mac app that is the master grimoire for one practitioner: every practice record, every divination, and where it sits in the physical notebooks.

## Replaces
Scattered Google Docs, paper notebooks with no index, one-off tarot apps.

## Main jobs
1. Log any practice record fast (quick panel, ~20 s) or fully (reflective editor), with hierarchical tags, typed links and a physical page reference.
2. Run compound divinations under one Inquiry (several decks and a Yi Jing cast), write a synthesis, and add dated outcomes later when a reminder comes due.
3. Triage phone voice captures in an Inbox: transcript and audio beside parsed draws, every field correctable, nothing filed until Confirm.
4. Find anything: full text, tags (parent includes children), type, date, "Volume III pages 40–50", card names.
5. Export everything to an Obsidian vault (Markdown + YAML) and grimoire.jsonl, re-runnable and byte-stable.

## Data
- Entry, Inquiry, Divination, Draw, YiJingCast, Synthesis, Outcome, Reminder, Volume, PhysicalRef, CorrectionLogEntry: SwiftData, shaped like the GrimoireCore structs.
- Decks, spreads, Yi Jing: JSON in ~/Library/Application Support/Grimoire/Definitions (copied from the package bundle on first launch).
- Attachments (audio, photos): files in ~/Library/Application Support/Grimoire/Attachments, referenced by relative path.
- Settings (home location, vault path, ingest folders, Whisper model, reminder default): UserDefaults.

## Shape
Single-window app with a sidebar, plus a floating quick-log panel, macOS 26 or later.
Local data. Works offline. No accounts, no telemetry, no network calls.

## System hooks
Global hotkey, floating panel, FSEvents folder watching (several folders), iCloud Drive placeholder download, local notifications, on-device speech-to-text (WhisperKit), obsidian:// URLs, agent CLI + MCP server.

## Reference
Day One (entry speed and timeline), Obsidian (links and backlinks).

## Look
Native, system accent colour. Calm, text-first. Cards shown by name with suit/element glyphs; hexagrams drawn as six lines with changing lines marked.

## Not in version one
- Analytics dashboards, transits, Uranian midpoints
- Phone app beyond capture (the iPhone Shortcut and the Android capture app in `android/` are capture-only)
- Two-way Obsidian sync
- ML, embeddings
- Video, in-app drawing
```

## How it works

| Part | API | Permission |
| --- | --- | --- |
| Domain logic | `GrimoireCore` (local Swift package, this repo) | None |
| Storage | SwiftData `@Model` types behind a `SwiftDataRepository: GrimoireRepository` | None |
| Quick log panel | Global hotkey (Carbon `RegisterEventHotKey`) + `NSPanel` (non-activating, floating) | None |
| Ingest folders | FSEvents (`FSEventStreamCreate`) on each `incoming/`, plus a 30 s timer, both call `InboxIngestor.scan` | Folder access via security-scoped bookmark from an open panel |
| iCloud placeholders | `FileManager.startDownloadingUbiquitousItem` (already in `LocalFileSystem.requestDownload`) | None |
| Transcription | WhisperKit (Core ML, on device) behind `Transcriber` | None (no microphone; files only) |
| Reminders | `UNUserNotificationCenter` local notifications | Notifications, asked once |
| Obsidian | Write export folder; open notes with `obsidian://open?file=` (`Link.obsidianURL`) | Folder bookmark |
| Agent access | BAMA `agent-cli`: wrap the existing `grimoire` CLI commands and expose them over MCP | None |

### Using GrimoireCore

Add the package as a local dependency of the app target. What the app gets, already tested (85 tests):

- `DefinitionLibrary.bundled()` / `.load(from:)` / `.validate()` for decks, spreads, Yi Jing. Copy the bundled `Definitions` folder to Application Support on first launch, then always load from there so the deck editor can write files.
- Models as `Codable` value types: `Entry` (+ `TypeFields`), `Inquiry`, `Divination`, `Draw`, `YiJingCast`, `Synthesis`, `Outcome`, `Reminder`, `Volume`, `PhysicalRef`, `TagPath`, `TagTree`, `Link`, `ZonedDate`, `ULID`.
- `ReadingParser.parse(_:)` for transcripts and `parseQuickDraw(_:deckId:spreadId:)` for the quick panel. Output is a `DraftReading` with `Parsed<T>` fields carrying `heard` text and a `Confidence` (high / medium / low / missing).
- `InboxIngestor` (folder rules) and `Confirmation.confirm` / `GrimoireRepository.confirm` (the only path from draft to filed records; logs corrections).
- `TimingContext.compute(at:location:timeKnown:)` for moon phase/sign, Sun sign, planetary day, hour and hour number (1–24 from sunrise); the location used is stored on the context. `GrimoireRepository.fillTiming(location:overwrite:)` fills records saved without it.
- `OutcomeCheckIn.reminder(for:askedOn:today:preset:)`: the 7/30/90-day ladder, one `Reminder` per Inquiry that rolls forward on `complete()`; filed late, it starts at the latest step already past, due today.
- `GrimoireRepository.search`, `needsOutcome(today:)`, `scheduleOutcomeCheckIn`, `addOutcome(_:to:)`, `stopReminders(for:)`, `backfillOutcomeCheckIns(today:)`, `backlinks(to:)`, `tagTree`, `knowsCapture`.
- `ObsidianExporter.files(for:)`, `JSONLExporter.export(_:)`, `ExportWriter.write(_:to:)`.

Main app types to write:

- `@Model` classes `EntryRecord`, `InquiryRecord`, `DivinationRecord`, `DrawRecord`, `VolumeRecord`, `ReminderRecord`, `InboxRecord`, `CorrectionRecord`, each with `init(_ value:)` and `var value` converting to and from the GrimoireCore struct. Store `TypeFields`, `TimingContext`, `[Link]`, `DraftReading` as `Codable` attributes. Index `id`, `occurredAt`, `captureId`, `status`.
- `SwiftDataRepository: GrimoireRepository`. `data` builds a `GrimoireData` snapshot (fine at personal scale; add targeted fetches later if search gets slow).
- `IngestCoordinator`: one `InboxIngestor` per ingest folder, an FSEvents stream per folder, a serial actor so scans never overlap.
- `WhisperTranscriber: Transcriber` (WhisperKit, model chosen in Settings, runs off the main actor).
- `ReminderScheduler`: schedules a notification for each pending `Reminder` at 09:00 local on `dueOn`, body `reminder.prompt`; actions Snooze 3 days / Add outcome / No more nudges (`stopReminders`). Reschedule a reminder whenever it is saved, since a ladder moves its `dueOn`.
- `QuickLogPanel`, `InquiryView`, `InboxView`, `TimelineView`, `TodayView`, `VolumesView`, `DecksView`, `SearchView`, `SettingsView`.

Behaviors that matter:

- **Confirm is mandatory.** Ingested items are `InboxRecord`s with `entry.status == .inbox`. Nothing in Timeline, Search or Export reads them. Only the Inbox's Confirm button calls `repository.confirm(...)`.
- **Inbox screen.** Left: transcript with an audio player. Right: the draft: question, each divination with deck and spread pickers, each draw as a card picker + orientation toggle + position. Anything with confidence below `.high` gets an accent outline; `missing` cards show an empty picker. `draft.unparsed` words appear as chips under the transcript, `draft.warnings` as a banner. Confirm is disabled while any card or Yi Jing line set is missing; `ConfirmError` text is shown inline.
- **Quick log.** Hotkey opens the panel anywhere. One keystroke picks the type: J journal, O omen, I insight, D dream, C card draw, Y Yi Jing, V vision. In C mode, deck and spread pickers, then one text field fed to `parseQuickDraw` live as the user types; Enter saves. In Y mode, six digits fed to `YiJingCast(quick:)`, hexagrams shown instantly. Saves `mode: .quick`.
- **Inquiry screen.** Question, context, every divination laid out by spread (Celtic Cross as the cross + staff, others as a row), Yi Jing as two hexagram drawings with changing lines marked, synthesis editor with confidence 1–5, outcomes in date order with "days after", linked entries and backlinks. Adding an outcome uses `repository.addOutcome(_:to:)` so they stack, status moves open → resolved → revisited, and a due check-in rolls on to the next step.
- **Reminders.** New-Inquiry sheet and Confirm offer presets 7 / 30 / 90 days (default, `.ladder`) / None / 1 week / 1 month / 3 months (`ReminderPreset`). Today shows `needsOutcome(today:)` with the reminder's prompt ("One week on: what has happened since you asked?"). After importing old notes, offer "Add check-ins to past readings" (`backfillOutcomeCheckIns`).
- **Timing.** Compute at save from `occurredAt` and the home location in Settings (per-entry override, stored in `timing.location`). Show moon phase, planetary day and "hour of Mars (3rd of night)" from `planetaryHourNumber`; show `nearCusp` signs with "≈". When the home location is first set, run `fillTiming(location:)`. Transits and Uranian midpoints are out of v1.
- **Ingest folder.** Default `~/Library/Mobile Documents/com~apple~CloudDocs/GrimoireInbox/`; Settings lists several (the Pixel's Syncthing folder, usually `~/GrimoireInbox/`, is the second; see `docs/android-capture.md`). Android captures may carry `transcript` and `draft`; `InboxIngestor` already uses them instead of Whisper and the parser, and the Inbox shows them like any other draft. Set `ingestor.defaultTimeZone` to the Mac's zone and `ingestor.location` to the home location, `attachmentsFolder` to Application Support/Attachments.
- **Export.** Settings holds the vault folder (e.g. `Vault/Grimoire/`). Export runs on demand and after each confirm; `ExportWriter` only touches changed files. Copy attachments into `_attachments/`.
- **Decks.** Read-only list in v1 milestone 1; the deck editor (add/rename cards, attributes, import JSON) writes JSON back to the Definitions folder and must pass `validate()` before saving.
- **Privacy.** No network entitlement. WhisperKit models are bundled or downloaded once by explicit user action in Settings.

## Milestones

Same order as spec §13. Each is done when its checks pass with `build-and-verify` and `test-mac-app`.

1. **App shell + definitions.** New Mac app via `new-mac-app`; depends on GrimoireCore; copies Definitions on first launch; Decks screen lists 4 decks (Quareia and Mystagogos marked placeholder) and 4 spreads. *Check:* `DefinitionLibrary.validate()` passes at launch.
2. **Core records.** SwiftData models + `SwiftDataRepository`; Timeline; reflective editor for all 8 non-divination types with their fields; tags with autocomplete from `tagTree`; links and backlinks. *Check:* create one of each type, relaunch, all present.
3. **Divination.** Inquiry list and screen, card draws, Yi Jing casts, synthesis, outcomes, reminders + notifications + Needs outcome. *Check:* spec §14 compound Inquiry (3-card RWS + Yi Jing; Quareia once its deck exists), 7-day check-in fires, add outcome, 30-day check-in is next.
4. **Quick log.** Hotkey panel, quick draw and quick cast. *Check:* omen with one tag in under 20 s.
5. **Volumes.** Volumes screen, physical refs, page-range search. *Check:* find everything in Volume III pp. 40–50.
6. **Export.** Obsidian + JSONL; vault-note links. *Check:* files open in Obsidian with valid frontmatter; second export writes 0 files.
7. **Ingest.** Folder watching, WhisperKit, Inbox confirm-and-correct; then importers (spec §11.3). *Check:* drop a capture pair, it appears transcribed within a minute; drop it again, no duplicate; the spoken RWS example shows 3 draft draws and nothing is filed until Confirm.
8. **Agent CLI.** `agent-cli` skill around the existing `grimoire` commands, pointed at the app's store.

## Open questions carried from the spec

Phone capture-only vs browse; relation to the Uranika/Obsidian hub; where the Quareia, Mystagogos and significations repos live.
