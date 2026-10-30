import Foundation

/// The controlled tag vocabulary (docs/session-recording.md, "Tag system"). Tags stay free-form
/// paths everywhere; the vocabulary adds three things on top:
///
/// - `suggest(in:)` proposes tags from words in a text ("a red door" → color/red, symbol/door);
/// - `canonical(_:)` rewrites an alias or a bare leaf to its full path ("crow" → entity/animal/crow);
/// - `classify(_:)` splits tags into controlled (in the vocabulary) and free, for the exports.
///
/// Terms are only added or aliased, never renamed, so old exports stay comparable.
public struct TagVocabulary: Codable, Hashable, Sendable {
    public static let formatVersion = 1

    public struct Term: Codable, Hashable, Sendable {
        public var path: TagPath
        /// Other words or phrases for the term, lowercase. A phrase with "/" is an old tag path.
        public var aliases: [String]
        /// False keeps a term out of text suggestions (too common a word), while still controlled.
        public var suggest: Bool?
        public init(path: TagPath, aliases: [String] = [], suggest: Bool? = nil) {
            self.path = path; self.aliases = aliases; self.suggest = suggest
        }
    }

    public var version: Int
    public private(set) var terms: [Term]
    /// Built once from `terms`; lookups run per word of every transcript.
    private var index: Index
    /// Every controlled path, including the parents of each term (selecting `entity/animal` is fine).
    public private(set) var paths: Set<TagPath>

    public init(terms: [Term], version: Int = TagVocabulary.formatVersion) {
        self.version = version
        self.terms = terms.sorted { $0.path < $1.path }
        self.index = Self.makeIndex(self.terms)
        self.paths = TagTree(self.terms.map(\.path)).all
    }

    enum CodingKeys: String, CodingKey { case version, terms }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(terms: try c.decode([Term].self, forKey: .terms), version: try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.formatVersion)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(terms, forKey: .terms)
    }

    public static func == (a: TagVocabulary, b: TagVocabulary) -> Bool { a.version == b.version && a.terms == b.terms }
    public func hash(into h: inout Hasher) { h.combine(version); h.combine(terms) }

    // MARK: Lookups

    /// Top-level facets: entity, place, symbol, …
    public var facets: [String] { Array(Set(terms.compactMap { $0.path.components.first })).sorted() }

    public func isControlled(_ tag: TagPath) -> Bool { paths.contains(tag) }

    /// Splits tags (after `canonical`) into controlled and free, each sorted and unique.
    public func classify(_ tags: [TagPath]) -> (controlled: [TagPath], free: [TagPath]) {
        let all = Set(tags.map(canonical))
        return (all.filter(isControlled).sorted(), all.filter { !isControlled($0) }.sorted())
    }

    /// The controlled tags under each facet, e.g. ["entity": ["entity/animal/crow"], "color": ["color/red"]].
    public func byFacet(_ tags: [TagPath]) -> [String: [TagPath]] {
        var out: [String: [TagPath]] = [:]
        for t in classify(tags).controlled { if let f = t.components.first { out[f, default: []].append(t) } }
        return out
    }

    /// The canonical form of a tag: an alias path or alias word becomes its term, a bare leaf that
    /// names exactly one term becomes that term's full path. Anything else is returned unchanged.
    public func canonical(_ tag: TagPath) -> TagPath {
        if isControlled(tag) { return tag }
        let key = tag.path
        if let t = index.aliasPaths[key] { return t }
        if tag.components.count == 1 {
            let word = key.replacingOccurrences(of: "-", with: " ")
            if let t = index.phrases[word], t.count == 1 { return t[0] }
        }
        return tag
    }

    /// Controlled tags whose words appear in `text`, in order of first appearance.
    /// Matches whole words and phrases up to three words, singular or plural.
    public func suggest(in text: String) -> [TagPath] {
        let words = Self.words(text)
        var out: [TagPath] = []
        var i = 0
        while i < words.count {
            var matched = 0
            for n in stride(from: min(3, words.count - i), through: 1, by: -1) {
                let phrase = words[i..<(i + n)].joined(separator: " ")
                if let hits = index.suggestPhrases[phrase] ?? index.suggestPhrases[Self.singular(phrase)], hits.count == 1 {
                    if !out.contains(hits[0]) { out.append(hits[0]) }
                    matched = n
                    break
                }
            }
            i += max(matched, 1)
        }
        return out
    }

    /// This vocabulary with `other`'s terms added; aliases of a shared path are merged.
    public func merging(_ other: TagVocabulary) -> TagVocabulary {
        var byPath = Dictionary(terms.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        for t in other.terms {
            if var existing = byPath[t.path] {
                existing.aliases = Array(Set(existing.aliases + t.aliases)).sorted()
                if let s = t.suggest { existing.suggest = s }
                byPath[t.path] = existing
            } else {
                byPath[t.path] = t
            }
        }
        return TagVocabulary(terms: Array(byPath.values), version: max(version, other.version))
    }

    /// Adds a term (for "promote this free tag"). No-op when it is already controlled.
    public mutating func add(_ path: TagPath, aliases: [String] = []) {
        guard !path.isEmpty, !terms.contains(where: { $0.path == path }) else { return }
        self = merging(TagVocabulary(terms: [Term(path: path, aliases: aliases.map { $0.lowercased() })]))
    }

    // MARK: Text

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .split { !($0.isLetter || $0.isNumber || $0 == "'") }
            .map { $0.replacingOccurrences(of: "'s", with: "").replacingOccurrences(of: "'", with: "") }
            .filter { !$0.isEmpty }
    }

    static func singular(_ phrase: String) -> String {
        guard phrase.count > 3 else { return phrase }
        if phrase.hasSuffix("ies") { return String(phrase.dropLast(3)) + "y" }
        if phrase.hasSuffix("ses") || phrase.hasSuffix("xes") || phrase.hasSuffix("ches") || phrase.hasSuffix("shes") { return String(phrase.dropLast(2)) }
        if phrase.hasSuffix("s") && !phrase.hasSuffix("ss") { return String(phrase.dropLast()) }
        return phrase
    }

    struct Index: Hashable, Sendable {
        var phrases: [String: [TagPath]] = [:]
        var suggestPhrases: [String: [TagPath]] = [:]
        var aliasPaths: [String: TagPath] = [:]
    }

    static func makeIndex(_ terms: [Term]) -> Index {
        var ix = Index()
        for t in terms {
            guard let leaf = t.path.components.last else { continue }
            var spoken = [leaf.replacingOccurrences(of: "-", with: " ")]
            for a in t.aliases {
                if a.contains("/") { ix.aliasPaths[TagPath(a).path] = t.path } else { spoken.append(a.lowercased()) }
            }
            for p in Set(spoken) {
                ix.phrases[p, default: []].append(t.path)
                if t.suggest != false { ix.suggestPhrases[p, default: []].append(t.path) }
            }
        }
        // A word that names several terms is ambiguous; keep each list unique.
        ix.phrases = ix.phrases.mapValues { Array(Set($0)).sorted() }
        ix.suggestPhrases = ix.suggestPhrases.mapValues { Array(Set($0)).sorted() }
        return ix
    }

    // MARK: Files

    public static func load(from url: URL) throws -> TagVocabulary {
        try JSONDecoder().decode(TagVocabulary.self, from: Data(contentsOf: url))
    }

    public func json() throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try enc.encode(self), as: UTF8.self) + "\n"
    }

    /// The standard vocabulary plus the user's own file when it exists and reads.
    public static func standard(withUserFile url: URL?) -> TagVocabulary {
        guard let url, let user = try? load(from: url) else { return .standard }
        return standard.merging(user)
    }
}

extension TagVocabulary {
    /// The vocabulary Grimoire ships with, for Quareia-style ritual, meditation and visionary work.
    ///
    /// One line per parent: `parent: leaf leaf|alias|alias another-leaf`. An alias with `_` is a
    /// phrase with spaces; a leaf ending in `!` is controlled but never suggested from text.
    public static let standard: TagVocabulary = parse("""
    entity: ancestor|ancestors dead|the_dead deity|god|goddess|gods demon|demonic parasite spirit|spirits
    entity/being: angel|angelic|angels guardian|guardians inner-contact|inner_contact teacher priest priestess|priestesses faery|fairy|fae|faeries land-being|land_spirit|land_spirits elemental|elementals sleeper|sleepers child figure|robed_figure|hooded_figure|presence
    entity/animal: bird|birds crow|crows raven|ravens owl|owls hawk eagle dove swan snake|snakes wolf|wolves dog|dogs hound cat|cats horse|horses deer|stag bear lion fox bull spider bee|bees fish butterfly moth
    place: temple desert abyss underworld inner-library|inner_library|library forest|woods cave|cavern river sea|ocean lake well! mountain garden threshold gate|gateway tower city ruins stars|starlight void|nothing|darkness! house|home! field grave|graveyard|cemetery crossroads|crossroad
    symbol: door|doors|doorway key|keys sword|blade cup|chalice|grail wand|staff stone|stones book|books light! flame|flames|candle tree|trees serpent|serpents eye|eyes mirror ring crown thread|threads veil spiral cross circle star sun moon pillar|pillars|column bridge ladder|stairs|steps scales vessel|bowl spear|lance shield web feather|feathers skull bone|bones blood! bell
    color: red|crimson|scarlet orange gold|golden yellow green blue indigo violet|purple white black silver grey|gray brown
    element: fire water air earth spirit!
    direction: east south west north above! below! centre|center!
    sense: sight! sound|sounds|hum|humming|buzzing touch! heat|hot|warmth|warm cold|chill|chilled pressure tingling|tingle|prickling vibration|vibrating heaviness|heavy lightness|weightless scent|smell|incense taste falling spinning|vertigo
    emotion: awe fear|afraid|terror peace|peaceful|calm! joy|joyful grief|sad|sadness unease|uneasy|anxious love|loving anger|angry reverence|reverent
    state: drift|drifting sleep|asleep|dozed distraction|distracted clarity|clear!
    state/trance: light! deep!
    technique: stillness inner-flame|inner_flame breath|breathing visualization|visualisation chanting|chant|toning pathworking scrying banishing invocation|invoked|invoking offering|offered consecration|consecrated contemplation tarot-vision|card_vision
    planet: saturn jupiter mars sun! venus mercury moon!
    sign: aries taurus gemini cancer! leo virgo libra scorpio sagittarius capricorn aquarius pisces
    theme: threshold! death birth protection warning|warned teaching|taught|lesson healing test|tested|trial service
    """)

    static func parse(_ source: String) -> TagVocabulary {
        var terms: [Term] = []
        for line in source.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            for token in parts[1].split(separator: " ") {
                var names = token.split(separator: "|").map { String($0).replacingOccurrences(of: "_", with: " ") }
                var suggest: Bool?
                if names[0].hasSuffix("!") { names[0].removeLast(); suggest = false }
                names = names.map { $0.hasSuffix("!") ? String($0.dropLast()) : $0 }
                terms.append(Term(path: TagPath("\(parts[0])/\(names[0])"), aliases: Array(names.dropFirst()), suggest: suggest))
            }
        }
        return TagVocabulary(terms: terms)
    }
}
