import Foundation

/// A record waiting in the Inbox. Parsed items never file themselves: only `confirm` turns a
/// draft into filed records (spec §12 step 3a, Hugh's requirement).
public struct InboxItem: Codable, Hashable, Sendable, Identifiable {
    public var id: ULID { entry.id }
    /// The Entry, with `status == .inbox`.
    public var entry: Entry
    /// Parsed draws/casts awaiting confirmation; nil when nothing divinatory was heard.
    public var draft: DraftReading?
    /// Where the item came from: "phone:<device>", "import:<file>", …
    public var source: String

    public init(entry: Entry, draft: DraftReading?, source: String) {
        precondition(entry.status == .inbox, "Inbox items must have status inbox")
        self.entry = entry
        self.draft = draft
        self.source = source
    }
}

/// One correction made during confirm, logged so the parser's synonym lists can improve.
public struct CorrectionLogEntry: Codable, Hashable, Sendable {
    public var field: String
    public var heard: String?
    public var proposed: String?
    public var corrected: String?
    public var deckId: String?
    public var at: Date
}

public struct ConfirmResult: Sendable {
    public var entry: Entry
    public var inquiry: Inquiry?
    public var corrections: [CorrectionLogEntry]
}

public enum ConfirmError: Error, Equatable, CustomStringConvertible {
    case unresolvedCard(divination: Int, draw: Int)
    case missingDeck(divination: Int)
    case invalidCast(divination: Int, String)
    case unknownCard(deck: String, card: String)

    public var description: String {
        switch self {
        case .unresolvedCard(let d, let i): return "Divination \(d + 1), card \(i + 1) has no card chosen"
        case .missingDeck(let d): return "Divination \(d + 1) has no deck chosen"
        case .invalidCast(let d, let why): return "Divination \(d + 1): \(why)"
        case .unknownCard(let deck, let card): return "Card \(card) is not in deck \(deck)"
        }
    }
}

public enum Confirmation {
    /// Files an Inbox item. `corrected` is the draft as edited in the Inbox; the original
    /// `item.draft` is compared against it to build the correction log.
    public static func confirm(
        _ item: InboxItem,
        corrected: DraftReading?,
        entryType: EntryType? = nil,
        library: DefinitionLibrary,
        now: Date = Date()
    ) throws -> ConfirmResult {
        var entry = item.entry
        entry.status = .filed
        entry.updatedAt = now
        if let t = entryType { entry.type = t }

        var corrections: [CorrectionLogEntry] = []
        var inquiry: Inquiry?

        if let final = corrected, !final.divinations.isEmpty {
            var divinations: [Divination] = []
            for (di, d) in final.divinations.enumerated() {
                let original = item.draft?.divinations.indices.contains(di) == true ? item.draft!.divinations[di] : nil
                switch d.system {
                case .cards, .other:
                    guard let deckId = d.deckId.value else { throw ConfirmError.missingDeck(divination: di) }
                    let deck = library.deck(deckId)
                    if let o = original, o.deckId.value != deckId {
                        corrections.append(.init(field: "deck", heard: o.deckId.heard, proposed: o.deckId.value, corrected: deckId, deckId: nil, at: now))
                    }
                    var draws: [Draw] = []
                    let finalCards = Set(d.draws.compactMap(\.cardId.value))
                    var unusedOriginals = Array((original?.draws ?? []).enumerated())
                    for (wi, w) in d.draws.enumerated() {
                        guard let cardId = w.cardId.value else { throw ConfirmError.unresolvedCard(divination: di, draw: wi) }
                        if let deck, deck.status == .complete, deck.card(cardId) == nil {
                            throw ConfirmError.unknownCard(deck: deckId, card: cardId)
                        }
                        if let k = unusedOriginals.firstIndex(where: { $0.element.cardId.value == cardId }) {
                            // Same card kept (possibly moved): only orientation can have changed.
                            let ow = unusedOriginals.remove(at: k).element
                            if ow.orientation.value != w.orientation.value {
                                corrections.append(.init(field: "orientation", heard: ow.orientation.heard, proposed: ow.orientation.value?.rawValue, corrected: w.orientation.value?.rawValue, deckId: deckId, at: now))
                            }
                        } else if let k = unusedOriginals.firstIndex(where: { $0.offset == wi && !finalCards.contains($0.element.cardId.value ?? "") }) {
                            // A misheard card replaced in place: log heard → corrected for the synonym list.
                            let ow = unusedOriginals.remove(at: k).element
                            corrections.append(.init(field: "card", heard: ow.cardId.heard, proposed: ow.cardId.value, corrected: cardId, deckId: deckId, at: now))
                        } else {
                            corrections.append(.init(field: "card", heard: nil, proposed: nil, corrected: cardId, deckId: deckId, at: now))
                        }
                        let orientation = (deck?.reversalsAllowed == false) ? .upright : (w.orientation.value ?? .upright)
                        draws.append(Draw(cardId: cardId, positionKey: w.positionKey, orientation: orientation))
                    }
                    divinations.append(Divination(system: d.system, deckId: deckId, spreadId: d.spreadId.value ?? SpreadDefinition.freeformID,
                                                  performedAt: entry.occurredAt, order: di, draws: draws))
                case .yijing:
                    guard let lines = d.cast?.lines.value else { throw ConfirmError.invalidCast(divination: di, "no lines") }
                    let cast: YiJingCast
                    do { cast = try YiJingCast(lines: lines, method: d.cast?.method ?? .coins) }
                    catch { throw ConfirmError.invalidCast(divination: di, String(describing: error)) }
                    if let o = original?.cast, o.lines.value != lines {
                        corrections.append(.init(field: "yijing-lines", heard: o.lines.heard, proposed: o.lines.value.map { $0.map(String.init).joined() },
                                                 corrected: lines.map(String.init).joined(), deckId: nil, at: now))
                    }
                    divinations.append(Divination(system: .yijing, performedAt: entry.occurredAt, method: cast.method.rawValue, order: di, cast: cast))
                }
            }
            let question = final.question.value ?? item.draft?.question.value ?? entry.displayTitle
            var inq = Inquiry(id: ULID(date: entry.occurredAt.instant), question: question, askedAt: entry.occurredAt, context: entry.body, tags: entry.tags,
                              divinations: divinations, timing: entry.timing, createdAt: now)
            inq.physicalRef = entry.physicalRef
            entry.type = .divination
            entry.inquiryId = inq.id
            inquiry = inq
        }
        return ConfirmResult(entry: entry, inquiry: inquiry, corrections: corrections)
    }
}
