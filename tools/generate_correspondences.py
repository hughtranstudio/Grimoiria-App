#!/usr/bin/env python3
"""Writes Sources/GrimoireCore/Resources/Definitions/correspondences.json.

Classical tables only: planetary days, metals, rulerships and dignities (Ptolemy, Lilly),
magic-square numbers and planetary incense (Agrippa, Three Books, I.44 and II.22),
Golden Dawn colours (King scale), sephiroth, elemental directions, archangels and tools,
the zodiacal man (melothesia), and the trigram images of the Shuo Gua with the
Later Heaven directions. Tarot attributions are not repeated here: the app reads them
from each deck's `attribution` attribute, so a deck with other attributions shows its own.

Quareia and other systems can be added as further files later; keep each table's source stated.
"""
import json, pathlib

OUT = pathlib.Path(__file__).resolve().parent.parent / "Sources/GrimoireCore/Resources/Definitions/correspondences.json"

SIGNS = ["aries", "taurus", "gemini", "cancer", "leo", "virgo", "libra", "scorpio", "sagittarius", "capricorn", "aquarius", "pisces"]
GLYPH = {"saturn": "♄", "jupiter": "♃", "mars": "♂", "sun": "☉", "venus": "♀", "mercury": "☿", "moon": "☽",
         "aries": "♈︎", "taurus": "♉︎", "gemini": "♊︎", "cancer": "♋︎", "leo": "♌︎", "virgo": "♍︎", "libra": "♎︎",
         "scorpio": "♏︎", "sagittarius": "♐︎", "capricorn": "♑︎", "aquarius": "♒︎", "pisces": "♓︎",
         "fire": "🜂", "water": "🜄", "air": "🜁", "earth": "🜃",
         "qian": "☰", "kun": "☷", "zhen": "☳", "kan": "☵", "gen": "☶", "xun": "☴", "li": "☲", "dui": "☱"}

def t(s): return s[:1].upper() + s[1:]

planets = {
    #          day         metal          GD colour        sephirah     square  nature                         rules                      exalted       detriment                  fall          incense (Agrippa)
    "saturn":  ("Saturday", "Lead",        "Indigo",        "Binah",     3, "Cold and dry",                  ["capricorn", "aquarius"],   "libra",      ["cancer", "leo"],          "aries",      ["Myrrh", "Black poppy seed", "Mandrake root"]),
    "jupiter": ("Thursday", "Tin",         "Violet",        "Chesed",    4, "Warm and moist",                ["sagittarius", "pisces"],   "cancer",     ["gemini", "virgo"],        "capricorn",  ["Storax", "Lignum aloes", "Benzoin"]),
    "mars":    ("Tuesday",  "Iron",        "Scarlet",       "Geburah",   5, "Hot and dry",                   ["aries", "scorpio"],        "capricorn",  ["libra", "taurus"],        "cancer",     ["Sulphur", "Euphorbium", "Bdellium"]),
    "sun":     ("Sunday",   "Gold",        "Orange",        "Tiphareth", 6, "Hot and dry",                   ["leo"],                     "aries",      ["aquarius"],               "libra",      ["Frankincense", "Saffron", "Balsam"]),
    "venus":   ("Friday",   "Copper",      "Emerald green", "Netzach",   7, "Temperate, warm and moist",     ["taurus", "libra"],         "pisces",     ["scorpio", "aries"],       "virgo",      ["Musk", "Red roses", "Ambergris"]),
    "mercury": ("Wednesday","Quicksilver", "Yellow",        "Hod",       8, "Changeable, takes on others",   ["gemini", "virgo"],         "virgo",      ["sagittarius", "pisces"],  "pisces",     ["Mastic", "Cloves", "Cinquefoil"]),
    "moon":    ("Monday",   "Silver",      "Blue",          "Yesod",     9, "Cold and moist",                ["cancer"],                  "taurus",     ["capricorn"],              "scorpio",    ["Camphor", "White poppy seed", "Frankincense"]),
}

sign_data = {
    #               element  modality    ruler      modern     exalted    body (melothesia)
    "aries":       ("fire",  "Cardinal", "mars",    None,      "sun",     "Head and face"),
    "taurus":      ("earth", "Fixed",    "venus",   None,      "moon",    "Neck and throat"),
    "gemini":      ("air",   "Mutable",  "mercury", None,      None,      "Shoulders, arms and hands"),
    "cancer":      ("water", "Cardinal", "moon",    None,      "jupiter", "Chest and breasts"),
    "leo":         ("fire",  "Fixed",    "sun",     None,      None,      "Heart and back"),
    "virgo":       ("earth", "Mutable",  "mercury", None,      "mercury", "Belly and bowels"),
    "libra":       ("air",   "Cardinal", "venus",   None,      "saturn",  "Kidneys and lower back"),
    "scorpio":     ("water", "Fixed",    "mars",    "Pluto",   None,      "Genitals"),
    "sagittarius": ("fire",  "Mutable",  "jupiter", None,      None,      "Hips and thighs"),
    "capricorn":   ("earth", "Cardinal", "saturn",  None,      "mars",    "Knees"),
    "aquarius":    ("air",   "Fixed",    "saturn",  "Uranus",  None,      "Calves and ankles"),
    "pisces":      ("water", "Mutable",  "jupiter", "Neptune", "venus",   "Feet"),
}

elements = {
    #        qualities        humour                     direction archangel  tool        suit         beings       kerub
    "fire":  ("Hot and dry",   "Choleric (yellow bile)",  "South",  "Michael", "Wand",     "wands",     "Salamanders", "Lion"),
    "water": ("Cold and moist","Phlegmatic (phlegm)",     "West",   "Gabriel", "Cup",      "cups",      "Undines",     "Eagle"),
    "air":   ("Hot and moist", "Sanguine (blood)",        "East",   "Raphael", "Dagger",   "swords",    "Sylphs",      "Man"),
    "earth": ("Cold and dry",  "Melancholic (black bile)","North",  "Auriel",  "Pentacle", "pentacles", "Gnomes",      "Bull"),
}

trigrams = {
    #        family             quality (Shuo Gua)          direction    phase    body      animal
    "qian": ("Father",          "Strong, creative",         "Northwest", "Metal", "Head",   "Horse"),
    "kun":  ("Mother",          "Yielding, receptive",      "Southwest", "Earth", "Belly",  "Cow"),
    "zhen": ("Eldest son",      "Arousing, movement",       "East",      "Wood",  "Foot",   "Dragon"),
    "kan":  ("Middle son",      "Dangerous, the abyss",     "North",     "Water", "Ear",    "Pig"),
    "gen":  ("Youngest son",    "Keeping still",            "Northeast", "Earth", "Hand",   "Dog"),
    "xun":  ("Eldest daughter", "Gentle, penetrating",      "Southeast", "Wood",  "Thighs", "Fowl"),
    "li":   ("Middle daughter", "Clinging, light",          "South",     "Fire",  "Eye",    "Pheasant"),
    "dui":  ("Youngest daughter","Joyous",                  "West",      "Metal", "Mouth",  "Sheep"),
}

def f(label, *values): return {"label": label, "values": [v for v in values if v]}

entries = []
for p, (day, metal, colour, seph, square, nature, rules, ex, det, fall, incense) in planets.items():
    entries.append({
        "id": f"planet:{p}", "kind": "planet", "name": t(p), "glyph": GLYPH[p],
        "fields": [f("Day", day), f("Metal", metal), f("Nature", nature), f("Rules", *map(t, rules)), f("Exalted in", t(ex)),
                   f("Detriment in", *map(t, det)), f("Fall in", t(fall)), f("Colour (Golden Dawn)", colour), f("Sephirah", seph),
                   f("Magic square", f"{square} × {square}"), f("Incense (Agrippa)", *incense)],
        "related": [f"sign:{s}" for s in rules] + [f"sign:{ex}"],
    })
for s, (el, mod, ruler, modern, ex, body) in sign_data.items():
    entries.append({
        "id": f"sign:{s}", "kind": "sign", "name": t(s), "glyph": GLYPH[s],
        "fields": [f("Element", t(el)), f("Modality", mod), f("Ruler", t(ruler)), f("Modern ruler", modern),
                   f("Exaltation of", t(ex) if ex else None), f("Body", body),
                   f("Polarity", "Masculine, diurnal" if el in ("fire", "air") else "Feminine, nocturnal")],
        "related": [f"element:{el}", f"planet:{ruler}"] + ([f"planet:{ex}"] if ex else []),
    })
for e, (q, humour, direction, angel, tool, suit, beings, kerub) in elements.items():
    signs = [s for s, d in sign_data.items() if d[0] == e]
    entries.append({
        "id": f"element:{e}", "kind": "element", "name": t(e), "glyph": GLYPH[e],
        "fields": [f("Qualities", q), f("Humour", humour), f("Signs", *map(t, signs)), f("Direction (Golden Dawn)", direction),
                   f("Archangel (Golden Dawn)", angel), f("Tool", tool), f("Tarot suit", t(suit)), f("Elementals", beings), f("Kerub", kerub)],
        "related": [f"sign:{s}" for s in signs],
        "suit": suit,
    })
for g, (family, quality, direction, phase, body, animal) in trigrams.items():
    entries.append({
        "id": f"trigram:{g}", "kind": "trigram", "name": t(g), "glyph": GLYPH[g],
        "fields": [f("Family", family), f("Quality", quality), f("Direction (Later Heaven)", direction), f("Phase", phase),
                   f("Body", body), f("Animal", animal)],
        "related": [],
    })

doc = {
    "id": "classical", "name": "Classical correspondences", "version": 1,
    "source": "Ptolemy and Lilly (dignities), Agrippa (squares, incense), Golden Dawn (colours, sephiroth, directions, archangels), Shuo Gua (trigrams).",
    "entries": entries,
}
OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
print(f"wrote {OUT} ({len(entries)} entries)")
