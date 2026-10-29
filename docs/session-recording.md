# Session recording: rituals, meditations and visions

Status: design + v1 implementation (GrimoireCore and the Mac app). Pixel side is specified here and
built later in the Android capture app.

## What it is for

When Hugh sits down for a ritual, a meditation or a vision (visionary magic), Grimoire records the
whole session: audio with a transcript, the things seen and met inside it as separate timestamped
observations, how it started and ended, and the moon and planetary hour it happened under. Over
years this becomes one consistent table of observations that a local model or a notebook can mine
("which beings show up in Mars hours?", "what imagery comes before a reading that turned out
right?").

Three rules follow from that goal:

1. **One record per observation, with a time.** A crow seen at minute 12 is its own row, not a
   sentence buried in a paragraph.
2. **A stable vocabulary.** The same thing gets the same tag every time (`entity/animal/crow`, not
   `crow` one week and `birds/crows` the next). Free tags are still allowed, and are kept apart.
3. **Nothing is filed unchecked.** Like every capture, a recorded session lands in the Inbox and is
   confirmed (and corrected) before it is filed.

## The session flow

### On the Mac

1. **Start.** File > Record Session… (⌥⌘R). Pick ritual, meditation or vision, optionally write an
   intention and technique, and rate how you feel going in (energy, calm, focus, 1–5). Start begins
   the clock and the microphone.
2. **During.** The window stays small and quiet. You can:
   - just speak: everything is recorded and later split into observations;
   - press **⌘K** to drop a marker ("something happened here") without opening your eyes;
   - type an observation and press Return. Pick its kind with ⌃⌥ and a letter (I imagery,
     E entity, P place, Y symbol, M message, H sound, S sensation, F feeling, T insight, O omen,
     V event, A action, N note). Leave the tags empty and they are suggested from the words;
   - change phase: preparation → opening → working → closing (⌃⌥1…⌃⌥4).
   All of these are in the **Session** menu. End the session with ⌥⌘E.
3. **Stop.** Rate how you feel coming out, add a short outcome and anything else you remember,
   press Send to Inbox. Grimoire transcribes the
   audio on the Mac, splits the transcript into timed observations, suggests tags from the
   vocabulary, and puts the session in the **Inbox**.
4. **Review.** In the Inbox the session shows as a timeline. Fix kinds, text and tags, delete what
   isn't an observation, then Confirm. It is filed as a ritual, meditation or vision entry.
5. **Later.** On the filed entry, observations can be edited or added (marked *recalled*), and an
   observation can be turned into its own Contact or Omen entry, linked back to the session.

Speaking during the session also works for structure: "phase working", "now closing" or
"closing now" set the phase, and "mark" on its own drops a marker.

### On the Pixel

Same idea, phone-sized: a **Session** button in Grimoire Capture records audio, a big tap target
drops markers, and phase buttons sit along the bottom. On Stop the phone writes the audio and the
usual sidecar with a `session` block (below) into the Syncthing folder. The Mac ingests it like any
capture, transcribes it if the phone didn't, and builds the same Inbox session.

```json
{
  "contract_version": 1,
  "id": "20261029-213000-4821",
  "captured_at": "2026-10-29T21:30:00-07:00",
  "kind_hint": "vision",
  "audio": "20261029-213000-4821.wav",
  "session": {
    "type": "vision",
    "started_at": "2026-10-29T21:30:00-07:00",
    "ended_at": "2026-10-29T22:05:40-07:00",
    "intention": "Visit the inner library",
    "marks": [
      { "offset_s": 0, "phase": "opening" },
      { "offset_s": 312.5 },
      { "offset_s": 640, "kind": "entity", "text": "Robed figure at the door", "tags": ["entity/being/guardian"] },
      { "offset_s": 1800, "phase": "closing" }
    ],
    "segments": [
      { "offset": 305.0, "text": "I see a red door in the desert" }
    ],
    "before": { "energy": 3, "calm": 2, "focus": 3 },
    "after": { "energy": 4, "calm": 4, "focus": 4 }
  }
}
```

`segments` (offsets in seconds from the start of the audio) is optional: when the phone has no timed transcript, the Mac transcribes the audio. A
plain transcript with `[mm:ss]` or `[hh:mm:ss]` at the start of lines also counts as timed.

## Schema changes

All additive: older stores and exports still read, and records without a session look exactly as
before.

`Entry.session: PracticeSession?` (on ritual, meditation and vision entries)

| field | type | notes |
|---|---|---|
| `schemaVersion` | Int | 1 |
| `startedAt`, `endedAt` | ZonedDate | wall clock with time zone |
| `phases` | [PhaseMark] | `{phase, offset}`; phases are preparation, opening, working, closing, aftermath |
| `observations` | [Observation] | see below, sorted by offset |
| `recordings` | [SessionRecording] | audio attachment path, start offset, duration, timed transcript segments |
| `before`, `after` | StateCheck? | energy, calm, focus, each 1–5 |
| `outcome` | String? | how it ended, in a sentence |
| `interrupted` | Bool? | stopped early or disturbed |

`Observation`

| field | type | notes |
|---|---|---|
| `id` | ULID | stable, used as the row key in exports |
| `offset` | Double | seconds since `startedAt`; the absolute time is derived |
| `phase` | SessionPhase? | filled from the phase marks when not given |
| `kind` | ObservationKind | imagery, entity, place, symbol, message, sound, sensation, emotion, insight, omen, event, action, note |
| `text` | String | what was seen, heard or felt |
| `tags` | [TagPath] | controlled or free |
| `intensity` | Int? | 1–5, how strong |
| `clarity` | Int? | 1–5, how clear or certain |
| `capture` | live / spoken / recalled / marker | typed in the session, transcribed from audio, written afterwards, or a bare marker |
| `reviewed` | Bool | false for machine-made observations until confirmed |
| `linkedEntryId` | ULID? | a Contact or Omen entry made from this observation |

`capture` and `reviewed` matter for analysis: recalled observations are written with hindsight, and
unreviewed ones came from the speech-to-text and keyword guesses.

## Tag system

Tags stay hierarchical paths (`entity/animal/crow`), as everywhere else in Grimoire. Selecting a
parent finds its children.

**Controlled vocabulary.** GrimoireCore ships a starter vocabulary arranged in facets:

| facet | examples |
|---|---|
| `entity/` | `entity/animal/crow`, `entity/being/guardian`, `entity/being/inner-contact`, `entity/dead`, `entity/deity` |
| `place/` | `place/desert`, `place/temple`, `place/inner-library`, `place/abyss`, `place/underworld` |
| `symbol/` | `symbol/door`, `symbol/key`, `symbol/sword`, `symbol/flame`, `symbol/serpent` |
| `color/` | `color/red`, `color/gold`, `color/black` |
| `element/`, `direction/` | `element/fire`, `direction/east` |
| `sense/` | `sense/heat`, `sense/pressure`, `sense/tingling`, `sense/sound`, `sense/scent` |
| `emotion/` | `emotion/awe`, `emotion/fear`, `emotion/peace` |
| `state/` | `state/trance/deep`, `state/drift`, `state/sleep` |
| `technique/` | `technique/stillness`, `technique/inner-flame`, `technique/pathworking`, `technique/banishing` |
| `planet/`, `sign/` | the seven planets and twelve signs |
| `theme/` | `theme/threshold`, `theme/death`, `theme/warning`, `theme/teaching` |

Each term has aliases ("raven" also suggests `entity/animal/raven`; "angelic" maps to
`entity/being/angel`). The vocabulary is used three ways:

- **Suggest:** words in an observation suggest tags ("a red door" → `color/red`, `symbol/door`).
  Suggestions are shown in review, never filed silently.
- **Normalize:** an alias typed as a tag is rewritten to its canonical path.
- **Classify:** every tag is either *controlled* (in the vocabulary) or *free*. Free tags are fine;
  exports keep them in their own column, and Settings shows the most-used free tags so they can be
  promoted into the vocabulary once they prove themselves.

The vocabulary lives in a JSON file (`tag-vocabulary.json` in the app's data folder) so it can grow
without an app update. Terms are only ever added or aliased, never renamed, so old exports stay
comparable. **Settings > Tags** lists the free tags in use, most used first, with an Add to
Vocabulary button, and opens the file for bigger edits.

## Exports for analysis

Beside the existing `grimoire.jsonl` and `ML/` files, the export writes:

- `ML/sessions.jsonl` and `ML/sessions.csv`: one row per session with type, start, duration,
  phase lengths, state before and after, observation counts by kind, tags and astro timing.
- `ML/observations.jsonl` and `ML/observations.csv`: one row per observation with its session's
  context copied in (type, moon phase, planetary hour…), kind, text, capture, tags split into
  controlled and free, and one column per facet (`entity`, `place`, `symbol`, `color`, …).
- `ML/tag-vocabulary.json`: the vocabulary the tags were checked against.

The Markdown vault gets a **Session log** table on each session entry (time, phase, kind,
observation, tags) and `session:` frontmatter, so Obsidian Dataview can query it too.

How to analyze these files is in [analyzing-sessions.md](analyzing-sessions.md).

## Not in v1

- The Pixel session screen (contract above is ready for it).
- Live on-screen transcription during the session (the transcript is made after Stop).
- Biometrics (heart rate from a watch); `StateCheck` is the place for it later.
- Uranika chart snapshots per session beyond the stored moon and planetary hour; see the Uranika
  integration plan.
