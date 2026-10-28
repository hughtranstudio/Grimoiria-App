import Foundation

/// A deck file (spec §5.1). Cards are referenced by `deckId` + `cardId`, never by name.
public struct DeckDefinition: Codable, Hashable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case complete, placeholder, template
    }

    public var id: String
    public var name: String
    public var version: Int
    public var system: String
    public var status: Status
    public var reversalsAllowed: Bool
    public var aliases: [String]
    public var attributes: [String]
    public var source: String?
    public var cards: [Card]

    public struct Card: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var aliases: [String]
        /// Per-deck attributes (arcana, suit, number, element, …). Values are strings or numbers.
        public var attributes: [String: AttributeValue]
        /// Meanings/keywords, merged in from Hugh's deck repositories.
        public var significations: [String: AttributeValue]

        public init(id: String, name: String, aliases: [String] = [], attributes: [String: AttributeValue] = [:], significations: [String: AttributeValue] = [:]) {
            self.id = id
            self.name = name
            self.aliases = aliases
            self.attributes = attributes
            self.significations = significations
        }

        enum Known: String, CodingKey { case id, name, aliases, significations }

        struct AnyKey: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        // Attributes are stored flat on the card object, as in the spec example.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Known.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
            significations = try c.decodeIfPresent([String: AttributeValue].self, forKey: .significations) ?? [:]
            let all = try decoder.container(keyedBy: AnyKey.self)
            var attrs: [String: AttributeValue] = [:]
            for key in all.allKeys where Known(rawValue: key.stringValue) == nil {
                attrs[key.stringValue] = try all.decode(AttributeValue.self, forKey: key)
            }
            attributes = attrs
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Known.self)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            if !aliases.isEmpty { try c.encode(aliases, forKey: .aliases) }
            try c.encode(significations, forKey: .significations)
            var all = encoder.container(keyedBy: AnyKey.self)
            for (k, v) in attributes { try all.encode(v, forKey: AnyKey(stringValue: k)) }
        }
    }

    public func card(_ id: String) -> Card? { cards.first { $0.id == id } }
}

/// A JSON scalar or nested value used for open-ended attributes.
public enum AttributeValue: Codable, Hashable, Sendable, CustomStringConvertible {
    case string(String)
    case number(Double)
    case bool(Bool)
    case list([AttributeValue])
    case object([String: AttributeValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let l = try? c.decode([AttributeValue].self) { self = .list(l) }
        else { self = .object(try c.decode([String: AttributeValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n):
            if n == n.rounded(), abs(n) < 1e15 { try c.encode(Int(n)) } else { try c.encode(n) }
        case .bool(let b): try c.encode(b)
        case .list(let l): try c.encode(l)
        case .object(let o): try c.encode(o)
        }
    }

    public var description: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return String(b)
        case .list(let l): return l.map(\.description).joined(separator: ", ")
        case .object(let o): return o.keys.sorted().map { "\($0): \(o[$0]!)" }.joined(separator: ", ")
        }
    }
}
