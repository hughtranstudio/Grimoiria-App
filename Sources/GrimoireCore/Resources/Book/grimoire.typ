// Grimoire book layout (Typst 0.14+).
// Content comes from book.json (written by BookExporter); every visual choice comes from
// design.json, so a new look is a new design.json, not a new template.

// MARK: Lookups

#let paper-sizes = (
  "a4": (210mm, 297mm),
  "a5": (148mm, 210mm),
  "a6": (105mm, 148mm),
  "b5": (176mm, 250mm),
  "us-letter": (8.5in, 11in),
  "us-trade": (6in, 9in),
  "royal": (6.14in, 9.21in),
  "pocket": (4.25in, 6.87in),
)

#let sign-glyphs = (
  aries: "♈", taurus: "♉", gemini: "♊", cancer: "♋", leo: "♌", virgo: "♍",
  libra: "♎", scorpio: "♏", sagittarius: "♐", capricorn: "♑", aquarius: "♒", pisces: "♓",
)
#let planet-glyphs = (
  sun: "☉", moon: "☽", mercury: "☿", venus: "♀", mars: "♂", jupiter: "♃", saturn: "♄",
)

#let length(s) = if type(s) == str { eval(s) } else { s }
#let words(s) = s.replace("-", " ")

// MARK: Book

#let render(book, design) = {
  let pg = design.page
  let ty = design.at("type")
  let col = design.colour
  let orn = design.ornament
  let show-opt = design.content
  let ink = rgb(col.ink)
  let accent = rgb(col.accent)
  let quiet = rgb(col.quiet)
  let rule-colour = rgb(col.rule)

  let (trim-w, trim-h) = if type(pg.size) == str { paper-sizes.at(pg.size) } else { (length(pg.size.width), length(pg.size.height)) }
  let bleed = length(pg.at("bleed", default: "0mm"))
  let m = pg.margins

  // Symbols use their own font list; VS15 asks for the text (not emoji) form.
  let sym(glyph) = text(font: ty.symbols, fallback: true, glyph + "\u{fe0e}")
  let label-text(body, size: 0.78em, fill: quiet) = {
    let t = text(font: ty.label, size: size, fill: fill, tracking: 0.04em, body)
    if ty.smallCapsLabels { smallcaps(t) } else { upper(text(size: 0.92em, t)) }
  }
  // Sticky, so an ornament never sits alone at the foot of a page.
  let separator() = block(sticky: true, above: 0.9em, below: 0.9em, width: 100%,
    if orn.itemSeparator == "rule" {
      line(length: 100%, stroke: 0.5pt + rule-colour)
    } else {
      align(center, text(fill: accent, size: 1.1em, sym(orn.itemSeparator)))
    })

  let crop-marks = if pg.at("cropMarks", default: false) and bleed > 0pt {
    let w = trim-w + 2 * bleed
    let h = trim-h + 2 * bleed
    let gap = 1mm
    let s = 0.25pt + black
    for (x, y) in ((bleed, bleed), (w - bleed, bleed), (bleed, h - bleed), (w - bleed, h - bleed)) {
      place(top + left, dx: if x == bleed { 0pt } else { x + gap }, dy: y, line(length: bleed - gap, stroke: s))
      place(top + left, dx: x, dy: if y == bleed { 0pt } else { y + gap }, line(length: bleed - gap, angle: 90deg, stroke: s))
    }
  }

  set document(title: book.title)
  set text(font: ty.body, size: length(ty.size), fill: ink, lang: "en", hyphenate: ty.justify)
  set par(justify: ty.justify, leading: length(ty.leading), spacing: length(ty.paragraphSpacing), first-line-indent: length(ty.indent))
  set page(
    width: trim-w + 2 * bleed,
    height: trim-h + 2 * bleed,
    margin: (
      inside: length(m.inside) + bleed, outside: length(m.outside) + bleed,
      top: length(m.top) + bleed, bottom: length(m.bottom) + bleed,
    ),
    foreground: crop-marks,
  )

  // Marks where a part of the book stops, so the filler page before a right-hand chapter opener stays blank.
  let end-mark = [#metadata("end") <grimoire-end>]

  // Chapter titles: level 1. Item titles: level 2, never numbered.
  show heading.where(level: 1): it => {
    pagebreak(weak: true, to: if pg.chaptersOnRecto { "odd" } else { none })
    v(18%)
    if orn.chapterMark != "" { align(center, text(fill: accent, size: 1.6em, sym(orn.chapterMark))); v(0.6em) }
    align(center, text(font: ty.display, size: 2em, weight: "regular", fill: accent, it.body))
    v(0.4em)
    align(center, line(length: 30%, stroke: 0.6pt + rule-colour))
    v(2.4em)
  }
  show heading.where(level: 2): it => block(below: 0.5em, text(font: ty.display, size: 1.35em, weight: "regular", it.body))
  show outline.entry.where(level: 1): it => { v(0.3em); it }

  // MARK: Title page and contents

  page(header: none, footer: none, {
    v(26%)
    align(center, {
      if orn.titleMark != "" { text(fill: accent, size: 1.4em, sym(orn.titleMark)); v(1.2em) }
      text(font: ty.display, size: 2.8em, fill: ink, book.title)
      if book.at("subtitle", default: none) != none { v(0.4em); text(font: ty.display, size: 1.3em, style: "italic", book.subtitle) }
      v(1.4em)
      line(length: 25%, stroke: 0.6pt + rule-colour)
      v(1em)
      if book.at("period", default: none) != none { label-text(book.period, size: 0.9em) }
      v(0.4em)
      text(size: 0.85em, fill: quiet)[#book.counts.entries entries · #book.counts.readings readings]
    })
    end-mark
  })

  // Running heads: book title on the left page, chapter on the right; none on chapter openers.
  set page(
    header: context {
      let p = here().page()
      let chapters = query(heading.where(level: 1))
      if chapters.any(h => h.location().page() == p) { return }
      let ended = query(<grimoire-end>).map(m => m.location().page()).filter(e => e <= p)
      let next = chapters.filter(h => h.location().page() > p)
      if ended.len() > 0 and ended.last() < p and next.len() > 0 and next.first().location().page() == p + 1 { return }
      let before = chapters.filter(h => h.location().page() <= p)
      let chapter = if before.len() > 0 { before.last().body } else { [] }
      // Left-hand (even) pages carry the book title, right-hand pages the chapter; numbers sit outside.
      let odd = calc.odd(p)
      set text(size: 0.8em, fill: quiet)
      grid(columns: (1fr, 1fr),
        align(left, if odd { label-text(chapter, size: 1em) } else { counter(page).display() }),
        align(right, if odd { counter(page).display() } else { label-text(book.title, size: 1em) }),
      )
      v(-0.4em)
      line(length: 100%, stroke: 0.4pt + rule-colour)
    },
    footer: none,
  )

  if show-opt.contents and book.chapters.len() > 1 {
    pagebreak(weak: true)
    outline(title: text(font: ty.display, weight: "regular", fill: accent)[Contents], depth: 1)
    end-mark
  }

  // MARK: Pieces

  let paragraphs(s, initial: true) = {
    for (i, para) in s.trim().split(regex("\n\s*\n")).enumerate() {
      let lines = para.split("\n").map(l => [#l]).join(linebreak())
      if i == 0 and initial and ty.initial == "accent" and para.len() > 0 {
        let first = para.clusters().first()
        let rest = para.clusters().slice(1).join()
        par[#text(fill: accent, size: 1.25em, first)#rest.split("\n").map(l => [#l]).join(linebreak())]
      } else {
        par(lines)
      }
    }
  }

  let timing-line(t) = {
    let parts = (
      [#sym(planet-glyphs.moon) #words(t.moonPhase) in #sym(sign-glyphs.at(t.moonSign)) #t.moonSign, #t.moonIllumination%],
      [#sym(planet-glyphs.sun) in #sym(sign-glyphs.at(t.sunSign)) #t.sunSign],
    )
    if t.at("planetaryDay", default: none) != none {
      parts.push([day of #sym(planet-glyphs.at(t.planetaryDay))#if t.at("planetaryHour", default: none) != none [, hour of #sym(planet-glyphs.at(t.planetaryHour))]])
    }
    text(size: 0.82em, fill: quiet, parts.join([ · ]))
  }

  let fields-grid(fields) = if fields.len() > 0 {
    block(above: 0.6em, below: 0.9em, grid(
      columns: (auto, 1fr), column-gutter: 1em, row-gutter: 0.55em,
      ..fields.map(f => (label-text(f.label), text(size: 0.95em, f.value))).flatten(),
    ))
  }

  let hexagram(lines, marks: true, width: 2.6em) = {
    let bar(w) = rect(width: w, height: 0.36em, fill: ink)
    stack(dir: ttb, spacing: 0.3em, ..lines.rev().map(v => {
      let yang = v == 7 or v == 9
      let line-shape = if yang { bar(width) } else { stack(dir: ltr, spacing: width * 0.2, bar(width * 0.4), bar(width * 0.4)) }
      let mark = if marks and v == 9 { text(fill: accent, size: 0.95em)[○] } else if marks and v == 6 { text(fill: accent, size: 0.95em)[×] } else { [] }
      stack(dir: ltr, spacing: 0.45em, line-shape, box(width: 0.8em, height: 0.36em, align(horizon, mark)))
    }))
  }
  let changed(v) = if v == 9 { 8 } else if v == 6 { 7 } else { v }
  let hex-name(h) = [#text(weight: "semibold")[#h.number.] #h.name #text(fill: quiet, style: "italic")[#h.pinyin]]

  let spread(draws) = {
    let n = calc.min(draws.len(), 5)
    grid(columns: (1fr,) * n, column-gutter: 0.6em, row-gutter: 0.8em,
      ..draws.map(d => block(width: 100%, {
        align(center, label-text(d.position, size: 0.7em))
        v(-0.3em)
        block(width: 100%, inset: (x: 0.4em, y: 0.9em), stroke: (paint: rule-colour, thickness: 0.6pt, dash: if d.reversed { "dashed" } else { none }), radius: 2pt,
          align(center, {
            text(font: ty.display, size: 1em, d.card)
            if d.reversed { linebreak(); text(size: 0.75em, style: "italic", fill: accent)[reversed] }
          }))
        if d.at("notes", default: none) != none { align(center, text(size: 0.75em, fill: quiet, d.notes)) }
      }))
    )
  }

  let divination(dv) = block(breakable: false, above: 1em, below: 1em, {
    let heading-bits = (dv.at("deck", default: none), dv.at("spread", default: none), dv.at("method", default: none)).filter(x => x != none)
    if dv.system == "yijing" { heading-bits = ("Yi Jing",) + heading-bits }
    label-text(heading-bits.join(" · "), fill: accent)
    v(0.4em)
    if dv.at("cast", default: none) != none {
      let c = dv.cast
      grid(columns: if c.at("resulting", default: none) != none { (auto, auto, auto) } else { (auto,) }, column-gutter: 1.6em, align: horizon,
        stack(dir: ttb, spacing: 0.6em, hexagram(c.lines), text(size: 0.85em, hex-name(c.primary))),
        ..if c.at("resulting", default: none) != none {
          (text(fill: quiet, size: 1.2em)[→],
           stack(dir: ttb, spacing: 0.6em, hexagram(c.lines.map(changed), marks: false), text(size: 0.85em, hex-name(c.resulting))))
        } else { () },
      )
      if c.changing.len() > 0 {
        v(0.3em)
        text(size: 0.8em, fill: quiet)[Changing line#if c.changing.len() > 1 [s] #c.changing.map(str).join(", ")]
      }
    }
    if dv.draws.len() > 0 { spread(dv.draws) }
    if dv.at("notes", default: none) != none { v(0.3em); text(size: 0.9em, style: "italic", dv.notes) }
  })

  let item(it) = {
    block(breakable: true, {
      // The date line, title and timing stay together and with what follows.
      block(sticky: true, breakable: false, {
        label-text([#it.typeLabel · #it.dateLabel · #it.time], fill: accent)
        if it.title != "" { heading(level: 2, outlined: false, it.title) } else { v(0.3em) }
        if show-opt.timing and it.at("timing", default: none) != none { block(above: 0.2em, below: 0.8em, timing-line(it.timing)) }
      })
      fields-grid(it.fields)
      if it.body.trim() != "" and not (it.kind == "reading" and it.body.trim() == it.title.trim()) { paragraphs(it.body) }
      for dv in it.divinations { divination(dv) }
      if it.at("synthesis", default: none) != none {
        block(above: 0.8em, { set par(first-line-indent: 0em); label-text("Synthesis"); v(0.2em); text(style: "italic", it.synthesis) })
      }
      for o in it.outcomes {
        block(above: 0.8em, {
          set par(first-line-indent: 0em)
          label-text([Outcome · #o.day · #o.daysAfter days later · #o.fulfilled])
          v(0.2em)
          paragraphs(o.body, initial: false)
        })
      }
      if it.at("transcript", default: none) != none {
        block(above: 0.8em, { set par(first-line-indent: 0em); label-text("Transcript"); v(0.2em); text(size: 0.88em, fill: quiet, it.transcript) })
      }
      if show-opt.photos {
        for img in it.images { figure(image(img, width: 100%), gap: 0.4em) }
      }
      let foot = ()
      if it.at("physical", default: none) != none { foot.push(it.physical) }
      if show-opt.tags and it.tags.len() > 0 { foot.push(it.tags.map(t => "#" + t).join("  ")) }
      if foot.len() > 0 { block(above: 0.8em, par(first-line-indent: 0em, text(size: 0.78em, fill: quiet, foot.join("   ·   ")))) }
    })
  }

  // MARK: Chapters

  for (n, chapter) in book.chapters.enumerate() {
    heading(level: 1, chapter.title)
    // Body pages count from the first chapter opener.
    if n == 0 { counter(page).update(1) }
    for (i, it) in chapter.items.enumerate() {
      if i > 0 { separator() }
      // Each item is anchored once (its first appearance) so indexes can point at its page.
      [#item(it) #metadata(it.id) <grimoire-item>]
    }
    end-mark
  }

  // MARK: Indexes

  let page-of(id) = context {
    let hits = query(<grimoire-item>).filter(m => m.value == id)
    if hits.len() > 0 {
      let loc = hits.first().location()
      link(loc, str(counter(page).at(loc).first()))
    }
  }
  let index(title, entries) = if entries.len() > 0 {
    heading(level: 1, title)
    set par(first-line-indent: 0em, justify: false)
    columns(2, gutter: 1.6em, {
      let group = none
      for e in entries {
        if e.group != group {
          group = e.group
          block(above: 1.1em, below: 0.5em, label-text(group, fill: accent))
        }
        block(above: 0.35em, below: 0.35em, [#e.label #box(width: 1fr, repeat[.#h(0.3em)]) #e.items.dedup().map(page-of).join(", ")])
      }
    })
    end-mark
  }
  if show-opt.cardIndex { index("Index of Cards", book.cardIndex) }
  if show-opt.hexagramIndex { index("Index of Hexagrams", book.hexagramIndex) }
}
