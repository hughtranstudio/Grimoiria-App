#!/usr/bin/env python3
"""Writes the importer test fixtures in Tests/GrimoireCoreTests/Fixtures/import/.

The same Google Doc ("Magical diary autumn 2025") is written twice, once as the Markdown the
connector route produces and once as the .docx Google Docs downloads, so the tests can check that
both routes give the same Inbox items (spec §14). Run from the repo root; output is deterministic.
"""
import pathlib
import zipfile
from xml.sax.saxutils import escape

OUT = pathlib.Path("Tests/GrimoireCoreTests/Fixtures/import")

# (style, text) per paragraph; style None is body text, "" an empty paragraph.
DIARY = [
    ("Title", "Magical diary autumn 2025"),
    ("Heading2", "3 October 2025 — Ritual: opening the directions"),
    (None, "Opened the four directions at dawn. Strong sense of the threshold in the east. #theme/threshold"),
    ("", ""),
    ("Heading2", "Saturday, 4 October 2025, 9:40 pm — Reading"),
    (None, "Question: should I start the new course this winter?"),
    (None, "Deck Rider-Waite. Three card. Three of cups reversed, the Tower, page of wands."),
    ("", ""),
    ("Heading2", "2025-10-05 08:15 Dream"),
    (None, "Walked through a flooded library; a crow carried a key."),
    (None, "2025-10-20: the course was confirmed, so the reading held."),
    ("", ""),
    ("Heading2", "6 Oct 2025 Yi Jing on the house"),
    (None, "Yi Jing, coins. 7 8 9 6 7 7."),
]

FRONTMATTER = """---
source: google-docs
google_doc_id: 1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789
source_url: https://docs.google.com/document/d/1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789/edit
title: Magical diary autumn 2025
modified: 2025-11-02T09:00:00Z
tags: [source/google-docs]
---
"""


def markdown(paras):
    lines = []
    for style, text in paras:
        if style == "Title":
            lines.append("# " + text)
        elif style and style.startswith("Heading"):
            lines.append("#" * int(style[-1]) + " " + text)
        else:
            lines.append(text)
    return "\n".join(lines) + "\n"


W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'


def run(text, bold=False):
    rpr = "<w:rPr><w:b/></w:rPr>" if bold else ""
    return f'<w:r>{rpr}<w:t xml:space="preserve">{escape(text)}</w:t></w:r>'


def paragraph(style, text, numbered=False):
    ppr = ""
    if style:
        ppr = f'<w:pPr><w:pStyle w:val="{style}"/></w:pPr>'
    elif numbered:
        ppr = '<w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr>'
    if style and style.startswith("Heading") and " — " in text:
        # Google Docs often splits a heading into runs; keep the date in its own bold run.
        date, rest = text.split(" — ", 1)
        runs = run(date, bold=True) + run(" — " + rest)
    else:
        runs = run(text) if text else ""
    return f"<w:p>{ppr}{runs}</w:p>"


def docx(path, body_xml, modified):
    files = {
        "[Content_Types].xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        "</Types>",
        "_rels/.rels": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        "</Relationships>",
        "docProps/core.xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        f'<dcterms:modified xsi:type="dcterms:W3CDTF">{modified}</dcterms:modified></cp:coreProperties>',
        "word/document.xml": f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W}><w:body>{body_xml}</w:body></w:document>',
    }
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for name, content in files.items():
            info = zipfile.ZipInfo(name, date_time=(2025, 11, 2, 9, 0, 0))
            info.compress_type = zipfile.ZIP_STORED if name.startswith("[") else zipfile.ZIP_DEFLATED
            z.writestr(info, content)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "magical-diary-autumn-2025.md").write_text(FRONTMATTER + markdown(DIARY))
    docx(OUT / "Magical diary autumn 2025.docx", "".join(paragraph(s, t) for s, t in DIARY), "2025-11-02T09:00:00Z")

    # Structure check: tabs, line breaks, a list, a table, entities and non-ASCII text.
    body = (
        paragraph("Heading1", "Tools & tables")
        + '<w:p><w:r><w:t>Line one</w:t><w:br/><w:t>line two</w:t><w:tab/><w:t>tabbed</w:t></w:r></w:p>'
        + paragraph(None, "Salt", numbered=True)
        + paragraph(None, "Water", numbered=True)
        + "<w:tbl><w:tr><w:tc>" + paragraph(None, "Card") + "</w:tc><w:tc>" + paragraph(None, "Position") + "</w:tc></w:tr>"
        + "<w:tr><w:tc>" + paragraph(None, "The Tower") + "</w:tc><w:tc>" + paragraph(None, "Outcome") + "</w:tc></w:tr></w:tbl>"
        + paragraph(None, "Évocation <done> “quoted”")
    )
    docx(OUT / "structure.docx", body, "2025-01-15T10:00:00Z")

    # Downloaded as plain text, US numeric dates, no headings.
    (OUT / "notebook.txt").write_text(
        "Notebook\n\n"
        "10/28/2025\n"
        "Three crows on the fence at the crossroads. #entity/crow\n\n"
        "11/02/2025 Meditation\n"
        "Sat with the breath for twenty minutes.\n"
    )


if __name__ == "__main__":
    main()
