import Foundation

/// Index notes in the Obsidian export: one per card drawn, one per hexagram cast, and a home note.
extension ObsidianExporter {
    func card(_ draws: [CardOccurrence], readings: [ULID: Inquiry], links: [String: String], key: String, meaning: PersonalMeaning? = nil) -> String {
        let deckId = draws[0].deckId, cardId = draws[0].cardId
        let deck = library.deck(deckId)
        let def = deck?.card(cardId)
        var fm: [(String, YAMLValue)] = [
            ("id", .string(key)),
            ("type", .string("card")),
            ("deck", .string(deckId)),
            ("card", .string(cardId)),
            ("name", .string(cardName(deckId, cardId))),
        ]
        for attr in deck?.attributes ?? [] {
            if let v = def?.attributes[attr] { fm.append((attr, .string(v.description))) }
        }
        let reversed = draws.filter { $0.orientation == .reversed }.count
        fm.append(("times_drawn", .int(draws.count)))
        if reversed > 0 { fm.append(("times_reversed", .int(reversed))) }
        if let meaning { fm += Self.outcomeFields(meaning) }
        fm.append(("grimoire_export_version", .int(Self.formatVersion)))

        var md = "# \(cardName(deckId, cardId))\n\n"
        md += "\(deck?.name ?? deckId). Drawn \(draws.count) time\(draws.count == 1 ? "" : "s")"
        md += reversed > 0 ? ", \(reversed) reversed.\n\n" : ".\n\n"
        if let meaning { md += meaningSection(meaning, links: links) + "## Every reading\n\n" }
        md += "| Date | Reading | Position | Orientation |\n|---|---|---|---|\n"
        for d in draws.sorted(by: { ($0.askedAt.instant, $0.inquiryId) > ($1.askedAt.instant, $1.inquiryId) }) {
            let reading = readings[d.inquiryId]
            let spread = reading?.divinations.first { $0.deckId == d.deckId && $0.draws.contains { $0.cardId == d.cardId } }?.spreadId.flatMap(library.spread)
            let link = links[d.inquiryId.string].map { Self.wiki($0, reading?.question ?? $0) } ?? d.inquiryId.string
            md += "| \(d.askedAt.day) | \(Self.cell(link)) | \(Self.cell(spread?.label(for: d.positionKey) ?? d.positionKey)) | \(d.orientation.rawValue) |\n"
        }
        return YAML.frontmatter(.map(fm), comment: Self.header) + "\n" + md
    }

    func hexagram(_ n: Int, _ casts: [HexagramOccurrence], readings: [ULID: Inquiry], links: [String: String], meaning: PersonalMeaning? = nil) -> String {
        let h = library.yijing.hexagram(n)
        var fm: [(String, YAMLValue)] = [
            ("id", .string("yijing/\(n)")),
            ("type", .string("hexagram")),
            ("number", .int(n)),
            ("name", .string(h?.name ?? "")),
        ]
        if let h {
            fm.append(("pinyin", .string(h.pinyin)))
            fm.append(("lower", .string(h.lower)))
            fm.append(("upper", .string(h.upper)))
        }
        let primary = casts.filter { $0.role == .primary }.count
        fm.append(("times_cast", .int(primary)))
        fm.append(("times_resulting", .int(casts.count - primary)))
        if let meaning { fm += Self.outcomeFields(meaning) }
        fm.append(("grimoire_export_version", .int(Self.formatVersion)))

        var md = "# \(n). \(h?.name ?? "")\n\n"
        md += "Cast \(primary) time\(primary == 1 ? "" : "s")"
        md += casts.count > primary ? ", changed into \(casts.count - primary) time\(casts.count - primary == 1 ? "" : "s").\n\n" : ".\n\n"
        if let meaning { md += meaningSection(meaning, links: links) + "## Every reading\n\n" }
        md += "| Date | Reading | As | Changing lines |\n|---|---|---|---|\n"
        for c in casts.sorted(by: { ($0.askedAt.instant, $0.inquiryId) > ($1.askedAt.instant, $1.inquiryId) }) {
            let q = readings[c.inquiryId]?.question
            let link = links[c.inquiryId.string].map { Self.wiki($0, q ?? $0) } ?? c.inquiryId.string
            md += "| \(c.askedAt.day) | \(Self.cell(link)) | \(c.role.rawValue) | \(c.changingLines.map(String.init).joined(separator: ", ")) |\n"
        }
        return YAML.frontmatter(.map(fm), comment: Self.header) + "\n" + md
    }

    /// Outcome counts for a card or hexagram note's frontmatter, so Dataview can sort by them.
    static func outcomeFields(_ m: PersonalMeaning) -> [(String, YAMLValue)] {
        var fm: [(String, YAMLValue)] = [("readings_with_outcome", .int(m.outcomes.answered))]
        for f in [Outcome.Fulfilled.yes, .partly, .no, .unclear] {
            if let n = m.outcomes.byFulfilled[f], n > 0 { fm.append(("outcome_\(f.rawValue)", .int(n))) }
        }
        return fm
    }

    /// "What it has meant for you": the summary, your own notes, and what happened when it came true.
    func meaningSection(_ m: PersonalMeaning, links: [String: String]) -> String {
        func reading(_ a: PersonalMeaning.Appearance) -> String {
            links[a.inquiryId.string].map { Self.wiki($0, a.question) } ?? a.question
        }
        func oneLine(_ s: String) -> String { s.split(whereSeparator: \.isNewline).joined(separator: " ") }
        var md = "## What it has meant for you\n\n\(m.summary)\n\n"
        let words = m.appearances.filter { !($0.note ?? "").isEmpty }
        if !words.isEmpty {
            md += "### In your words\n\n"
            for a in words.prefix(12) { md += "- \(a.day), \(reading(a)): \(oneLine(a.note!))\n" }
            md += "\n"
        }
        let fulfilled = m.whenItCameTrue
        if !fulfilled.isEmpty {
            md += "### When it came true\n\n"
            for a in fulfilled.prefix(12) {
                let o = a.outcome!
                md += "- \(a.day), \(reading(a)) (\(o.fulfilled == .yes ? "yes" : "partly"), as \(a.position)): \(oneLine(o.body))\n"
            }
            md += "\n"
        }
        return md
    }

    /// The vault's way in: open readings, notebooks, the cards and hexagrams that come up most.
    func home(_ data: GrimoireData, patterns: Patterns, links: [String: String]) -> String {
        let fm: [(String, YAMLValue)] = [("type", .string("grimoire-home")), ("grimoire_export_version", .int(Self.formatVersion))]
        var md = "# Grimoire\n\n"
        md += "\(data.inquiries.count) readings, \(data.entries.filter { $0.status == .filed }.count) entries, \(data.volumes.count) notebooks.\n"
        let open = data.inquiries.filter { $0.status == .open }.sorted { $0.askedAt.instant > $1.askedAt.instant }
        if !open.isEmpty {
            md += "\n## Open readings\n\n"
            for i in open.prefix(20) { md += "- \(i.askedAt.day) \(Self.wiki(links[i.id.string]!, i.question))\n" }
        }
        if !data.volumes.isEmpty {
            md += "\n## Notebooks\n\n"
            for v in data.volumes.sorted(by: { $0.name < $1.name }) { md += "- \(Self.wiki("\(Self.slug(v.name))-\(v.id)", v.name))\n" }
        }
        let cards = patterns.cardCounts().prefix(10)
        if !cards.isEmpty {
            md += "\n## Cards that come up most\n\n"
            for c in cards {
                let parts = c.key.split(separator: "/", maxSplits: 1).map(String.init)
                md += "- \(Self.wiki(cardBase(parts[0], parts[1]), cardName(parts[0], parts[1]))) · \(c.count)\n"
            }
        }
        let hex = patterns.hexagramCounts().prefix(5)
        if !hex.isEmpty {
            md += "\n## Hexagrams cast most\n\n"
            for h in hex { md += "- \(Self.wiki(hexagramBase(h.key), "\(h.key). \(library.yijing.hexagram(h.key)?.name ?? "")")) · \(h.count)\n" }
        }
        return YAML.frontmatter(.map(fm), comment: Self.header) + "\n" + md
    }
}
