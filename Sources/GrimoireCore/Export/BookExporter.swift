import Foundation

/// What goes into a printed book: a saved selection plus how it is split into chapters.
/// The look lives separately in a `BookDesign`, so one selection prints in any design.
public struct BookSpec: Codable, Hashable, Sendable {
    public enum Grouping: String, Codable, CaseIterable, Sendable { case month, week, type, tag, deck, card, none }

    public var title: String
    public var subtitle: String?
    /// Inclusive yyyy-MM-dd bounds, compared with each record's own local day.
    public var from: String?
    public var to: String?
    /// Empty = all types. `.divination` selects readings (Inquiries).
    public var types: [EntryType]
    /// Any of these tags, children included. Empty = no tag filter.
    public var tags: [TagPath]
    /// Readings that used one of these decks. Non-reading entries are dropped when set.
    public var decks: [String]
    /// Readings that drew one of these cards (`cups-03` or `rws-tarot/cups-03`).
    public var cards: [String]
    public var grouping: Grouping
    public var includeTranscripts: Bool

    public init(title: String = "Grimoire", subtitle: String? = nil, from: String? = nil, to: String? = nil, types: [EntryType] = [],
                tags: [TagPath] = [], decks: [String] = [], cards: [String] = [], grouping: Grouping = .month, includeTranscripts: Bool = false) {
        self.title = title; self.subtitle = subtitle; self.from = from; self.to = to; self.types = types
        self.tags = tags; self.decks = decks; self.cards = cards; self.grouping = grouping; self.includeTranscripts = includeTranscripts
    }
}

/// `book.json`: everything a design template needs, already resolved (card names, hexagram
/// names, date labels), so templates only lay out pages and never look anything up.
public struct BookDocument: Codable, Equatable, Sendable {
    public static let formatVersion = 1

    public var formatVersion: Int
    public var title: String
    public var subtitle: String?
    public var period: String?
    public var generatedOn: String
    public var counts: Counts
    public var chapters: [Chapter]
    public var cardIndex: [IndexEntry]
    public var hexagramIndex: [IndexEntry]
    /// Book-relative image paths the writer must copy in, mapped from attachment-relative sources.
    public var images: [String: String]

    public struct Counts: Codable, Equatable, Sendable { public var entries: Int; public var readings: Int }

    public struct Chapter: Codable, Equatable, Sendable {
        public var key: String
        public var title: String
        public var items: [Item]
    }

    public struct Item: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case entry, reading }
        public var id: String
        public var kind: Kind
        public var type: String
        public var typeLabel: String
        public var day: String
        public var dateLabel: String
        public var time: String
        public var title: String
        public var body: String
        public var tags: [String]
        public var fields: [Field]
        public var timing: Timing?
        public var physical: String?
        public var images: [String]
        public var transcript: String?
        // readings
        public var question: String?
        public var divinations: [Divination]
        public var synthesis: String?
        public var outcomes: [OutcomeLine]
    }

    public struct Field: Codable, Equatable, Sendable { public var label: String; public var value: String }

    public struct Timing: Codable, Equatable, Sendable {
        public var moonPhase: String
        public var moonSign: String
        public var moonIllumination: Int
        public var sunSign: String
        public var planetaryDay: String?
        public var planetaryHour: String?
    }

    public struct Divination: Codable, Equatable, Sendable {
        public var system: String
        public var deck: String?
        public var spread: String?
        public var method: String?
        public var notes: String?
        public var draws: [DrawLine]
        public var cast: Cast?
    }

    public struct DrawLine: Codable, Equatable, Sendable {
        public var position: String
        public var card: String
        public var reversed: Bool
        public var notes: String?
    }

    public struct Cast: Codable, Equatable, Sendable {
        /// Line values bottom to top (6, 7, 8, 9).
        public var lines: [Int]
        public var changing: [Int]
        public var primary: Hexagram
        public var resulting: Hexagram?
    }

    public struct Hexagram: Codable, Equatable, Sendable { public var number: Int; public var name: String; public var pinyin: String }

    public struct OutcomeLine: Codable, Equatable, Sendable {
        public var day: String
        public var fulfilled: String
        public var daysAfter: Int
        public var body: String
    }

    /// One card or hexagram and the items it appears in, for the back-of-book index.
    public struct IndexEntry: Codable, Equatable, Sendable {
        public var key: String
        public var label: String
        public var group: String
        public var items: [String]
    }

    public func json() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(self)
    }
}

/// Builds a `BookDocument` from the store. Deterministic: the same data, spec and
/// `generatedOn` give byte-identical `book.json`.
public struct BookExporter: Sendable {
    public let library: DefinitionLibrary
    public init(library: DefinitionLibrary) { self.library = library }

    /// One selected record before chapters are cut.
    struct Piece {
        var item: BookDocument.Item
        var instant: Date
        var zone: TimeZone
        var tags: [TagPath]
        var decks: [String]
        /// `deck/card` keys drawn.
        var cards: [String]
        var hexagrams: [Int]
    }

    /// - Parameter attachmentExists: whether an attachment-relative path can be copied into the book;
    ///   images that can't are left out rather than breaking the layout.
    public func book(_ data: GrimoireData, spec: BookSpec, generatedOn: String, attachmentExists: (String) -> Bool = { _ in false }) -> BookDocument {
        var images: [String: String] = [:]
        func image(_ a: Attachment?) -> String? {
            guard let a, a.kind == .image, attachmentExists(a.path) else { return nil }
            let name = "images/" + a.path.replacingOccurrences(of: "/", with: "-")
            images[name] = a.path
            return name
        }
        let volumes = Dictionary(uniqueKeysWithValues: data.volumes.map { ($0.id, $0.name) })
        func physical(_ p: PhysicalRef?) -> String? {
            guard let p else { return nil }
            return "\(volumes[p.volumeId] ?? "Volume"), p. \(p.page)"
        }

        var pieces: [Piece] = []
        let inquiryIds = Set(data.inquiries.map(\.id))
        let wantReadings = spec.types.isEmpty || spec.types.contains(.divination)
        let readingsOnly = !spec.decks.isEmpty || !spec.cards.isEmpty

        if !readingsOnly {
            for e in data.entries where e.status == .filed {
                // A confirmed reading files both an entry and its Inquiry; print it once, as the reading.
                if e.type == .divination, let i = e.inquiryId, inquiryIds.contains(i) { continue }
                guard spec.types.isEmpty || spec.types.contains(e.type) else { continue }
                var item = Self.blank(id: e.id.string, kind: .entry, type: e.type.rawValue, at: e.occurredAt)
                // Untitled entries print without a heading rather than repeating their first line.
                item.title = e.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                item.body = e.body
                item.tags = e.tags.map(\.path)
                item.fields = fields(e)
                item.timing = e.timing.map(Self.timing)
                item.physical = physical(e.physicalRef)
                item.images = ([e.physicalRef?.photo] + e.attachments.map { Optional($0) }).compactMap(image)
                if spec.includeTranscripts, let t = e.transcript, !t.isEmpty, t != e.body { item.transcript = t }
                pieces.append(Piece(item: item, instant: e.occurredAt.instant, zone: e.occurredAt.zone, tags: e.tags, decks: [], cards: [], hexagrams: []))
            }
        }
        if wantReadings {
            for i in data.inquiries {
                var item = Self.blank(id: i.id.string, kind: .reading, type: EntryType.divination.rawValue, at: i.askedAt)
                item.typeLabel = "Reading"
                item.title = i.question
                item.question = i.question
                item.body = i.context
                let tags = i.tags + (i.category.map { [$0] } ?? []) + i.divinations.flatMap { $0.draws.flatMap(\.tags) }
                item.tags = i.tags.map(\.path)
                item.timing = i.timing.map(Self.timing)
                item.physical = physical(i.physicalRef)
                item.images = [i.physicalRef?.photo].compactMap(image)
                item.synthesis = i.synthesis?.body
                item.outcomes = i.outcomes.map {
                    BookDocument.OutcomeLine(day: $0.recordedAt.day, fulfilled: $0.fulfilled.rawValue, daysAfter: i.daysAfter($0), body: $0.body)
                }
                var decks: [String] = [], cards: [String] = [], hexagrams: [Int] = []
                for d in i.divinations.sorted(by: { $0.order < $1.order }) {
                    let deck = d.deckId.flatMap(library.deck)
                    let spread = d.spreadId.flatMap(library.spread)
                    var line = BookDocument.Divination(system: d.system.rawValue, deck: deck?.name ?? d.deckId, spread: spread?.name ?? d.spreadId,
                                                       method: d.method, notes: d.notes, draws: [], cast: nil)
                    if let id = d.deckId { decks.append(id) }
                    for w in d.draws {
                        line.draws.append(BookDocument.DrawLine(position: spread?.label(for: w.positionKey) ?? w.positionKey, card: deck?.card(w.cardId)?.name ?? w.cardId,
                                                                reversed: w.orientation == .reversed, notes: w.notes))
                        cards.append("\(d.deckId ?? "")/\(w.cardId)")
                    }
                    if let c = d.cast {
                        let p = c.primaryHexagram(in: library.yijing)
                        let r = c.resultingHexagram(in: library.yijing)
                        line.cast = BookDocument.Cast(lines: c.lines, changing: c.changingLines, primary: hexagram(p), resulting: r.map(hexagram))
                        hexagrams.append(p)
                        if let r { hexagrams.append(r) }
                    }
                    item.divinations.append(line)
                }
                pieces.append(Piece(item: item, instant: i.askedAt.instant, zone: i.askedAt.zone, tags: tags, decks: decks, cards: cards, hexagrams: hexagrams))
            }
        }

        pieces = pieces.filter { p in
            if let f = spec.from, p.item.day < f { return false }
            if let t = spec.to, p.item.day > t { return false }
            if !spec.tags.isEmpty, !p.tags.contains(where: { t in spec.tags.contains { t.isUnder($0) } }) { return false }
            if !spec.decks.isEmpty, !p.decks.contains(where: spec.decks.contains) { return false }
            if !spec.cards.isEmpty, !p.cards.contains(where: { k in spec.cards.contains { k == $0 || k.hasSuffix("/" + $0) } }) { return false }
            return true
        }
        pieces.sort { ($0.instant, $0.item.id) < ($1.instant, $1.item.id) }
        images = images.filter { name, _ in pieces.contains { $0.item.images.contains(name) } }

        return BookDocument(
            formatVersion: BookDocument.formatVersion, title: spec.title, subtitle: spec.subtitle,
            period: period(spec, pieces), generatedOn: generatedOn,
            counts: .init(entries: pieces.filter { $0.item.kind == .entry }.count, readings: pieces.filter { $0.item.kind == .reading }.count),
            chapters: chapters(pieces, spec: spec), cardIndex: cardIndex(pieces), hexagramIndex: hexagramIndex(pieces), images: images)
    }

    // MARK: Chapters

    func chapters(_ pieces: [Piece], spec: BookSpec) -> [BookDocument.Chapter] {
        // key → (sort key, title, items); an item can sit in several tag, deck or card chapters.
        var groups: [String: (sort: String, title: String, items: [BookDocument.Item])] = [:]
        func put(_ key: String, sort: String, title: String, _ item: BookDocument.Item) {
            groups[key, default: (sort, title, [])].items.append(item)
        }
        let typeOrder = Dictionary(uniqueKeysWithValues: EntryType.allCases.enumerated().map { ($1.rawValue, $0) })
        for p in pieces {
            switch spec.grouping {
            case .none:
                put("all", sort: "", title: spec.title, p.item)
            case .month:
                let key = String(p.item.day.prefix(7))
                put(key, sort: key, title: Self.format(p.instant, zone: p.zone, "MMMM yyyy"), p.item)
            case .week:
                var cal = Calendar(identifier: .iso8601)
                cal.timeZone = p.zone
                let start = cal.dateInterval(of: .weekOfYear, for: p.instant)?.start ?? p.instant
                let key = GrimoireDateFormat.day(start, in: p.zone)
                put(key, sort: key, title: "Week of " + Self.format(start, zone: p.zone, "d MMMM yyyy"), p.item)
            case .type:
                let order = String(format: "%02d", typeOrder[p.item.type] ?? 99)
                put(p.item.type, sort: order, title: Self.plural(p.item.type), p.item)
            case .tag:
                let wanted: Set<TagPath> = spec.tags.isEmpty
                    ? Set(p.tags.compactMap { t in t.components.first.map { TagPath($0) } })
                    : Set(spec.tags.filter { w in p.tags.contains { $0.isUnder(w) } })
                for t in wanted { put(t.path, sort: t.path, title: t.path, p.item) }
                if wanted.isEmpty { put("~untagged", sort: "~", title: "Untagged", p.item) }
            case .deck:
                for d in Set(p.decks) { put(d, sort: library.deck(d)?.name ?? d, title: library.deck(d)?.name ?? d, p.item) }
                if p.decks.isEmpty, !p.hexagrams.isEmpty { put("~yijing", sort: "~", title: library.yijing.name, p.item) }
            case .card:
                for k in Set(p.cards) where spec.cards.isEmpty || spec.cards.contains(where: { k == $0 || k.hasSuffix("/" + $0) }) {
                    let parts = k.split(separator: "/", maxSplits: 1).map(String.init)
                    let name = library.deck(parts[0])?.card(parts.last ?? "")?.name ?? k
                    put(k, sort: name, title: name, p.item)
                }
            }
        }
        return groups.sorted { ($0.value.sort, $0.key) < ($1.value.sort, $1.key) }
            .map { BookDocument.Chapter(key: $0.key, title: $0.value.title, items: $0.value.items) }
    }

    func cardIndex(_ pieces: [Piece]) -> [BookDocument.IndexEntry] {
        var hits: [String: [String]] = [:]
        for p in pieces { for k in Set(p.cards) { hits[k, default: []].append(p.item.id) } }
        return hits.map { k, ids in
            let parts = k.split(separator: "/", maxSplits: 1).map(String.init)
            let deck = library.deck(parts[0])
            return BookDocument.IndexEntry(key: k, label: deck?.card(parts.last ?? "")?.name ?? k, group: deck?.name ?? parts[0], items: ids)
        }.sorted { ($0.group, $0.label, $0.key) < ($1.group, $1.label, $1.key) }
    }

    func hexagramIndex(_ pieces: [Piece]) -> [BookDocument.IndexEntry] {
        var hits: [Int: [String]] = [:]
        for p in pieces { for n in Set(p.hexagrams) { hits[n, default: []].append(p.item.id) } }
        return hits.keys.sorted().map { n in
            let h = hexagram(n)
            return BookDocument.IndexEntry(key: String(n), label: "\(n). \(h.name)", group: library.yijing.name, items: hits[n]!)
        }
    }

    // MARK: Pieces

    func hexagram(_ n: Int) -> BookDocument.Hexagram {
        let h = library.yijing.hexagram(n)
        return BookDocument.Hexagram(number: n, name: h?.name ?? "Hexagram \(n)", pinyin: h?.pinyin ?? "")
    }

    func period(_ spec: BookSpec, _ pieces: [Piece]) -> String? {
        guard let lo = spec.from ?? pieces.first?.item.day, let hi = spec.to ?? pieces.last?.item.day else { return nil }
        func label(_ day: String) -> String {
            guard let d = GrimoireDateFormat.parseISO(day + "T12:00:00Z") else { return day }
            return Self.format(d, zone: TimeZone(identifier: "UTC")!, "d MMMM yyyy")
        }
        return lo == hi ? label(lo) : "\(label(lo)) – \(label(hi))"
    }

    /// Type-specific fields in the order the spec lists them, as label/value pairs.
    func fields(_ e: Entry) -> [BookDocument.Field] {
        let f = e.fields
        func tags(_ t: [TagPath]?) -> String? { t.flatMap { $0.isEmpty ? nil : $0.map(\.path).joined(separator: ", ") } }
        func scale(_ v: Int?) -> String? { v.map { "\($0) of 5" } }
        func yes(_ v: Bool?) -> String? { v.map { $0 ? "yes" : "no" } }
        let all: [(String, String?)] = [
            ("Intention", f.intention), ("Tools", f.tools.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") }), ("Location", f.location),
            ("Technique", f.technique), ("Duration", f.durationMin.map { "\($0) min" }), ("Depth", scale(f.depth)),
            ("Setting", f.setting), ("Beings", tags(f.beings)), ("Places", tags(f.places)), ("Clarity", scale(f.clarity)),
            ("Being", f.being?.path), ("Nature", f.nature), ("Observed in", f.observedIn), ("Domain", f.domain),
            ("Lucid", yes(f.lucid)), ("Recurring", yes(f.recurring)), ("Figures", tags(f.figures)),
            ("Steps", f.steps), ("Observations", f.observations), ("Communication", f.communication),
            ("Interpretation", f.interpretation), ("Result", f.result), ("Resolved", yes(f.resolved)), ("Notes", e.extraNotes),
        ]
        return all.compactMap { k, v in
            guard let v = v?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
            return BookDocument.Field(label: k, value: v)
        }
    }

    static func blank(id: String, kind: BookDocument.Item.Kind, type: String, at z: ZonedDate) -> BookDocument.Item {
        BookDocument.Item(id: id, kind: kind, type: type, typeLabel: type.capitalized, day: z.day,
                          dateLabel: format(z.instant, zone: z.zone, "EEEE d MMMM yyyy"), time: format(z.instant, zone: z.zone, "HH:mm"),
                          title: "", body: "", tags: [], fields: [], timing: nil, physical: nil, images: [], transcript: nil,
                          question: nil, divinations: [], synthesis: nil, outcomes: [])
    }

    static func timing(_ t: TimingContext) -> BookDocument.Timing {
        BookDocument.Timing(moonPhase: t.moonPhase.rawValue, moonSign: t.moonSign.rawValue, moonIllumination: t.moonIllumination,
                            sunSign: t.sunSign.rawValue, planetaryDay: t.planetaryDay?.rawValue, planetaryHour: t.planetaryHour?.rawValue)
    }

    static func plural(_ type: String) -> String {
        switch type {
        case "divination": return "Readings"
        case "journal": return "Journal"
        case "insight": return "Insights"
        default: return type.capitalized + "s"
        }
    }

    static func format(_ d: Date, zone: TimeZone, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = zone
        f.dateFormat = pattern
        return f.string(from: d)
    }
}
