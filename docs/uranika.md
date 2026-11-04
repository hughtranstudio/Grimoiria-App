# Uranika charts in Grimoire

Say "Hey so I just launched a website" into Grimoire Capture, and the Inbox gets a **life event** titled "Launched a website", with tags, your place, and the chart of that moment from Uranika: where every planet, the Node and the eight transneptunians stood, the Ascendant and Meridian, and which transits and solar arcs were on your natal points and midpoints.

Uranika runs on the same Mac (`http://127.0.0.1:8765`), so nothing leaves the computer.

## How it works

1. The capture arrives in the Inbox folder as usual.
2. If the note starts like an event ("I just …", "we've just …", "I finally …", "big news …"), or the phone marked it as an event, it becomes a **life event** with a title from the sentence. Tags you already use are suggested when the note mentions them ("website" → `projects/website`). Captures marked as a draw, an omen and so on keep their type.
3. Grimoire asks Uranika for the chart of the moment at your place, and for your natal chart directed to that moment. Hits use Uranika's own rule and defaults: 90° dial (45° family), 1° orb, Q2 rate, tightest 20 transits and 20 solar arcs. The arithmetic is a port of Uranika's `astro.js` and gives the same hits.
4. In the Inbox you confirm or fix the type, title and tags as usual. The chart is stored on the entry and written to the Obsidian export under `astro:`.
5. If Uranika is closed, the entry is marked **chart pending**. `grimoire uranika fill` (or the Mac app, on a timer) fills it in once Uranika is open.
6. Optionally, a filed life event is also added to your chart's case file in Uranika (Library ▸ life events), so Uranika's Research tests can use it.

## Settings (`uranika-settings.json`)

| Setting | Default | Meaning |
|---|---|---|
| `natalChartId` | none | Your chart's id in Uranika. Find it with `grimoire uranika check`. Without it only the sky of the moment is stored. |
| `home` | none | The fixed place charts are cast for: `{"name": "Home", "latitude": …, "longitude": …}`. |
| `useCapturedLocation` | false | Use the phone's position instead of `home` when the capture has one. If no home is set, the phone's position is used anyway. |
| `coordinateDecimals` | 2 | Coordinates are rounded on arrival. 2 decimals is about 1 km, which moves the chart's angles by a few arc-seconds. |
| `scope` | `all` | `all` gives every captured entry a chart; `events` only life events. |
| `hits` | 45, 1, `q2`, 20 | Modulus, orb, progression rate, hits kept per method. |
| `recordEventsInUranika` | false | Add filed life events to your chart in Uranika. |
| `eventCategory` | `other` | Uranika's event category for those. |
| `baseURL` | `http://127.0.0.1:8765` | Where Uranika's server listens. |

Client charts: Grimoire only ever reads your own chart's birth data from Uranika (to direct it); it stores the chart's name and id, never birth data.

## Privacy

- Everything stays local: phone to Mac over Syncthing, then Uranika on the same Mac. No place lookup online.
- Coordinates are rounded on arrival, and named places ("Home") can stand in for them.
- `grimoire export --no-coordinates` (or the app's export setting) keeps place names but leaves coordinates out of the vault.

## CLI

```bash
grimoire uranika check                                  # is Uranika open? which charts, which is yours
grimoire uranika chart 2026-10-29T00:45:00-07:00        # the chart Grimoire would store
grimoire ingest ~/GrimoireInbox --uranika               # ingest with charts
grimoire uranika fill                                   # complete "chart pending" entries
grimoire uranika record <entry id>                      # add a filed life event to your chart in Uranika
```

## In the Mac app

**Settings ▸ Uranika** switches it on (off by default), checks that Uranika is open, and picks your chart from Uranika's library. It writes `uranika-settings.json` beside the app's store (`~/Library/Application Support/Grimoire/`), the same format the CLI reads, so `GRIMOIRE_URANIKA=~/Library/Application\ Support/Grimoire/uranika-settings.json grimoire uranika check` sees the same settings.

- Captures arriving in the Inbox get the chart of their moment (`InboxIngestor.astrologer`), cast for the home place in Settings ▸ General unless the phone's position is allowed.
- "Chart pending" entries and Inbox items fill in at launch and every 10 minutes once Uranika is open, or at once with **Fill Pending Charts Now**.
- With **Add life events to your chart in Uranika** on, confirming a life event adds it to your chart's case file, once.
- An entry's page shows a **Sky** row: what was measured and the three tightest hits.
