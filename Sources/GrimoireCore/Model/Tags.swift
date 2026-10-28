import Foundation

/// A hierarchical tag such as `entity/ally/crow` (spec §6).
public struct TagPath: Hashable, Comparable, Codable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let components: [String]

    public init(_ raw: String) {
        components = raw.lowercased()
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-") }
            .filter { !$0.isEmpty }
    }

    public init(stringLiteral value: String) { self.init(value) }

    public init(from decoder: Decoder) throws { self.init(try decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(path)
    }

    public var path: String { components.joined(separator: "/") }
    public var description: String { path }
    public var parent: TagPath? { components.count > 1 ? TagPath(components.dropLast().joined(separator: "/")) : nil }
    public var isEmpty: Bool { components.isEmpty }

    /// True when this tag equals `ancestor` or sits beneath it. Selecting a parent includes children.
    public func isUnder(_ ancestor: TagPath) -> Bool {
        ancestor.components.count <= components.count && Array(components.prefix(ancestor.components.count)) == ancestor.components
    }

    public static func < (a: TagPath, b: TagPath) -> Bool { a.path < b.path }
}

/// Builds the tag tree used by pickers and hierarchical search.
public struct TagTree: Sendable {
    public private(set) var all: Set<TagPath> = []

    public init<S: Sequence>(_ tags: S) where S.Element == TagPath {
        for t in tags { insert(t) }
    }

    public mutating func insert(_ tag: TagPath) {
        var cur: TagPath? = tag
        while let c = cur, !c.isEmpty { all.insert(c); cur = c.parent }
    }

    public func children(of parent: TagPath?) -> [TagPath] {
        let depth = (parent?.components.count ?? 0) + 1
        return all.filter { $0.components.count == depth && (parent.map($0.isUnder) ?? true) }.sorted()
    }

    /// Autocomplete: tags whose path contains the typed fragment, shortest first.
    public func suggestions(for fragment: String, limit: Int = 10) -> [TagPath] {
        let f = fragment.lowercased()
        return all.filter { $0.path.contains(f) }
            .sorted { ($0.path.count, $0.path) < ($1.path.count, $1.path) }
            .prefix(limit).map { $0 }
    }
}

/// Typed, directional links between records (spec §6).
public struct Link: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case respondsTo = "responds-to"
        case fulfilledBy = "fulfilled-by"
        case contradicts
        case continues
        case related
        /// Link to an Obsidian note by vault-relative path (spec §11.2).
        case vaultNote = "vault-note"
    }
    public var kind: Kind
    /// A record ULID, or a vault-relative path for `vaultNote`.
    public var target: String

    public init(_ kind: Kind, to target: String) { self.kind = kind; self.target = target }
    public init(_ kind: Kind, to id: ULID) { self.kind = kind; self.target = id.string }

    public var obsidianURL: URL? {
        guard kind == .vaultNote else { return nil }
        var c = URLComponents()
        c.scheme = "obsidian"
        c.host = "open"
        c.queryItems = [URLQueryItem(name: "file", value: target)]
        return c.url
    }
}
