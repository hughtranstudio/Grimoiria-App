import Foundation

/// A value and how often it came up.
public struct Tally<Key: Hashable & Sendable>: Hashable, Sendable {
    public var key: Key
    public var count: Int
    public init(_ key: Key, _ count: Int) { self.key = key; self.count = count }
}

/// One card in one reading.
public struct CardOccurrence: Hashable, Sendable {
    public var inquiryId: ULID
    public var deckId: String
    public var cardId: String
    public var positionKey: String
    public var orientation: Orientation
    public var askedAt: ZonedDate
}

/// One hexagram in one reading: the cast itself, or the one it changes into.
public struct HexagramOccurrence: Hashable, Sendable {
    public enum Role: String, Codable, Sendable { case primary, resulting }
    public var inquiryId: ULID
    public var number: Int
    public var role: Role
    public var changingLines: [Int]
    public var askedAt: ZonedDate
}

/// A card or hexagram that kept coming back in separate readings close together.
public struct Recurrence: Hashable, Sendable {
    public enum Symbol: Hashable, Sendable {
        case card(deckId: String, cardId: String)
        case hexagram(Int)
    }
    public var symbol: Symbol
    public var inquiryIds: [ULID]
    /// First and last day it came up in this run.
    public var from: String
    public var to: String
}

/// What a timing table groups by.
public enum TimingDimension: String, CaseIterable, Sendable {
    case moonPhase = "moon-phase", moonSign = "moon-sign", sunSign = "sun-sign", planetaryDay = "planetary-day", planetaryHour = "planetary-hour"

    /// Every value in its natural order, so empty rows show as zero.
    public var values: [String] {
        switch self {
        case .moonPhase: return ["new", "waxing-crescent", "first-quarter", "waxing-gibbous", "full", "waning-gibbous", "last-quarter", "waning-crescent"]
        case .moonSign, .sunSign: return ZodiacSign.allCases.map(\.rawValue)
        case .planetaryDay: return Planet.dayRulers.map(\.rawValue)
        case .planetaryHour: return Planet.chaldean.map(\.rawValue)
        }
    }

    public func value(_ t: TimingContext) -> String? {
        switch self {
        case .moonPhase: return t.moonPhase.rawValue
        case .moonSign: return t.moonSign.rawValue
        case .sunSign: return t.sunSign.rawValue
        case .planetaryDay: return t.planetaryDay?.rawValue
        case .planetaryHour: return t.planetaryHour?.rawValue
        }
    }
}

/// How the readings held up, from their outcomes.
public struct OutcomeStats: Hashable, Sendable {
    /// Each reading counted once, by its latest outcome.
    public var byFulfilled: [Outcome.Fulfilled: Int] = [:]
    /// Readings with at least one outcome / all readings.
    public var answered = 0
    public var total = 0
    /// Days from asking to the first outcome, middle value.
    public var medianDaysToFirstOutcome: Int?

    /// Share of answered readings that came true (yes = 1, partly = ½), unclear left out.
    public var hitRate: Double? {
        let yes = byFulfilled[.yes] ?? 0, partly = byFulfilled[.partly] ?? 0, no = byFulfilled[.no] ?? 0
        let n = yes + partly + no
        return n == 0 ? nil : (Double(yes) + Double(partly) / 2) / Double(n)
    }
}

/// Counts over filed records for pattern-spotting (spec "analytics"): what comes up, when, and how
/// it turned out. Everything is computed from the data on demand; nothing here is stored.
public struct Patterns: Sendable {
    public let data: GrimoireData
    public let library: DefinitionLibrary
    public let cards: [CardOccurrence]
    public let hexagrams: [HexagramOccurrence]
    /// Inquiries and filed entries inside the window.
    public let inquiries: [Inquiry]
    public let entries: [Entry]

    /// `from` and `to` are inclusive instants; nil means no limit.
    public init(data: GrimoireData, library: DefinitionLibrary, from: Date? = nil, to: Date? = nil) {
        func inside(_ d: Date) -> Bool { (from.map { d >= $0 } ?? true) && (to.map { d <= $0 } ?? true) }
        self.data = data
        self.library = library
        inquiries = data.inquiries.filter { inside($0.askedAt.instant) }.sorted { $0.askedAt.instant < $1.askedAt.instant }
        // Divination entries stand for their Inquiry; leave them out so readings aren't counted twice.
        entries = data.entries.filter { $0.status == .filed && inside($0.occurredAt.instant) && !($0.type == .divination && $0.inquiryId != nil) }
        var cards: [CardOccurrence] = [], hexagrams: [HexagramOccurrence] = []
        for i in inquiries {
            for d in i.divinations.sorted(by: { $0.order < $1.order }) {
                if let deck = d.deckId {
                    for w in d.draws {
                        cards.append(CardOccurrence(inquiryId: i.id, deckId: deck, cardId: w.cardId, positionKey: w.positionKey,
                                                    orientation: w.orientation, askedAt: d.performedAt))
                    }
                }
                if let c = d.cast, let n = library.yijing.number(forLines: c.primaryLines) {
                    hexagrams.append(HexagramOccurrence(inquiryId: i.id, number: n, role: .primary, changingLines: c.changingLines, askedAt: d.performedAt))
                    if let r = c.resultingHexagram(in: library.yijing) {
                        hexagrams.append(HexagramOccurrence(inquiryId: i.id, number: r, role: .resulting, changingLines: [], askedAt: d.performedAt))
                    }
                }
            }
        }
        self.cards = cards
        self.hexagrams = hexagrams
    }

    static func tally<K: Hashable & Comparable & Sendable>(_ keys: [K]) -> [Tally<K>] {
        Dictionary(keys.map { ($0, 1) }, uniquingKeysWith: +).map { Tally($0.key, $0.value) }
            .sorted { ($1.count, $0.key) < ($0.count, $1.key) }
    }

    // MARK: Cards

    /// Decks that have draws in the window, most used first.
    public var decksUsed: [Tally<String>] { Self.tally(cards.map(\.deckId)) }

    /// How often each card was drawn, most first. `deckId` nil counts every deck ("deck/card" keys).
    public func cardCounts(deckId: String? = nil) -> [Tally<String>] {
        Self.tally(cards.filter { deckId == nil || $0.deckId == deckId }.map { deckId == nil ? "\($0.deckId)/\($0.cardId)" : $0.cardId })
    }

    /// Draws grouped by a deck attribute such as suit, element, arcana or number. Cards without it count as "none".
    public func attributeCounts(deckId: String, attribute: String) -> [Tally<String>] {
        let deck = library.deck(deckId)
        return Self.tally(cards.filter { $0.deckId == deckId }.map { deck?.card($0.cardId)?.attributes[attribute]?.description ?? "none" })
    }

    /// Share of draws that were reversed, for decks that allow reversals.
    public func reversedShare(deckId: String) -> Double? {
        let draws = cards.filter { $0.deckId == deckId && $0.orientation != .na }
        guard !draws.isEmpty, library.deck(deckId)?.reversalsAllowed != false else { return nil }
        return Double(draws.filter { $0.orientation == .reversed }.count) / Double(draws.count)
    }

    // MARK: Yi Jing

    public func hexagramCounts(role: HexagramOccurrence.Role? = .primary) -> [Tally<Int>] {
        Self.tally(hexagrams.filter { role == nil || $0.role == role }.map(\.number))
    }

    /// How often each line position (1 bottom … 6 top) was a changing line.
    public var changingLineCounts: [Tally<Int>] {
        let lines = hexagrams.filter { $0.role == .primary }.flatMap(\.changingLines)
        return (1...6).map { n in Tally(n, lines.filter { $0 == n }.count) }
    }

    // MARK: Recurrence

    /// Cards and hexagrams that came up in at least `minReadings` separate readings with no more than
    /// `withinDays` between one reading and the next. Longest runs first.
    public func recurrences(withinDays: Int = 30, minReadings: Int = 2) -> [Recurrence] {
        var hits: [Recurrence.Symbol: [(Date, String, ULID)]] = [:]
        for c in cards { hits[.card(deckId: c.deckId, cardId: c.cardId), default: []].append((c.askedAt.instant, c.askedAt.day, c.inquiryId)) }
        for h in hexagrams where h.role == .primary { hits[.hexagram(h.number), default: []].append((h.askedAt.instant, h.askedAt.day, h.inquiryId)) }
        var out: [Recurrence] = []
        let gap = TimeInterval(withinDays) * 86_400
        for (symbol, list) in hits {
            // One mark per reading, in time order, then split into runs wherever the gap is too long.
            var seen = Set<ULID>()
            let marks = list.sorted { $0.0 < $1.0 }.filter { seen.insert($0.2).inserted }
            var run: [(Date, String, ULID)] = []
            func close() {
                if run.count >= minReadings { out.append(Recurrence(symbol: symbol, inquiryIds: run.map(\.2), from: run.first!.1, to: run.last!.1)) }
                run = []
            }
            for m in marks {
                if let last = run.last, m.0.timeIntervalSince(last.0) > gap { close() }
                run.append(m)
            }
            close()
        }
        return out.sorted { ($1.inquiryIds.count, $0.from, "\($0.symbol)") < ($0.inquiryIds.count, $1.from, "\($1.symbol)") }
    }

    // MARK: Timing

    /// Records per timing value, every value listed (zero when none). `types` limits entries;
    /// `includeReadings` adds Inquiries by when they were asked.
    public func timing(_ dimension: TimingDimension, types: Set<EntryType> = [], includeReadings: Bool = true) -> [Tally<String>] {
        var values: [String] = entries.filter { types.isEmpty || types.contains($0.type) }.compactMap { $0.timing.flatMap(dimension.value) }
        if includeReadings { values += inquiries.compactMap { $0.timing.flatMap(dimension.value) } }
        let counts = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
        return dimension.values.map { Tally($0, counts[$0] ?? 0) }
    }

    /// Cards drawn under each timing value, for one card: does it favour a moon phase or a day?
    public func timing(_ dimension: TimingDimension, forCard cardId: String, deckId: String) -> [Tally<String>] {
        let asked = Set(cards.filter { $0.deckId == deckId && $0.cardId == cardId }.map(\.inquiryId))
        let values = inquiries.filter { asked.contains($0.id) }.compactMap { $0.timing.flatMap(dimension.value) }
        let counts = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
        return dimension.values.map { Tally($0, counts[$0] ?? 0) }
    }

    // MARK: Practice

    /// Entries per type, most first.
    public var typeCounts: [Tally<String>] { Self.tally(entries.map(\.type.rawValue)) }

    /// Entries and readings per month (yyyy-MM), oldest first.
    public var monthly: [Tally<String>] {
        let months = entries.map { String($0.occurredAt.day.prefix(7)) } + inquiries.map { String($0.askedAt.day.prefix(7)) }
        return Dictionary(months.map { ($0, 1) }, uniquingKeysWith: +).map { Tally($0.key, $0.value) }.sorted { $0.key < $1.key }
    }

    /// How often each tag is used, a parent counting its children's uses too.
    public var tagCounts: [Tally<TagPath>] {
        var counts: [TagPath: Int] = [:]
        let tagged = entries.map(\.tags) + inquiries.map { $0.tags + ($0.category.map { [$0] } ?? []) }
        for tags in tagged {
            var seen = Set<TagPath>()
            for t in tags {
                var node: TagPath? = t
                while let n = node {
                    if seen.insert(n).inserted { counts[n, default: 0] += 1 }
                    node = n.parent
                }
            }
        }
        return counts.map { Tally($0.key, $0.value) }.sorted { $0.key < $1.key }
    }

    // MARK: Outcomes

    public func outcomes(system: Divination.System? = nil, deckId: String? = nil) -> OutcomeStats {
        let readings = inquiries.filter { i in
            (system == nil || i.divinations.contains { $0.system == system }) && (deckId == nil || i.divinations.contains { $0.deckId == deckId })
        }
        var s = OutcomeStats()
        s.total = readings.count
        var days: [Int] = []
        for i in readings {
            guard let last = i.outcomes.last, let first = i.outcomes.first else { continue }
            s.answered += 1
            s.byFulfilled[last.fulfilled, default: 0] += 1
            days.append(i.daysAfter(first))
        }
        days.sort()
        s.medianDaysToFirstOutcome = days.isEmpty ? nil : days[days.count / 2]
        return s
    }

    /// Outcome tallies split by how confident the synthesis was (1–5): does confidence track results?
    public var outcomesByConfidence: [Int: OutcomeStats] {
        var out: [Int: OutcomeStats] = [:]
        for i in inquiries {
            guard let c = i.synthesis?.confidence else { continue }
            out[c, default: OutcomeStats()].total += 1
            guard let last = i.outcomes.last else { continue }
            out[c]!.answered += 1
            out[c]!.byFulfilled[last.fulfilled, default: 0] += 1
        }
        return out
    }

    // MARK: Browse

    /// Readings that drew this card, newest first.
    public func readings(withCard cardId: String, deckId: String) -> [ULID] {
        var seen = Set<ULID>()
        return cards.filter { $0.deckId == deckId && $0.cardId == cardId }.sorted { $0.askedAt.instant > $1.askedAt.instant }
            .map(\.inquiryId).filter { seen.insert($0).inserted }
    }

    /// Readings that cast (or changed into) this hexagram, newest first.
    public func readings(withHexagram number: Int, role: HexagramOccurrence.Role? = nil) -> [ULID] {
        var seen = Set<ULID>()
        return hexagrams.filter { $0.number == number && (role == nil || $0.role == role) }.sorted { $0.askedAt.instant > $1.askedAt.instant }
            .map(\.inquiryId).filter { seen.insert($0).inserted }
    }
}
