import Foundation

/// A plain summary of `Patterns`, for the CLI, the agent and the JSONL-minded: names resolved,
/// tables cut to the top few. Codable so `--json` prints it as is.
public struct PatternsReport: Codable, Hashable, Sendable {
    public struct Row: Codable, Hashable, Sendable {
        public var key: String
        public var name: String
        public var count: Int
    }
    public struct DeckSummary: Codable, Hashable, Sendable {
        public var deckId: String
        public var name: String
        public var draws: Int
        public var reversedShare: Double?
        public var topCards: [Row]
        /// attribute (suit, element, arcana) → counts
        public var byAttribute: [String: [Row]]
    }
    public struct RecurrenceRow: Codable, Hashable, Sendable {
        public var name: String
        public var readings: Int
        public var from: String
        public var to: String
    }
    public struct Outcomes: Codable, Hashable, Sendable {
        public var readings: Int
        public var answered: Int
        public var yes: Int, partly: Int, no: Int, unclear: Int
        public var hitRate: Double?
        public var medianDaysToFirstOutcome: Int?
    }

    public var readings: Int
    public var entries: Int
    public var decks: [DeckSummary]
    public var topHexagrams: [Row]
    public var changingLines: [Row]
    public var recurrences: [RecurrenceRow]
    public var moonPhase: [Row]
    public var planetaryDay: [Row]
    public var entryTypes: [Row]
    public var topTags: [Row]
    public var outcomes: Outcomes

    public static func pretty(_ key: String) -> String {
        key.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

public extension Patterns {
    func cardName(_ deckId: String, _ cardId: String) -> String { library.deck(deckId)?.card(cardId)?.name ?? cardId }
    func hexagramName(_ n: Int) -> String { library.yijing.hexagram(n).map { "\(n) \($0.name)" } ?? "\(n)" }

    func name(of symbol: Recurrence.Symbol) -> String {
        switch symbol {
        case .card(let deck, let card): return "\(cardName(deck, card)) (\(library.deck(deck)?.name ?? deck))"
        case .hexagram(let n): return "Hexagram \(hexagramName(n))"
        }
    }

    func report(top: Int = 10, recurrenceDays: Int = 30) -> PatternsReport {
        typealias Row = PatternsReport.Row
        let decks = decksUsed.map { d -> PatternsReport.DeckSummary in
            let def = library.deck(d.key)
            var by: [String: [Row]] = [:]
            for a in (def?.attributes ?? []) where ["arcana", "suit", "element"].contains(a) {
                by[a] = attributeCounts(deckId: d.key, attribute: a).map { Row(key: $0.key, name: PatternsReport.pretty($0.key), count: $0.count) }
            }
            return PatternsReport.DeckSummary(
                deckId: d.key, name: def?.name ?? d.key, draws: d.count, reversedShare: reversedShare(deckId: d.key),
                topCards: cardCounts(deckId: d.key).prefix(top).map { Row(key: $0.key, name: cardName(d.key, $0.key), count: $0.count) },
                byAttribute: by)
        }
        let o = outcomes()
        func rows(_ t: [Tally<String>]) -> [Row] { t.map { Row(key: $0.key, name: PatternsReport.pretty($0.key), count: $0.count) } }
        return PatternsReport(
            readings: inquiries.count,
            entries: entries.count,
            decks: decks,
            topHexagrams: hexagramCounts().prefix(top).map { Row(key: "\($0.key)", name: hexagramName($0.key), count: $0.count) },
            changingLines: changingLineCounts.map { Row(key: "\($0.key)", name: "Line \($0.key)", count: $0.count) },
            recurrences: recurrences(withinDays: recurrenceDays).prefix(top).map {
                PatternsReport.RecurrenceRow(name: name(of: $0.symbol), readings: $0.inquiryIds.count, from: $0.from, to: $0.to)
            },
            moonPhase: rows(timing(.moonPhase)),
            planetaryDay: rows(timing(.planetaryDay)),
            entryTypes: rows(typeCounts),
            topTags: tagCounts.sorted { ($1.count, $0.key) < ($0.count, $1.key) }.prefix(top).map { Row(key: $0.key.path, name: $0.key.path, count: $0.count) },
            outcomes: PatternsReport.Outcomes(readings: o.total, answered: o.answered, yes: o.byFulfilled[.yes] ?? 0, partly: o.byFulfilled[.partly] ?? 0,
                                              no: o.byFulfilled[.no] ?? 0, unclear: o.byFulfilled[.unclear] ?? 0,
                                              hitRate: o.hitRate, medianDaysToFirstOutcome: o.medianDaysToFirstOutcome))
    }
}

public extension PatternsReport {
    /// The report as plain text, for a terminal or a chat.
    var text: String {
        var out = ["\(readings) reading\(readings == 1 ? "" : "s"), \(entries) other entr\(entries == 1 ? "y" : "ies")"]
        func list(_ title: String, _ rows: [Row], skipZero: Bool = true) {
            let shown = rows.filter { !skipZero || $0.count > 0 }
            guard !shown.isEmpty else { return }
            out.append("\n\(title)")
            for r in shown { out.append("  \(r.count)  \(r.name)") }
        }
        for d in decks {
            var head = "\n\(d.name): \(d.draws) draw\(d.draws == 1 ? "" : "s")"
            if let r = d.reversedShare { head += ", \(Int((r * 100).rounded()))% reversed" }
            out.append(head)
            for c in d.topCards { out.append("  \(c.count)  \(c.name)") }
            for (attr, rows) in d.byAttribute.sorted(by: { $0.key < $1.key }) {
                out.append("  by \(attr): " + rows.map { "\($0.name) \($0.count)" }.joined(separator: ", "))
            }
        }
        list("Yi Jing, most cast", topHexagrams)
        if !recurrences.isEmpty {
            out.append("\nKept coming back")
            for r in recurrences { out.append("  \(r.readings)×  \(r.name)  \(r.from) to \(r.to)") }
        }
        list("Moon phase", moonPhase)
        list("Planetary day", planetaryDay)
        list("Entries by type", entryTypes)
        list("Tags", topTags)
        let o = outcomes
        if o.readings > 0 {
            var line = "\nOutcomes: \(o.answered) of \(o.readings) readings answered (yes \(o.yes), partly \(o.partly), no \(o.no), unclear \(o.unclear))"
            if let h = o.hitRate { line += "; came true \(Int((h * 100).rounded()))%" }
            if let d = o.medianDaysToFirstOutcome { line += "; first outcome after \(d) days (median)" }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }
}
