import Foundation

/// What a card or hexagram has meant in your own readings: where it fell, what the readings were about,
/// what you wrote about it, and how those readings turned out. Built from the records on demand,
/// next to the book meaning from the deck file; nothing here is stored.
public struct PersonalMeaning: Hashable, Sendable {
    /// One reading the card or hexagram came up in.
    public struct Appearance: Hashable, Sendable {
        public var inquiryId: ULID
        public var day: String
        public var question: String
        /// Spread position label for a card; "cast" or "changed into" for a hexagram.
        public var position: String
        public var orientation: Orientation?
        public var changingLines: [Int]
        /// What you wrote about this card in this reading (its draw note), or the divination note for a cast.
        public var note: String?
        /// The latest outcome of the reading, if any.
        public var outcome: Outcome?
    }

    public var symbol: Recurrence.Symbol
    public var name: String
    /// Significations from the deck or Yi Jing file ("upright", "reversed", "keywords", …).
    public var bookMeaning: [String: AttributeValue]
    /// Newest first, one per reading.
    public var appearances: [Appearance]
    public var timesReversed: Int
    /// Each reading counted once, by its latest outcome.
    public var outcomes: OutcomeStats
    /// Question categories and tags of the readings it came up in, most first.
    public var topics: [Tally<TagPath>]
    /// Positions it fell in, most first.
    public var positions: [Tally<String>]

    public var times: Int { appearances.count }

    /// Your own notes on it, newest first, with the day.
    public var inYourWords: [(day: String, text: String)] {
        appearances.compactMap { a in a.note.flatMap { $0.isEmpty ? nil : (a.day, $0) } }
    }

    /// What happened in readings that came true or partly true, newest first.
    public var whenItCameTrue: [Appearance] {
        appearances.filter { $0.outcome.map { $0.fulfilled == .yes || $0.fulfilled == .partly } ?? false }
    }

    /// One plain paragraph: how often, about what, where, and how it turned out.
    public var summary: String {
        var s = times == 1 ? "Came up once" : "Came up \(times) times"
        if timesReversed > 0 { s += ", \(timesReversed) reversed" }
        let about = topics.prefix(3).map { $0.key.leaf }
        if !about.isEmpty { s += ", mostly about \(Self.list(about))" }
        s += "."
        // A freeform spread only numbers its positions, which says nothing.
        if times > 1, let top = positions.first, top.count > 1, Int(top.key) == nil {
            s += " Most often in \(top.key)."
        }
        let yes = outcomes.byFulfilled[.yes] ?? 0, partly = outcomes.byFulfilled[.partly] ?? 0
        let no = outcomes.byFulfilled[.no] ?? 0, unclear = outcomes.byFulfilled[.unclear] ?? 0
        if outcomes.answered == 0 {
            s += " No outcomes recorded yet."
        } else if outcomes.answered == 1 {
            switch outcomes.byFulfilled.first?.key {
            case .yes: s += " The one reading with an outcome came true."
            case .partly: s += " The one reading with an outcome came partly true."
            case .no: s += " The one reading with an outcome didn't come true."
            default: s += " The one reading with an outcome is still unclear."
            }
        } else {
            var parts: [String] = []
            if yes > 0 { parts.append("\(yes) came true") }
            if partly > 0 { parts.append("\(partly) partly") }
            if no > 0 { parts.append("\(no) didn't") }
            if unclear > 0 { parts.append("\(unclear) unclear") }
            s += " Of the \(outcomes.answered) readings with an outcome, \(Self.list(parts))."
        }
        return s
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }
}

extension TagPath {
    /// The last part of the path, without dashes: `question/work-life` → "work life".
    var leaf: String { (path.split(separator: "/").last.map(String.init) ?? path).replacingOccurrences(of: "-", with: " ") }
}

extension Patterns {
    /// Your meaning of one card, or nil when it was never drawn in the window.
    public func meaning(card cardId: String, deckId: String) -> PersonalMeaning? {
        let draws = cards.filter { $0.deckId == deckId && $0.cardId == cardId }
        guard !draws.isEmpty else { return nil }
        let byId = Dictionary(uniqueKeysWithValues: inquiries.map { ($0.id, $0) })
        var seen = Set<ULID>()
        var appearances: [PersonalMeaning.Appearance] = []
        for d in draws.sorted(by: { ($0.askedAt.instant, $0.inquiryId) > ($1.askedAt.instant, $1.inquiryId) }) where seen.insert(d.inquiryId).inserted {
            guard let i = byId[d.inquiryId] else { continue }
            let div = i.divinations.first { $0.deckId == deckId && $0.draws.contains { $0.cardId == cardId } }
            let draw = div?.draws.first { $0.cardId == cardId }
            let label = div?.spreadId.flatMap(library.spread)?.label(for: d.positionKey) ?? d.positionKey
            appearances.append(.init(inquiryId: i.id, day: d.askedAt.day, question: i.question, position: label,
                                     orientation: d.orientation, changingLines: [], note: draw?.notes, outcome: i.outcomes.last))
        }
        let deck = library.deck(deckId)
        return build(.card(deckId: deckId, cardId: cardId), name: deck?.card(cardId)?.name ?? cardId,
                     book: deck?.card(cardId)?.significations ?? [:], appearances: appearances,
                     reversed: draws.filter { $0.orientation == .reversed }.count,
                     extraTags: draws.compactMap { d in byId[d.inquiryId]?.divinations.flatMap(\.draws).first { $0.cardId == cardId }?.tags }.flatMap { $0 })
    }

    /// Your meaning of one hexagram, cast or changed into, or nil when it never came up.
    public func meaning(hexagram number: Int) -> PersonalMeaning? {
        let casts = hexagrams.filter { $0.number == number }
        guard !casts.isEmpty else { return nil }
        let byId = Dictionary(uniqueKeysWithValues: inquiries.map { ($0.id, $0) })
        var seen = Set<ULID>()
        var appearances: [PersonalMeaning.Appearance] = []
        // A reading that both cast it and changed into it counts once, as cast.
        for c in casts.sorted(by: { ($0.role == .primary ? 0 : 1) < ($1.role == .primary ? 0 : 1) }) where seen.insert(c.inquiryId).inserted {
            guard let i = byId[c.inquiryId] else { continue }
            let div = i.divinations.first { $0.cast != nil }
            appearances.append(.init(inquiryId: i.id, day: c.askedAt.day, question: i.question,
                                     position: c.role == .primary ? "cast" : "changed into", orientation: nil,
                                     changingLines: c.changingLines, note: div?.notes, outcome: i.outcomes.last))
        }
        appearances.sort { ($0.day, $0.inquiryId) > ($1.day, $1.inquiryId) }
        let h = library.yijing.hexagram(number)
        return build(.hexagram(number), name: h.map { "\(number). \($0.name)" } ?? "\(number)", book: h?.significations ?? [:],
                     appearances: appearances, reversed: 0, extraTags: [])
    }

    /// Every card and hexagram that came up, most often first.
    public func meanings() -> [PersonalMeaning] {
        var keys = Set<Recurrence.Symbol>()
        for c in cards { keys.insert(.card(deckId: c.deckId, cardId: c.cardId)) }
        for h in hexagrams { keys.insert(.hexagram(h.number)) }
        return keys.compactMap { key -> PersonalMeaning? in
            switch key {
            case let .card(deckId, cardId): return meaning(card: cardId, deckId: deckId)
            case let .hexagram(n): return meaning(hexagram: n)
            }
        }.sorted { ($1.times, $0.name) < ($0.times, $1.name) }
    }

    private func build(_ symbol: Recurrence.Symbol, name: String, book: [String: AttributeValue],
                       appearances: [PersonalMeaning.Appearance], reversed: Int, extraTags: [TagPath]) -> PersonalMeaning {
        let byId = Dictionary(uniqueKeysWithValues: inquiries.map { ($0.id, $0) })
        var stats = OutcomeStats()
        stats.total = appearances.count
        var days: [Int] = []
        var topicKeys: [TagPath] = extraTags
        for a in appearances {
            guard let i = byId[a.inquiryId] else { continue }
            topicKeys += (i.category.map { [$0] } ?? []) + i.tags
            guard let first = i.outcomes.first, let last = i.outcomes.last else { continue }
            stats.answered += 1
            stats.byFulfilled[last.fulfilled, default: 0] += 1
            days.append(i.daysAfter(first))
        }
        days.sort()
        stats.medianDaysToFirstOutcome = days.isEmpty ? nil : days[days.count / 2]
        let topics = Dictionary(topicKeys.map { ($0, 1) }, uniquingKeysWith: +).map { Tally($0.key, $0.value) }
            .sorted { ($1.count, $0.key) < ($0.count, $1.key) }
        return PersonalMeaning(symbol: symbol, name: name, bookMeaning: book, appearances: appearances, timesReversed: reversed,
                               outcomes: stats, topics: topics, positions: Self.tally(appearances.map(\.position)))
    }
}

extension DefinitionLibrary {
    /// A card or hexagram from what you type: "the tower", "3 cups", "yijing/29", "hexagram 29", "29".
    /// Cards are looked for in `deckId` when given, otherwise in every deck, first match wins.
    public func symbol(named text: String, deckId: String? = nil) -> Recurrence.Symbol? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        for prefix in ["yijing/", "hexagram ", "hex "] where t.hasPrefix(prefix) {
            if let n = Int(t.dropFirst(prefix.count)), yijing.hexagram(n) != nil { return .hexagram(n) }
        }
        if deckId == nil, let n = Int(t), yijing.hexagram(n) != nil { return .hexagram(n) }
        if let slash = t.firstIndex(of: "/"), deck(String(t[..<slash])) != nil {
            let d = String(t[..<slash]), c = String(t[t.index(after: slash)...])
            if deck(d)?.card(c) != nil { return .card(deckId: d, cardId: c) }
        }
        for d in decks where (deckId == nil || d.id == deckId) && !d.cards.isEmpty {
            if let m = d.cardMatcher.match(t) { return .card(deckId: d.id, cardId: m.id) }
        }
        if deckId == nil, let h = yijing.hexagrams.first(where: { $0.name.lowercased() == t || $0.pinyin.lowercased() == t }) {
            return .hexagram(h.number)
        }
        return nil
    }
}

extension PersonalMeaning {
    /// A plain, Codable copy for `--json` and other apps.
    public struct Report: Codable, Hashable, Sendable {
        public struct Reading: Codable, Hashable, Sendable {
            public var id: String
            public var day: String
            public var question: String
            public var position: String
            public var orientation: String?
            public var changingLines: [Int]?
            public var note: String?
            public var outcome: String?
            public var fulfilled: String?
        }
        public var key: String
        public var name: String
        public var summary: String
        public var times: Int
        public var timesReversed: Int
        public var outcomes: [String: Int]
        public var topics: [String]
        public var positions: [String: Int]
        public var bookMeaning: [String: String]
        public var readings: [Reading]
    }

    public var key: String {
        switch symbol {
        case let .card(deckId, cardId): return "\(deckId)/\(cardId)"
        case let .hexagram(n): return "yijing/\(n)"
        }
    }

    public var report: Report {
        Report(key: key, name: name, summary: summary, times: times, timesReversed: timesReversed,
               outcomes: Dictionary(uniqueKeysWithValues: outcomes.byFulfilled.map { ($0.key.rawValue, $0.value) }),
               topics: topics.map(\.key.path), positions: Dictionary(uniqueKeysWithValues: positions.map { ($0.key, $0.count) }),
               bookMeaning: bookMeaning.mapValues(\.description),
               readings: appearances.map {
                   .init(id: $0.inquiryId.string, day: $0.day, question: $0.question, position: $0.position,
                         orientation: $0.orientation?.rawValue, changingLines: $0.changingLines.isEmpty ? nil : $0.changingLines,
                         note: $0.note, outcome: $0.outcome?.body, fulfilled: $0.outcome?.fulfilled.rawValue)
               })
    }

    /// The whole page as plain text, for the command line.
    public var text: String {
        var s = "\(name)\n\n\(summary)\n"
        if !bookMeaning.isEmpty {
            s += "\nThe book says\n"
            for (k, v) in bookMeaning.sorted(by: { $0.key < $1.key }) { s += "  \(k): \(v)\n" }
        }
        let words = appearances.filter { !($0.note ?? "").isEmpty }
        if !words.isEmpty {
            s += "\nIn your words\n"
            for a in words { s += "  \(a.day)  \(a.note!)  (\(a.question))\n" }
        }
        if !whenItCameTrue.isEmpty {
            s += "\nWhen it came true, or partly\n"
            for a in whenItCameTrue { s += "  \(a.day)  \(a.question): \(a.outcome!.body) (\(a.outcome!.fulfilled.rawValue), as \(a.position))\n" }
        }
        s += "\nEvery reading\n"
        for a in appearances {
            var line = "  \(a.day)  \(a.position)"
            if let o = a.orientation, o == .reversed { line += ", reversed" }
            if !a.changingLines.isEmpty { line += ", lines \(a.changingLines.map(String.init).joined(separator: " "))" }
            line += "  \(a.question)"
            if let o = a.outcome { line += "  → \(o.fulfilled.rawValue)" }
            s += line + "\n"
        }
        return s
    }
}
