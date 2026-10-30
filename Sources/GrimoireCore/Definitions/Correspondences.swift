import Foundation

/// A table of correspondences (planets, signs, elements, trigrams) loaded from
/// `Definitions/correspondences.json`. Data, like decks: edit or add to the file, not the code.
public struct Correspondences: Codable, Hashable, Sendable {
    public struct Field: Codable, Hashable, Sendable {
        public var label: String
        public var values: [String]
    }

    public struct Entry: Codable, Hashable, Sendable, Identifiable {
        /// "planet:mars", "sign:aries", "element:fire", "trigram:qian".
        public var id: String
        public var kind: String
        public var name: String
        public var glyph: String?
        public var fields: [Field]
        public var related: [String]
        /// Element entries: the tarot suit that carries the element.
        public var suit: String?

        /// The part after the colon: "mars", "aries", "fire", "qian".
        public var key: String { String(id.split(separator: ":", maxSplits: 1).last ?? "") }

        public func values(_ label: String) -> [String] { fields.first { $0.label == label }?.values ?? [] }
    }

    public var id: String
    public var name: String
    public var version: Int
    public var source: String?
    public var entries: [Entry]

    public static let kinds = ["planet", "sign", "element", "trigram"]

    public func entry(_ id: String) -> Entry? { entries.first { $0.id == id } }

    /// Entries whose name, glyph or any value contains the text: "iron" finds Mars, "tuesday" Mars,
    /// "head" Aries and Qian. Name matches come first.
    public func search(_ text: String) -> [Entry] {
        let needle = Tokenizer.fold(text).trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return entries }
        func has(_ s: String) -> Bool { Tokenizer.fold(s).contains(needle) }
        let byName = entries.filter { has($0.name) || $0.glyph == text.trimmingCharacters(in: .whitespaces) }
        let byValue = entries.filter { e in !byName.contains(e) && e.fields.contains { $0.values.contains(where: has) } }
        return byName + byValue
    }

    /// Other entries naming this one in a field ("Rules: Aries" on Mars lists Mars under Aries).
    public func mentions(of entry: Entry) -> [Entry] {
        let name = Tokenizer.fold(entry.name)
        return entries.filter { e in
            e.id != entry.id && (e.related.contains(entry.id) || e.fields.contains { $0.values.contains { Tokenizer.fold($0) == name } })
        }
    }
}

public extension DefinitionLibrary {
    /// Cards a deck attributes to this planet, sign or element (its `attribution` attribute), and for
    /// an element the cards of its suit's aces as well, since the whole suit carries it.
    func cards(for entry: Correspondences.Entry) -> [(deck: DeckDefinition, card: DeckDefinition.Card)] {
        var out: [(DeckDefinition, DeckDefinition.Card)] = []
        for deck in decks where deck.status != .template {
            for card in deck.cards {
                if case .string(let a)? = card.attributes["attribution"], a.lowercased() == entry.key { out.append((deck, card)); continue }
                if let suit = entry.suit, case .string(let s)? = card.attributes["suit"], s == suit,
                   case .string(let rank)? = card.attributes["rank"], rank == "ace" { out.append((deck, card)) }
            }
        }
        return out
    }

    /// Hexagrams with this trigram below or above.
    func hexagrams(withTrigram id: String) -> [YiJingDefinition.Hexagram] {
        yijing.hexagrams.filter { $0.lower == id || $0.upper == id }.sorted { $0.number < $1.number }
    }
}
