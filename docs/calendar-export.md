# Calendar export (.ics)

Grimoire can write an iCalendar file that Google Calendar, Apple Calendar or any other calendar imports.
It is the first step toward Google Calendar integration; the research behind it is in the project's
"Google Calendar integration: repo research" doc.

## What goes in the file

| Event | When | Title |
| --- | --- | --- |
| Planned ritual | Ritual entries dated in the window, for `durationMin` (60 minutes if unset) | `Ritual`, plus ` · hour of Venus` when the entry's timing has a planetary hour |
| Outcome check-in | All day on each open reminder's due day | `Outcome check-in (7 days)` |
| Lunar phase | The moment of each new, first quarter, full and last quarter Moon | `Full Moon in Gemini` |
| Sign change (`--sky all`) | Moon and Sun ingresses | `Moon enters Leo` |
| Planetary hour (`--hours`) | Each hour of the chosen planets, optionally only on their own day | `Hour of Venus` |

Only timing crosses. Questions, bodies, intentions, cards and titles stay in Grimoire. Each ritual and
check-in carries a `grimoire://entry/<id>` or `grimoire://inquiry/<id>` link instead. Sky events, hours
and check-ins are marked free (`TRANSP:TRANSPARENT`); rituals are marked busy.

UIDs are stable (`ritual-<id>@grimoire`, `checkin-<id>@grimoire`, `sky-full-moon-2026-11-24@grimoire`),
so a calendar can recognise events it already has when a newer file is imported.

## CLI

```
grimoire calendar-export --out ~/Desktop/Grimoire.ics                    # next 90 days, lunar phases
grimoire calendar-export --out g.ics --from 2026-11-01 --days 30 --sky all
grimoire calendar-export --out g.ics --hours venus,jupiter --its-day       # needs --lat/--lon or $GRIMOIRE_HOME
grimoire calendar-export --out g.ics --sky none --no-checkins              # rituals only
```

## Mac app

File > Export Calendar (.ics)… (Option-Command-E) saves the next 90 days: rituals, check-ins and lunar phases.

## Importing into Google Calendar

1. In Google Calendar on the web, create a calendar named Grimoire (Settings > Add calendar > Create new calendar), so these events stay separate and can be hidden or deleted together.
2. Settings > Import & export > Import, pick the `.ics` file and the Grimoire calendar.

Google does not re-read an imported file, so import again after planning new rituals. A live link
through the Mac's calendar (EventKit) is the next step.
