# Analyzing sessions and observations

Grimoire writes its analysis files into the `ML/` folder of the export (Mac: File > Export to
Obsidian with "ML files" on in Settings > Export; CLI: `grimoire export --out DIR`). Everything stays
on your Mac: these files are for notebooks and models you run locally.

| file | one row per | use it for |
|---|---|---|
| `ML/observations.csv` / `.jsonl` | observation inside a session | what was seen, met and felt, when, under which sky |
| `ML/sessions.csv` / `.jsonl` | recorded ritual, meditation or vision | how sessions went: length, phases, ratings, counts |
| `ML/draws.jsonl` | card drawn or hexagram cast | divination patterns (already there before sessions) |
| `ML/corpus.jsonl` | passage of written text | local embeddings and search |
| `ML/tag-vocabulary.json` | controlled tag | which tags were "official" at export time |
| `ML/manifest.json` | file | row counts and the `session_schema_version` |

The CSV and JSONL versions hold the same rows. In CSV, lists (tags) are joined with `;`; in JSONL
they are arrays.

## Columns worth knowing

**observations**

- `observation_id`, `session_id`: stable ids. `session_id` joins to `sessions.csv`.
- `observed_at` (wall clock with offset), `offset_s` and `minute` (time into the session), `phase`
  (preparation, opening, working, closing, aftermath).
- `kind`: imagery, entity, place, symbol, message, sound, sensation, emotion, insight, omen, event,
  action, note.
- `capture`: `live` (typed during), `spoken` (from the recording), `recalled` (written after),
  `marker` (a bare "something happened"). `reviewed` is false only for speech-made rows that were
  never confirmed (normally none once filed).
- `tags`, `tags_controlled`, `tags_free`, and one column per facet: `entity`, `place`, `symbol`,
  `color`, `element`, `direction`, `sense`, `emotion`, `state`, `technique`, `planet`, `sign`,
  `theme`.
- The session's context copied onto every row: `session_type`, `session_tags`, `intention`,
  `technique`, `moon_phase`, `moon_illumination`, `moon_sign`, `sun_sign`, `planetary_day`,
  `planetary_hour`, `planetary_hour_number`, `near_cusp`, `inquiry_id`.

**sessions**

- `duration_s`, and seconds per phase (`opening_s`, `working_s`, …).
- `before_*` and `after_*` ratings (energy, calm, focus, 1–5).
- `observations`, counts by capture, and `n_<kind>` per kind.
- `observed_tags` and `observed_tags_free`, plus the same timing columns.

Columns are only ever added at the end, and `session_schema_version` in the manifest goes up when
they are, so a notebook written today keeps working.

## Getting started in Python

```python
import pandas as pd

obs = pd.read_json("ML/observations.jsonl", lines=True)
ses = pd.read_json("ML/sessions.jsonl", lines=True)

# Use what you saw in the session, not hindsight, for timing questions.
live = obs[obs.capture.isin(["live", "spoken"])]

# Which beings come up most, and in which kind of session?
beings = live.explode("entity").dropna(subset=["entity"])
beings.groupby(["entity", "session_type"]).size().unstack(fill_value=0)

# Beings by planetary hour, as a share of all observations in that hour.
by_hour = beings.groupby(["planetary_hour", "entity"]).size() / live.groupby("planetary_hour").size()
by_hour.unstack(fill_value=0).round(2)

# When in a session does imagery arrive? Minutes into the working phase.
working = live[live.phase == "working"]
working[working.kind == "imagery"].minute.describe()

# Which tags travel together within one session?
from itertools import combinations
from collections import Counter
pairs = Counter()
for _, g in live.explode("tags_controlled").dropna(subset=["tags_controlled"]).groupby("session_id"):
    pairs.update(combinations(sorted(set(g.tags_controlled)), 2))
pairs.most_common(20)

# Did the practice change how you felt?
ses["calm_change"] = ses.after_calm - ses.before_calm
ses.groupby("technique").calm_change.agg(["mean", "count"])
```

Joining sessions to readings: a session filed with a reading has `inquiry_id`; `draws.jsonl` rows
carry the same `inquiry_id` and the reading's outcome (`fulfilled`, `days_to_first_outcome`).

## Free text with a local model

`text` in observations and `corpus.jsonl` can be embedded with a model that runs on the Mac (for
example `sentence-transformers` or an Ollama embedding model) and clustered to find recurring
images that were described in different words. Cluster labels that keep coming back are good
candidates for new vocabulary terms (Settings > Tags > Add to Vocabulary).

## Cautions

- **Small numbers.** Ten sessions in Mars hours is not a pattern. Look at counts before shares, and
  expect some striking-looking pairs by chance when you test many tags at once.
- **Recalled rows** are written with hindsight; keep them out of timing questions, or compare them
  separately.
- **Speech rows** (`capture = spoken`) came through speech to text and keyword guesses, then your
  review. Their kinds are less certain than typed ones.
- **Free tags** are not counted in the facet columns. Promote the ones you use often.
- **Moon sign and planetary hour** come from Grimoire's built-in ephemeris (good to about a degree;
  `near_cusp` marks rows within half a degree of a sign change). Planetary hours need your home
  location in Settings.
