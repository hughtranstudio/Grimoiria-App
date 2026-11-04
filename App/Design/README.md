# House style (DRAFT)

Grimoire wears the HT Press house style, **A · Codex**, built on the Brand Codex
(Hugh's Master Brand Style, my-website `brand/seed.json`). Hugh chose A on
10-29-2026; on 11-04-2026 it moved onto the Codex: white paper by day, forest
night after dark, where every red turns green. Settings keeps one other choice,
System (Apple's look with your accent). Options B Marginalia and C Beltane Night
were retired on 11-04-2026; they live in git history (before PR "Retire styles B
and C"), and a Mac that had one selected opens in A. The DRAFT labels go when Hugh says ship.

## Files

- `codex/tokens.json` the pinned Brand Codex (see `codex/README.md`). Never edit it.
- `tokens.json` the app map: which Codex role fills each app colour, plus fonts, type sizes and motion.
- `../tools/gen-tokens.py` writes `../Sources/GrimoireAppKit/HouseTokens.swift`, `tokens.css` and the Pixel's `CodexTokens.kt` and `codex_colors.xml`. `--check` fails when any is stale or a text colour reads under 4.5:1.
- `../Sources/Grimoire/UI/HouseStyle.swift` turns the tokens into SwiftUI: `House` (colours), `Typo` (fonts), `Motion`, `.pressPage()`, `PressHeading`.
- `../Resources/Fonts/` Cormorant Garamond and EB Garamond (SIL Open Font License), copied into the app by `build.sh`.
- `mockups.html` the October proofs of A, B and C, kept as history.

## A · Codex

| | Day | Night |
|---|---|---|
| Page | paper #FFFFFF | forest night #05120A |
| Cards | surface #F8F8F8 | #0B1C13 |
| Text | ink #000000 | night ink #EBE8DB |
| Quiet text | #6B6B6B | #A0B0A3 |
| Marks | rubric red #EB0303 | green #489E64 |
| Red text | #CC0000 | green #56A66F |
| Titles | Cormorant Garamond, tracked caps | same |
| Text and labels | EB Garamond | same |
| Corners | 2 pt | same |

Two tests guard it: every colour is a grey, rubric red or a Codex night colour,
and every text colour passes WCAG AA on its ground.

## Try it

- In the app: Settings > Appearance > House style.
- From a terminal: `APP_STYLE=system ~/Applications/Grimoire.app/Contents/MacOS/Grimoire` for Apple's look.
- Snapshots: `APP_STYLE=a tools/snap.sh` (and `system`).

Apple's pickers, date fields and toggles keep San Francisco in every style:
they are AppKit controls and do not take a custom font.

## Still to come

- Woodcut marks from Figma "HT Brand" beside the kicker and on empty pages (needs the SVG exports).
- Physis for astrological glyphs (needs the font file).
- Grouped form rows keep Apple's fill; style A could paint them surface by day and forest surface at night.
