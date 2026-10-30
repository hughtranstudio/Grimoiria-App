import Foundation

/// Full-text + tag + field filters (spec §10.7), and "where did I write about X" (spec §7).
public struct SearchQuery: Sendable {
    public var text: String?
    /// Matches the tag or any child of it.
    public var tags: [TagPath] = []
    public var types: Set<EntryType> = []
    public var volumeId: ULID?
    public var pages: ClosedRange<Int>?
    public var from: Date?
    public var to: Date?
    public var includeInbox = false
    /// Readings that drew this card, as "deckId/cardId". Entries never match.
    public var card: String?
    /// Readings that cast this hexagram or changed into it. Entries never match.
    public var hexagram: Int?

    public init(text: String? = nil, tags: [TagPath] = [], types: Set<EntryType> = [], volumeId: ULID? = nil,
                pages: ClosedRange<Int>? = nil, from: Date? = nil, to: Date? = nil, includeInbox: Bool = false) {
        self.text = text; self.tags = tags; self.types = types; self.volumeId = volumeId
        self.pages = pages; self.from = from; self.to = to; self.includeInbox = includeInbox
    }
}

public enum SearchHit: Sendable, Equatable {
    case entry(ULID)
    case inquiry(ULID)
    public var id: ULID { switch self { case .entry(let i), .inquiry(let i): return i } }
}

public extension GrimoireRepository {
    func search(_ q: SearchQuery, library: DefinitionLibrary? = nil) -> [SearchHit] {
        let needle = q.text.map(Tokenizer.fold)?.trimmingCharacters(in: .whitespaces)
        func textMatch(_ haystacks: [String?]) -> Bool {
            guard let n = needle, !n.isEmpty else { return true }
            return haystacks.contains { $0.map(Tokenizer.fold)?.contains(n) ?? false }
        }
        func tagMatch(_ tags: [TagPath]) -> Bool {
            q.tags.isEmpty || q.tags.allSatisfy { want in tags.contains { $0.isUnder(want) } }
        }
        func physMatch(_ p: PhysicalRef?) -> Bool {
            guard q.volumeId != nil || q.pages != nil else { return true }
            guard let p else { return false }
            if let v = q.volumeId, p.volumeId != v { return false }
            if let r = q.pages, !p.overlaps(r) { return false }
            return true
        }
        func dateMatch(_ d: Date) -> Bool { (q.from.map { d >= $0 } ?? true) && (q.to.map { d <= $0 } ?? true) }

        var hits: [(Date, SearchHit)] = []
        let readingsOnly = q.card != nil || q.hexagram != nil
        for e in data.entries where !readingsOnly && (q.includeInbox || e.status == .filed) {
            guard q.types.isEmpty || q.types.contains(e.type) else { continue }
            let f = e.fields
            let observed = e.session?.observations ?? []
            guard textMatch([e.title, e.body, e.extraNotes, e.transcript, f.intention, f.observations, f.interpretation, f.communication, f.result, f.steps,
                             e.session?.outcome] + observed.map(\.text))
                , tagMatch(e.tags + observed.flatMap(\.tags)), physMatch(e.physicalRef), dateMatch(e.occurredAt.instant) else { continue }
            hits.append((e.occurredAt.instant, .entry(e.id)))
        }
        if q.types.isEmpty || q.types.contains(.divination) {
            for i in data.inquiries {
                if let card = q.card, !i.divinations.contains(where: { d in d.draws.contains { "\(d.deckId ?? "")/\($0.cardId)" == card } }) { continue }
                if let n = q.hexagram {
                    guard let library, i.divinations.contains(where: { d in
                        d.cast.map { $0.primaryHexagram(in: library.yijing) == n || $0.resultingHexagram(in: library.yijing) == n } ?? false
                    }) else { continue }
                }
                var cardNames: [String?] = []
                if let library {
                    for d in i.divinations {
                        if let deck = d.deckId.flatMap(library.deck) { cardNames += d.draws.map { deck.card($0.cardId)?.name } }
                        if let c = d.cast { cardNames.append(library.yijing.hexagram(c.primaryHexagram(in: library.yijing))?.name) }
                    }
                }
                guard textMatch([i.question, i.context, i.synthesis?.body] + i.outcomes.map(\.body) + cardNames),
                      tagMatch(i.tags + (i.category.map { [$0] } ?? []) + i.divinations.flatMap { $0.draws.flatMap(\.tags) }),
                      physMatch(i.physicalRef), dateMatch(i.askedAt.instant) else { continue }
                hits.append((i.askedAt.instant, .inquiry(i.id)))
            }
        }
        return hits.sorted { $0.0 > $1.0 }.map(\.1)
    }
}
