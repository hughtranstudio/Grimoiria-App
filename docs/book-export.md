# Printable books (PDF)

`grimoire book` turns a slice of the grimoire into a typeset PDF. What goes in (a **Book**: dates, types, tags, decks, cards, chapters) is chosen separately from how it looks (a **Design**), so the same month prints as a plain journal or as an old-style book.

## Try it

```bash
brew install typst                      # once; the Mac app will bundle it later
tools/fetch-book-fonts.sh               # once, optional: free fonts the designs use
swift run grimoire book --out ~/Desktop/october --from 2026-10-01 --to 2026-10-31 --title "October Workings"
swift run grimoire book --out ~/Desktop/october-bos --from 2026-10-01 --to 2026-10-31 --design book-of-shadows
```

Each run writes a folder with `book.pdf` beside the Typst project that made it (`main.typ`, `grimoire.typ`, `book.json`, `design.json`). The folder compiles again on its own with `typst compile main.typ`.

| Option | Meaning |
|---|---|
| `--from`, `--to` | Inclusive days, `yyyy-MM-dd`, in each record's own time zone |
| `--type` | `journal`, `ritual`, `meditation`, `vision`, `contact`, `omen`, `insight`, `dream`, `reading`; repeat for several |
| `--tag` | Any of these tags, children included |
| `--deck`, `--card` | Readings that used a deck or drew a card (`maj-16` or `rws-tarot/maj-16`) |
| `--group` | Chapters by `month` (default), `week`, `type`, `tag`, `deck`, `card`, or `none` |
| `--design` | `working-journal` (default), `book-of-shadows`, or a path to your own design folder |
| `--attachments` | The attachments folder, so page photos and images are printed |
| `--transcripts` | Also print raw voice transcripts that differ from the entry text |
| `--fonts DIR` | Extra font folder; `--typst PATH` a specific Typst; `--no-pdf` writes the project only |

## Designs

A design is a folder with a `design.json`. The two bundled ones live in `Sources/GrimoireCore/Resources/Book/Designs/`; copy one, change its `id` and `name`, and pass its folder to `--design`.

| | Working Journal | Book of Shadows |
|---|---|---|
| Look | Clean, modern | Old printed book |
| Page | US Letter, for home printing | A5, chapters open on the right-hand page |
| Type | Source Serif 4, Source Sans 3 labels | EB Garamond text, IM Fell titles, small caps labels |
| Colour | Black and deep blue | Black and oxblood red, ornaments |

`design.json` settings:

- `page`: `size` (`a4`, `a5`, `a6`, `b5`, `us-letter`, `us-trade`, `royal`, `pocket`, or `{ "width": "6in", "height": "9in" }`), `margins` (`inside`, `outside`, `top`, `bottom`), `bleed` (for example `"3mm"`), `cropMarks`, `chaptersOnRecto`.
- `type`: font lists for `body`, `display`, `label`, `symbols` (first installed font wins), `size`, `leading`, `justify`, `indent`, `paragraphSpacing`, `smallCapsLabels`, `initial` (`accent` colours the first letter of each entry, `none`).
- `colour`: `ink`, `accent`, `quiet`, `rule` as hex.
- `ornament`: `chapterMark`, `itemSeparator` (`rule` or any glyph), `titleMark`.
- `content`: `contents`, `timing`, `photos`, `tags`, `cardIndex`, `hexagramIndex` on or off.

A design can also carry `fonts/` (used before system fonts) and its own `grimoire.typ` to replace the shared layout.

## How it fits together

`BookExporter` (GrimoireCore) selects records and resolves everything a page needs (card and hexagram names, spread positions, date labels, timing) into `book.json`. `BookWriter` lays out the project folder, and `TypstRenderer` runs Typst. Readings print once, as the reading, even though confirming a capture also files an entry. Yi Jing casts are drawn as lines with changing lines marked; card spreads as labelled boxes, reversed cards dashed. Card and hexagram indexes link to the page each reading is on.

The Mac app will call the same three pieces from an Export Book command, bundling Typst inside the app so nothing needs installing.
