# Quareia deck

`Sources/GrimoireCore/Resources/Definitions/decks/quareia.json` and the four `spreads/quareia-*.json` files come from the deckbook *LXXXI—Quareia The Magician's Deck: A Guide to the Card Meanings* by Josephine McCarthy (second edition, 2017). They are curated by hand; `tools/generate_definitions.py` does not write them.

## Cards (81)

Each card has:

| Field | Meaning |
|---|---|
| `order` | Position in the book, 1–81. The cards carry no printed number, so this is only the book's order. |
| `number`, `rootPower` | The ten root powers only: Star Father I, Creator of Time II, Holder of Light III, Light Bearer IV, Imprisoner V, Pure Balance VI, Grindstone VII, Unraveller VIII, Threshold Guardian IX, Mother Earth X. |
| `realm` | `divine`, `inner`, `physical` or `underworld`, from the chapter the card is in (the book's four realms / border colours). |
| `chapter`, `group` | The book chapter (I–IX) and its title, e.g. `IV` / `Physical Structures and Natural Features`. |
| `element`, `direction` | The four elemental tools only (Limiter air/east, Staff of the Gods fire/south, Regenerator water/west, Foundation earth/north). |
| `gender` | The book's "Male Powers and Qualities" and "Female Powers and Qualities" cards. The book asks for fluidity here. |
| `page` | Deckbook page. |
| `significations.mundane` | The book's "Mundane Divination" paragraph, verbatim. |
| `significations.magical` | A condensed summary of the book's main card text (magical reading), not the book's words. |

Names drop a leading "The" (the voice parser ignores it anyway). Aliases cover the book's other names and short forms, e.g. Keeper of Time, Weaver, Waterfall, White Horse, Sword, Staff/Wand, Vessel, Fool.

## Spreads

| Spread | Positions |
|---|---|
| `quareia-mystical-map` | Foundation/Mystical Map, 16 positions (I Mother Earth … XVI Path of Hercules) |
| `quareia-landscape` | Landscape, 12 positions, the abridged Mystical Map |
| `quareia-tree-of-life` | Tree of Life, 10 positions; each label gives the deeper root-power reading and the simpler one (from the book's diagram) |
| `quareia-four-directions` | Four Directions, 6 positions (centre, east, south, west, north, union) |

Spread aliases avoid card names, because the parser checks for a spread name before the first card ("foundation" alone is the card, "mystical map" is the spread).

## Gaps and ambiguities in the book

- **No reversed meanings.** The book never discusses reversals. `reversalsAllowed` stays `true` so a reversed draw can be recorded, but there is no reversed signification.
- **Two-realm cards.** The book says cards that belong to two realms have two-coloured borders but does not list them. Only the Abyss is called out (listed in the Inner Realm, black Underworld border). `realm` follows the chapter.
- **Naming.** Card II is "The Creator of Time" in its own heading but "Keeper of Time" in the Tree of Life key words (kept as an alias). The Holder of Light text calls its opposite the "Keeper of Time". The Magical Temple position mentions a "Threshold Keeper", presumably the Threshold Guardian (alias added).
- **Landscape position VI** is labelled Wheel of Fate but the text says the position "is the Weaver of Fate"; the label keeps Wheel of Fate.
- **Not captured:** the book's separate health-reading notes inside each card's main text, the layout reading rules (which positions are read together), and the card images.
