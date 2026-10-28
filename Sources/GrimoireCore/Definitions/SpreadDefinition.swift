import Foundation

/// A spread file (spec §5.2).
public struct SpreadDefinition: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var aliases: [String]
    public var positions: [Position]
    /// Deck ids this spread applies to; "*" means any.
    public var decks: [String]
    /// Freeform spreads accept any number of unnamed positions.
    public var openEnded: Bool

    public struct Position: Codable, Hashable, Sendable {
        public var key: String
        public var label: String
        public init(key: String, label: String) { self.key = key; self.label = label }
    }

    public init(id: String, name: String, aliases: [String] = [], positions: [Position], decks: [String] = ["*"], openEnded: Bool = false) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.positions = positions
        self.decks = decks
        self.openEnded = openEnded
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        positions = try c.decode([Position].self, forKey: .positions)
        decks = try c.decodeIfPresent([String].self, forKey: .decks) ?? ["*"]
        openEnded = try c.decodeIfPresent(Bool.self, forKey: .openEnded) ?? false
    }

    public static let freeformID = "freeform"

    /// Position key for the n-th draw (0-based). Overflow positions get `extra-N`.
    public func positionKey(at index: Int) -> String {
        if index < positions.count { return positions[index].key }
        if openEnded { return String(index + 1) }
        return "extra-\(index - positions.count + 1)"
    }

    public func label(for key: String) -> String {
        positions.first { $0.key == key }?.label ?? key
    }

    public func applies(to deckId: String) -> Bool { decks.contains("*") || decks.contains(deckId) }
}
