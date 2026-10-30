# House style (DRAFT)

The HT Press house style for Grimoire, as one token file and three options
for Hugh to compare. **Hugh chose A · Codex on 10-29-2026**, and the app now
opens in it. B, C and System stay in Settings for comparison. It stays a DRAFT
until Hugh says ship.

## Files

- `tokens.json` the one source of truth: palette, fonts, type sizes, motion, and the colours of each style in light and dark.
- `../tools/gen-tokens.py` writes `../Sources/GrimoireAppKit/HouseTokens.swift` and `tokens.css` from it. `--check` fails when either is stale.
- `../Sources/Grimoire/UI/HouseStyle.swift` turns the tokens into SwiftUI: `House` (colours), `Typo` (fonts), `Motion`, `.pressPage()`, `PressHeading`.
- `../Resources/Fonts/` Cormorant Garamond and EB Garamond (SIL Open Font License), copied into the app by `build.sh`.
- `mockups.html` proofs of the Inquiry page in A, B and C, drawn from the same tokens.

## The options

| | A · Codex | B · Marginalia | C · Beltane Night |
|---|---|---|---|
| Page | vellum #F8F8F8 / ink #000 | Apple's | Beltane ultramarine #010742 |
| Cards | paper #FFF / soot #141414 | Apple's | #00042C |
| Titles | Cormorant Garamond, tracked caps | Cormorant Garamond | Cormorant Garamond, tracked caps |
| Text | EB Garamond | EB Garamond | EB Garamond |
| Labels | EB Garamond | San Francisco | EB Garamond |
| Accent | rubric red | rubric red | red on dark #FF3232 |
| Corners | 2 pt | Apple's | 2 pt |
| Mode | follows the Mac | follows the Mac | always dark |

Rubric red is the only colour: a test fails if any other hue sneaks in, and
another checks every text colour against WCAG AA on its ground.

## Try one

- In the app: Settings > Appearance > House style.
- From a terminal: `APP_STYLE=a ~/Applications/Grimoire.app/Contents/MacOS/Grimoire`.
- Snapshots: `APP_STYLE=a tools/snap.sh` (and `b`, `c`).

## The default

`HouseStyleStore.defaultID` in `UI/HouseStyle.swift` (now "a"). On ship, drop
the `DRAFT` labels here, in `tokens.json` and in Settings.

Apple's pickers, date fields and toggles keep San Francisco in every style:
they are AppKit controls and do not take a custom font.

## Still to come

- Woodcut marks from Figma "HT Brand" beside the kicker and on empty pages (needs the SVG exports).
- Physis for astrological glyphs (needs the font file).
- Grouped form rows keep Apple's fill; style A could paint them paper and soot once the look is chosen.
