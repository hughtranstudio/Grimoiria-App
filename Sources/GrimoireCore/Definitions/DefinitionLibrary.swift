import Foundation

/// All decks, spreads and the Yi Jing table, loaded from JSON (spec §5).
public struct DefinitionLibrary: Sendable {
    public var decks: [DeckDefinition]
    public var spreads: [SpreadDefinition]
    public var yijing: YiJingDefinition
    /// Planets, signs, elements and trigrams (`correspondences.json`), when the folder has it.
    public var correspondences: Correspondences?

    public init(decks: [DeckDefinition], spreads: [SpreadDefinition], yijing: YiJingDefinition, correspondences: Correspondences? = nil) {
        self.decks = decks.sorted { $0.id < $1.id }
        self.spreads = spreads.sorted { $0.id < $1.id }
        self.yijing = yijing
        self.correspondences = correspondences
    }

    public func deck(_ id: String) -> DeckDefinition? { decks.first { $0.id == id } }
    public func spread(_ id: String) -> SpreadDefinition? { spreads.first { $0.id == id } }
    public var freeform: SpreadDefinition {
        spread(SpreadDefinition.freeformID) ?? SpreadDefinition(id: SpreadDefinition.freeformID, name: "Freeform", positions: [], openEnded: true)
    }

    /// The definitions shipped inside the package.
    public static func bundled() throws -> DefinitionLibrary {
        guard let url = Bundle.module.url(forResource: "Definitions", withExtension: nil) else {
            throw DefinitionError.missing("bundled Definitions folder")
        }
        return try load(from: url)
    }

    /// Loads `decks/*.json`, `spreads/*.json` and `yijing.json` from a folder.
    /// The Mac app copies the bundled folder to its data folder on first launch and loads from there.
    public static func load(from folder: URL) throws -> DefinitionLibrary {
        let fm = FileManager.default
        func jsonFiles(_ sub: String) throws -> [URL] {
            let dir = folder.appendingPathComponent(sub)
            guard fm.fileExists(atPath: dir.path) else { return [] }
            return try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        let decoder = JSONDecoder()
        func decode<T: Decodable>(_ type: T.Type, _ url: URL) throws -> T {
            do { return try decoder.decode(type, from: Data(contentsOf: url)) }
            catch { throw DefinitionError.invalid(url.lastPathComponent, String(describing: error)) }
        }
        let decks = try jsonFiles("decks").map { try decode(DeckDefinition.self, $0) }
        let spreads = try jsonFiles("spreads").map { try decode(SpreadDefinition.self, $0) }
        let yjURL = folder.appendingPathComponent("yijing.json")
        guard fm.fileExists(atPath: yjURL.path) else { throw DefinitionError.missing("yijing.json") }
        let cURL = folder.appendingPathComponent("correspondences.json")
        let correspondences = fm.fileExists(atPath: cURL.path) ? try decode(Correspondences.self, cURL) : nil
        return DefinitionLibrary(decks: decks, spreads: spreads, yijing: try decode(YiJingDefinition.self, yjURL), correspondences: correspondences)
    }

    /// Structural checks. Errors make the library unusable; warnings (e.g. placeholder decks) do not.
    public func validate() -> ValidationReport {
        var report = ValidationReport()
        var deckIDs = Set<String>()
        for deck in decks {
            if !deckIDs.insert(deck.id).inserted { report.errors.append("Duplicate deck id \(deck.id)") }
            var cardIDs = Set<String>()
            for card in deck.cards {
                if !cardIDs.insert(card.id).inserted { report.errors.append("\(deck.id): duplicate card id \(card.id)") }
                for key in card.attributes.keys where !deck.attributes.contains(key) {
                    report.errors.append("\(deck.id)/\(card.id): attribute '\(key)' not declared in deck.attributes")
                }
            }
            switch deck.status {
            case .placeholder:
                report.warnings.append("\(deck.id): placeholder deck with \(deck.cards.count) cards; card list and significations still to come from the deck repository")
            case .template: break
            case .complete:
                if deck.cards.isEmpty { report.errors.append("\(deck.id): marked complete but has no cards") }
            }
            if deck.id == "rws-tarot" && deck.cards.count != 78 {
                report.errors.append("rws-tarot: expected 78 cards, found \(deck.cards.count)")
            }
        }
        var spreadIDs = Set<String>()
        for spread in spreads {
            if !spreadIDs.insert(spread.id).inserted { report.errors.append("Duplicate spread id \(spread.id)") }
            let keys = spread.positions.map(\.key)
            if Set(keys).count != keys.count { report.errors.append("\(spread.id): duplicate position keys") }
            if spread.positions.isEmpty && !spread.openEnded { report.errors.append("\(spread.id): no positions and not openEnded") }
        }
        if spread(SpreadDefinition.freeformID) == nil { report.errors.append("Missing built-in freeform spread") }
        let numbers = Set(yijing.hexagrams.map(\.number))
        if numbers != Set(1...64) { report.errors.append("yijing: hexagrams must be exactly 1…64") }
        if Set(yijing.hexagrams.map(\.lines)).count != 64 { report.errors.append("yijing: hexagram line patterns are not unique") }
        let trig = Dictionary(uniqueKeysWithValues: yijing.trigrams.map { ($0.id, $0.lines) })
        for h in yijing.hexagrams {
            guard let lo = trig[h.lower], let up = trig[h.upper] else {
                report.errors.append("yijing #\(h.number): unknown trigram"); continue
            }
            if lo + up != h.lines { report.errors.append("yijing #\(h.number): lines disagree with trigrams") }
        }
        if let c = correspondences {
            let ids = c.entries.map(\.id)
            if Set(ids).count != ids.count { report.errors.append("correspondences: duplicate entry ids") }
            for e in c.entries {
                for r in e.related where c.entry(r) == nil { report.errors.append("correspondences \(e.id): unknown related entry \(r)") }
            }
        }
        return report
    }
}

public struct ValidationReport: Sendable {
    public var errors: [String] = []
    public var warnings: [String] = []
    public var isValid: Bool { errors.isEmpty }
}

public enum DefinitionError: Error, CustomStringConvertible {
    case missing(String)
    case invalid(String, String)
    public var description: String {
        switch self {
        case .missing(let what): return "Missing \(what)"
        case .invalid(let file, let why): return "Invalid \(file): \(why)"
        }
    }
}
