#!/usr/bin/env python3
"""Generates the preloaded definition files under
Sources/GrimoireCore/Resources/Definitions/.

Card lists here are structural only. Significations (meanings, keywords) are
meant to be merged in from Hugh's deck repositories later; every card carries
an empty `significations` object as the slot for that.

Run: python3 tools/generate_definitions.py
"""
import json
import os

ROOT = os.path.join(os.path.dirname(__file__), "..", "Sources", "GrimoireCore", "Resources", "Definitions")

NUMBER_WORDS = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]


def write(path, data):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


# ---------------------------------------------------------------- RWS tarot

MAJORS = [
    ("The Fool", "air", ["fool"]),
    ("The Magician", "mercury", ["magician", "magus"]),
    ("The High Priestess", "moon", ["high priestess", "priestess"]),
    ("The Empress", "venus", ["empress"]),
    ("The Emperor", "aries", ["emperor"]),
    ("The Hierophant", "taurus", ["hierophant", "high priest", "pope"]),
    ("The Lovers", "gemini", ["lovers", "lover"]),
    ("The Chariot", "cancer", ["chariot"]),
    ("Strength", "leo", ["strength"]),
    ("The Hermit", "virgo", ["hermit"]),
    ("Wheel of Fortune", "jupiter", ["wheel of fortune", "wheel"]),
    ("Justice", "libra", ["justice"]),
    ("The Hanged Man", "water", ["hanged man", "hanging man"]),
    ("Death", "scorpio", ["death"]),
    ("Temperance", "sagittarius", ["temperance"]),
    ("The Devil", "capricorn", ["devil"]),
    ("The Tower", "mars", ["tower"]),
    ("The Star", "aquarius", ["star"]),
    ("The Moon", "pisces", ["moon"]),
    ("The Sun", "sun", ["sun"]),
    ("Judgement", "fire", ["judgement", "judgment"]),
    ("The World", "saturn", ["world", "universe"]),
]

SUITS = [
    ("wands", "Wands", "fire", ["wands", "wand", "rods", "staves", "staffs", "batons"]),
    ("cups", "Cups", "water", ["cups", "cup", "chalices"]),
    ("swords", "Swords", "air", ["swords", "sword"]),
    ("pentacles", "Pentacles", "earth", ["pentacles", "pentacle", "coins", "disks", "discs"]),
]

RANKS = [
    (1, "ace", "Ace", ["ace", "one", "1"]),
    (2, "two", "Two", ["two", "2"]),
    (3, "three", "Three", ["three", "3"]),
    (4, "four", "Four", ["four", "4"]),
    (5, "five", "Five", ["five", "5"]),
    (6, "six", "Six", ["six", "6"]),
    (7, "seven", "Seven", ["seven", "7"]),
    (8, "eight", "Eight", ["eight", "8"]),
    (9, "nine", "Nine", ["nine", "9"]),
    (10, "ten", "Ten", ["ten", "10"]),
    (11, "page", "Page", ["page", "princess"]),
    (12, "knight", "Knight", ["knight", "prince"]),
    (13, "queen", "Queen", ["queen"]),
    (14, "king", "King", ["king"]),
]


def rws():
    cards = []
    for n, (name, attribution, aliases) in enumerate(MAJORS):
        cards.append({
            "id": f"maj-{n:02d}",
            "name": name,
            "arcana": "major",
            "number": n,
            "attribution": attribution,
            "aliases": aliases + [f"major {NUMBER_WORDS[n]}" if n <= 10 else f"major {n}"],
            "significations": {},
        })
    for suit_id, suit_name, element, suit_aliases in SUITS:
        for number, rank_id, rank_name, rank_aliases in RANKS:
            aliases = [f"{r} of {s}" for r in rank_aliases for s in suit_aliases]
            cards.append({
                "id": f"{suit_id}-{number:02d}",
                "name": f"{rank_name} of {suit_name}",
                "arcana": "minor",
                "suit": suit_id,
                "number": number,
                "rank": rank_id,
                "element": element,
                "aliases": aliases,
                "significations": {},
            })
    return {
        "id": "rws-tarot",
        "name": "Rider–Waite–Smith Tarot",
        "version": 1,
        "system": "tarot",
        "status": "complete",
        "reversalsAllowed": True,
        "aliases": ["rider waite smith", "rider waite", "rider-waite", "rws", "waite", "rider"],
        "attributes": ["arcana", "suit", "number", "rank", "element", "attribution"],
        "source": "Standard 78-card structure. Significations to be merged from Hugh's deck repository.",
        "cards": cards,
    }


def placeholder(deck_id, name, aliases, note):
    return {
        "id": deck_id,
        "name": name,
        "version": 0,
        "system": "oracle",
        "status": "placeholder",
        "reversalsAllowed": True,
        "aliases": aliases,
        "attributes": ["number", "group"],
        "source": note,
        "cards": [],
    }


def custom_template():
    return {
        "id": "custom-template",
        "name": "Custom deck (template)",
        "version": 0,
        "system": "oracle",
        "status": "template",
        "reversalsAllowed": False,
        "aliases": [],
        "attributes": ["number", "theme"],
        "source": "Copy this file, give it a new id, and add cards.",
        "cards": [],
    }


# ---------------------------------------------------------------- spreads

SPREADS = [
    {"id": "single", "name": "Single card", "aliases": ["single", "single card", "one card", "daily card"],
     "positions": [{"key": "card", "label": "Card"}], "decks": ["*"]},
    {"id": "three-card", "name": "Three card", "aliases": ["three card", "three cards", "3 card", "three card spread"],
     "positions": [{"key": "past", "label": "Past"}, {"key": "present", "label": "Present"}, {"key": "future", "label": "Future"}],
     "decks": ["*"]},
    {"id": "celtic-cross", "name": "Celtic Cross", "aliases": ["celtic cross", "celtic"],
     "positions": [
         {"key": "present", "label": "Present"},
         {"key": "challenge", "label": "Challenge"},
         {"key": "foundation", "label": "Foundation"},
         {"key": "past", "label": "Recent past"},
         {"key": "crown", "label": "Crown / possible outcome"},
         {"key": "near-future", "label": "Near future"},
         {"key": "self", "label": "Self"},
         {"key": "environment", "label": "Environment"},
         {"key": "hopes-fears", "label": "Hopes and fears"},
         {"key": "outcome", "label": "Outcome"},
     ], "decks": ["*"]},
    {"id": "freeform", "name": "Freeform", "aliases": ["freeform", "free form", "free"],
     "positions": [], "decks": ["*"], "openEnded": True},
]


# ---------------------------------------------------------------- Yi Jing

# Trigrams with lines bottom -> top, 1 = yang.
TRIGRAMS = [
    ("qian", "Qian", "☰", "Heaven", [1, 1, 1]),
    ("dui", "Dui", "☱", "Lake", [1, 1, 0]),
    ("li", "Li", "☲", "Fire", [1, 0, 1]),
    ("zhen", "Zhen", "☳", "Thunder", [1, 0, 0]),
    ("xun", "Xun", "☴", "Wind", [0, 1, 1]),
    ("kan", "Kan", "☵", "Water", [0, 1, 0]),
    ("gen", "Gen", "☶", "Mountain", [0, 0, 1]),
    ("kun", "Kun", "☷", "Earth", [0, 0, 0]),
]

# King Wen number by [upper][lower], both in this order.
KW_ORDER = ["qian", "zhen", "kan", "gen", "kun", "xun", "li", "dui"]
KW_TABLE = [
    [1, 25, 6, 33, 12, 44, 13, 10],
    [34, 51, 40, 62, 16, 32, 55, 54],
    [5, 3, 29, 39, 8, 48, 63, 60],
    [26, 27, 4, 52, 23, 18, 22, 41],
    [11, 24, 7, 15, 2, 46, 36, 19],
    [9, 42, 59, 53, 20, 57, 37, 61],
    [14, 21, 64, 56, 35, 50, 30, 38],
    [43, 17, 47, 31, 45, 28, 49, 58],
]

HEX_NAMES = {
    1: ("Qián", "The Creative"), 2: ("Kūn", "The Receptive"), 3: ("Zhūn", "Difficulty at the Beginning"),
    4: ("Méng", "Youthful Folly"), 5: ("Xū", "Waiting"), 6: ("Sòng", "Conflict"), 7: ("Shī", "The Army"),
    8: ("Bǐ", "Holding Together"), 9: ("Xiǎo Chù", "The Taming Power of the Small"), 10: ("Lǚ", "Treading"),
    11: ("Tài", "Peace"), 12: ("Pǐ", "Standstill"), 13: ("Tóng Rén", "Fellowship with Men"),
    14: ("Dà Yǒu", "Possession in Great Measure"), 15: ("Qiān", "Modesty"), 16: ("Yù", "Enthusiasm"),
    17: ("Suí", "Following"), 18: ("Gǔ", "Work on What Has Been Spoiled"), 19: ("Lín", "Approach"),
    20: ("Guān", "Contemplation"), 21: ("Shì Kè", "Biting Through"), 22: ("Bì", "Grace"),
    23: ("Bō", "Splitting Apart"), 24: ("Fù", "Return"), 25: ("Wú Wàng", "Innocence"),
    26: ("Dà Chù", "The Taming Power of the Great"), 27: ("Yí", "The Corners of the Mouth"),
    28: ("Dà Guò", "Preponderance of the Great"), 29: ("Kǎn", "The Abysmal"), 30: ("Lí", "The Clinging"),
    31: ("Xián", "Influence"), 32: ("Héng", "Duration"), 33: ("Dùn", "Retreat"), 34: ("Dà Zhuàng", "The Power of the Great"),
    35: ("Jìn", "Progress"), 36: ("Míng Yí", "Darkening of the Light"), 37: ("Jiā Rén", "The Family"),
    38: ("Kuí", "Opposition"), 39: ("Jiǎn", "Obstruction"), 40: ("Xiè", "Deliverance"), 41: ("Sǔn", "Decrease"),
    42: ("Yì", "Increase"), 43: ("Guài", "Break-through"), 44: ("Gòu", "Coming to Meet"),
    45: ("Cuì", "Gathering Together"), 46: ("Shēng", "Pushing Upward"), 47: ("Kùn", "Oppression"),
    48: ("Jǐng", "The Well"), 49: ("Gé", "Revolution"), 50: ("Dǐng", "The Cauldron"), 51: ("Zhèn", "The Arousing"),
    52: ("Gèn", "Keeping Still"), 53: ("Jiàn", "Development"), 54: ("Guī Mèi", "The Marrying Maiden"),
    55: ("Fēng", "Abundance"), 56: ("Lǚ", "The Wanderer"), 57: ("Xùn", "The Gentle"), 58: ("Duì", "The Joyous"),
    59: ("Huàn", "Dispersion"), 60: ("Jié", "Limitation"), 61: ("Zhōng Fú", "Inner Truth"),
    62: ("Xiǎo Guò", "Preponderance of the Small"), 63: ("Jì Jì", "After Completion"), 64: ("Wèi Jì", "Before Completion"),
}


def yijing():
    trig_lines = {t[0]: t[4] for t in TRIGRAMS}
    hexagrams = []
    for ui, upper in enumerate(KW_ORDER):
        for li, lower in enumerate(KW_ORDER):
            n = KW_TABLE[ui][li]
            pinyin, english = HEX_NAMES[n]
            hexagrams.append({
                "number": n,
                "pinyin": pinyin,
                "name": english,
                "lower": lower,
                "upper": upper,
                "lines": trig_lines[lower] + trig_lines[upper],
                "significations": {},
            })
    hexagrams.sort(key=lambda h: h["number"])
    assert sorted(h["number"] for h in hexagrams) == list(range(1, 65))
    return {
        "id": "yijing",
        "name": "Yi Jing",
        "version": 1,
        "lineValues": {
            "6": {"name": "old yin", "yang": False, "changing": True},
            "7": {"name": "young yang", "yang": True, "changing": False},
            "8": {"name": "young yin", "yang": False, "changing": False},
            "9": {"name": "old yang", "yang": True, "changing": True},
        },
        "aliases": ["yi jing", "i ching", "yijing", "iching", "e ching", "yi ching", "i jing"],
        "trigrams": [
            {"id": t[0], "name": t[1], "symbol": t[2], "image": t[3], "lines": t[4]} for t in TRIGRAMS
        ],
        "hexagrams": hexagrams,
    }


if __name__ == "__main__":
    write("decks/rws-tarot.json", rws())
    # decks/quareia.json and spreads/quareia-*.json are curated by hand from the
    # Quareia deckbook (see docs/quareia-deck.md); this script leaves them alone.
    write("decks/mystagogos.json", placeholder(
        "mystagogos", "Mystagogos Deck", ["mystagogos", "mystagogus", "mystagogue", "mista gogos"],
        "PLACEHOLDER: card list and significations to be generated from Hugh's Mystagogos deck repository."))
    write("decks/custom-template.json", custom_template())
    for s in SPREADS:
        write(f"spreads/{s['id']}.json", s)
    write("yijing.json", yijing())
    print("ok")
