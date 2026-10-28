import Foundation

/// Matches spoken or typed phrases against named things (cards, decks, spreads) using
/// their names and aliases. Exact matches score 1.0; near misses score their similarity.
public struct NameMatcher<ID: Hashable & Sendable>: Sendable {
    struct Candidate: Sendable { let key: String; let wordCount: Int; let id: ID }
    private let candidates: [Candidate]
    private let exact: [String: ID]
    public let maxWords: Int
    public let threshold: Double

    public init(names: [(id: ID, names: [String])], threshold: Double = 0.8) {
        var list: [Candidate] = []
        var exact: [String: ID] = [:]
        for (id, ns) in names {
            for n in ns {
                let k = Tokenizer.key(n)
                guard !k.isEmpty else { continue }
                list.append(Candidate(key: k, wordCount: k.split(separator: " ").count, id: id))
                if exact[k] == nil { exact[k] = id }
            }
        }
        self.candidates = list
        self.exact = exact
        self.maxWords = list.map(\.wordCount).max() ?? 1
        self.threshold = threshold
    }

    public struct Match: Sendable {
        public let id: ID
        public let score: Double
        public let wordCount: Int
    }

    /// Best match for an already-normalized key.
    func match(key: String) -> Match? {
        let words = key.split(separator: " ").count
        if let id = exact[key] { return Match(id: id, score: 1, wordCount: words) }
        // Fuzzy only on phrases long enough that a near miss is meaningful.
        guard key.count >= 4 else { return nil }
        var best: Match?
        for c in candidates where c.wordCount == words {
            let s = Fuzzy.similarity(key, c.key)
            if s >= threshold, s > (best?.score ?? 0) { best = Match(id: c.id, score: s, wordCount: words) }
        }
        return best
    }

    /// Match a free phrase such as "3 cups" or "the Tower".
    public func match(_ phrase: String) -> Match? { match(key: Tokenizer.key(phrase)) }

    /// Longest match starting at `start` in a word list (fillers already removed). Exact beats fuzzy.
    func longestMatch(in words: [String], from start: Int) -> Match? {
        var fuzzy: Match?
        for len in stride(from: min(maxWords, words.count - start), through: 1, by: -1) {
            let key = words[start..<start + len].joined(separator: " ")
            guard let m = match(key: key) else { continue }
            if m.score == 1 { return m }
            if fuzzy == nil || m.score > fuzzy!.score { fuzzy = m }
        }
        return fuzzy
    }
}

public extension DeckDefinition {
    /// Matcher over every card's name and aliases.
    var cardMatcher: NameMatcher<String> {
        NameMatcher(names: cards.map { ($0.id, [$0.name] + $0.aliases) })
    }
}
