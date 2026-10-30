import Foundation

/// Parses a transcript (or typed text) into a DraftReading against the loaded definitions.
///
/// Spoken pattern (Shortcut guide §4):
///   "Question: will the move go ahead. Deck Rider-Waite. Three card. One, three of cups reversed.
///    Two, the Tower. Three, page of wands. Yi Jing, coins. Seven eight nine six seven seven."
///
/// Each "deck …" or "Yi Jing" starts a new divination under the same question.
public struct ReadingParser: Sendable {
    public let library: DefinitionLibrary
    let deckMatcher: NameMatcher<String>
    let spreadMatcher: NameMatcher<String>
    let cardMatchers: [String: NameMatcher<String>]
    let yijingKeys: [[String]]

    static let reversedWords: Set<String> = ["reversed", "reverse", "inverted", "upside", "r", "rev", "rx"]
    static let uprightWords: Set<String> = ["upright"]
    static let deckKeyword = "deck"
    static let questionKeyword = "question"

    public init(library: DefinitionLibrary) {
        self.library = library
        deckMatcher = NameMatcher(names: library.decks.map { ($0.id, [$0.name, $0.id] + $0.aliases) }, threshold: 0.75)
        spreadMatcher = NameMatcher(names: library.spreads.map { ($0.id, [$0.name] + $0.aliases) }, threshold: 0.85)
        var cm: [String: NameMatcher<String>] = [:]
        for d in library.decks where !d.cards.isEmpty { cm[d.id] = d.cardMatcher }
        cardMatchers = cm
        yijingKeys = library.yijing.aliases.map { Tokenizer.key($0).split(separator: " ").map(String.init) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Quick draw (spec §9.1)

    /// Typed quick draw: "3 cups r, tower, page wands". Positions fill in the spread's order.
    public func parseQuickDraw(_ text: String, deckId: String, spreadId: String? = nil) -> DraftDivination {
        var div = DraftDivination(system: .cards, deckId: Parsed(deckId, confidence: .high),
                                  spreadId: Parsed(spreadId ?? SpreadDefinition.freeformID, confidence: .high), heard: text)
        var unparsed: [String] = []
        parseCards(Tokenizer.tokenize(text)[...], into: &div, unparsed: &unparsed)
        return div
    }

    // MARK: - Full transcript

    public func parse(_ transcript: String) -> DraftReading {
        var reading = DraftReading()
        var tokens = Tokenizer.tokenize(transcript)[...]

        // Question: from "question" to the end of that sentence.
        if let qi = tokens.firstIndex(of: .word(Self.questionKeyword)) {
            var end = tokens.index(after: qi)
            if end < tokens.endIndex, tokens[end] == .boundary { end += 1 } // "Question: …"
            let start = end
            while end < tokens.endIndex, tokens[end] != .boundary { end += 1 }
            let words = tokens[start..<end].compactMap { if case .word(let w) = $0 { return w } else { return nil } }
            if !words.isEmpty {
                let q = Self.recoverQuestion(from: transcript) ?? words.joined(separator: " ")
                reading.question = Parsed(q, heard: words.joined(separator: " "), confidence: .high)
            }
            tokens.removeSubrange(qi..<end)
        }

        // Split into segments at "deck" and Yi Jing keywords.
        for segment in segments(tokens) {
            switch segment.kind {
            case .cards:
                var div = DraftDivination(system: .cards, heard: segment.text)
                var rest = segment.tokens
                if let (deck, used) = matchDeck(rest) {
                    div.deckId = deck
                    rest = rest.dropFirst(used)
                } else {
                    reading.warnings.append("No deck recognised after \"deck\"; pick one in the Inbox")
                }
                parseCards(rest, into: &div, unparsed: &reading.unparsed)
                if div.deckId.value != nil && cardMatchers[div.deckId.value!] == nil {
                    reading.warnings.append("Deck \(div.deckId.value!) has no card list yet; draws must be entered by hand")
                }
                if div.spreadId.value == nil { div.spreadId = Parsed(SpreadDefinition.freeformID, confidence: .medium) }
                if let spread = div.spreadId.value.flatMap(library.spread), !spread.openEnded, div.draws.count != spread.positions.count {
                    reading.warnings.append("\(spread.name) has \(spread.positions.count) positions but \(div.draws.count) cards were heard")
                }
                reading.divinations.append(div)
            case .yijing:
                var div = DraftDivination(system: .yijing, heard: segment.text)
                div.cast = parseCast(segment.tokens, warnings: &reading.warnings)
                reading.divinations.append(div)
            case .preamble:
                // Words before any deck/Yi Jing keyword: try cards against the only complete deck if
                // the text clearly lists cards, otherwise leave them as body text.
                break
            }
        }
        return reading
    }

    // MARK: - Segmenting

    enum SegmentKind { case preamble, cards, yijing }
    struct Segment { var kind: SegmentKind; var tokens: ArraySlice<Token>; var text: String }

    func segments(_ tokens: ArraySlice<Token>) -> [Segment] {
        var result: [Segment] = []
        var kind = SegmentKind.preamble
        var buf: [Token] = []
        func flush() {
            let text = buf.compactMap { if case .word(let w) = $0 { return w } else { return nil } }.joined(separator: " ")
            if kind != .preamble || !buf.isEmpty { result.append(Segment(kind: kind, tokens: buf[...], text: text)) }
            buf = []
        }
        var i = tokens.startIndex
        while i < tokens.endIndex {
            if tokens[i] == .word(Self.deckKeyword) {
                flush(); kind = .cards; i += 1; continue
            }
            if let len = yijingKeywordLength(tokens, at: i) {
                flush(); kind = .yijing; i += len; continue
            }
            buf.append(tokens[i]); i += 1
        }
        flush()
        return result.filter { $0.kind != .preamble }
    }

    func yijingKeywordLength(_ tokens: ArraySlice<Token>, at i: Int) -> Int? {
        for key in yijingKeys where i + key.count <= tokens.endIndex {
            let words = tokens[i..<i + key.count].map { tok -> String in if case .word(let w) = tok { return w } else { return "" } }
            if words == key { return key.count }
        }
        return nil
    }

    // MARK: - Decks and cards

    func words(_ tokens: ArraySlice<Token>) -> [String] {
        tokens.compactMap { if case .word(let w) = $0 { return w } else { return nil } }
    }

    /// Matches the deck name at the start of a segment. Returns the number of tokens consumed.
    func matchDeck(_ tokens: ArraySlice<Token>) -> (Parsed<String>, Int)? {
        // Look at words up to the first boundary.
        var idx = tokens.startIndex
        var ws: [String] = []
        var positions: [Int] = []
        while idx < tokens.endIndex, ws.count < 4 {
            if case .word(let w) = tokens[idx] { if !Tokenizer.fillers.contains(w) { ws.append(Tokenizer.spell(w)); positions.append(idx) } }
            else if !ws.isEmpty { break }
            idx += 1
        }
        guard !ws.isEmpty, let m = deckMatcher.longestMatch(in: ws, from: 0) else { return nil }
        let consumed = positions[m.wordCount - 1] - tokens.startIndex + 1
        return (Parsed(m.id, heard: ws.prefix(m.wordCount).joined(separator: " "), confidence: .from(score: m.score)), consumed)
    }

    func parseCards(_ tokens: ArraySlice<Token>, into div: inout DraftDivination, unparsed: inout [String]) {
        let matcher = div.deckId.value.flatMap { cardMatchers[$0] }
        // Work on runs between boundaries so a match never spans "One, three of cups".
        var runs: [[String]] = [[]]
        for t in tokens {
            switch t {
            case .boundary: if !runs.last!.isEmpty { runs.append([]) }
            case .word(let w): if !Tokenizer.fillers.contains(w) { runs[runs.count - 1].append(Tokenizer.spell(w)) }
            }
        }
        for run in runs where !run.isEmpty {
            var i = 0
            while i < run.count {
                let w = run[i]
                if Self.reversedWords.contains(w) || (w == "upside" && i + 1 < run.count && run[i + 1] == "down") {
                    if let last = div.draws.indices.last {
                        div.draws[last].orientation = Parsed(.reversed, heard: w, confidence: w == "r" ? .medium : .high)
                    }
                    i += (w == "upside" && i + 1 < run.count && run[i + 1] == "down") ? 2 : 1
                    continue
                }
                if Self.uprightWords.contains(w) { i += 1; continue }
                // Spread name, only before the first card.
                if div.draws.isEmpty, div.spreadId.value == nil || div.spreadId.confidence < .high,
                   let sm = spreadMatcher.longestMatch(in: run, from: i), sm.score >= 0.85 {
                    div.spreadId = Parsed(sm.id, heard: run[i..<i + sm.wordCount].joined(separator: " "), confidence: .from(score: sm.score))
                    i += sm.wordCount
                    if i < run.count, run[i] == "spread" { i += 1 }
                    continue
                }
                if let matcher, let cm = matcher.longestMatch(in: run, from: i) {
                    let heard = run[i..<i + cm.wordCount].joined(separator: " ")
                    let spread = div.spreadId.value.flatMap(library.spread) ?? library.freeform
                    div.draws.append(DraftDraw(cardId: Parsed(cm.id, heard: heard, confidence: .from(score: cm.score)),
                                               orientation: Parsed(.upright, confidence: .high),
                                               positionKey: spread.positionKey(at: div.draws.count)))
                    i += cm.wordCount
                    continue
                }
                if !Self.ignorable.contains(w) && Int(w) == nil && Tokenizer.numberWords[w] == nil { unparsed.append(w) }
                i += 1
            }
        }
        // Mark overflow positions as low confidence so they stand out.
        if let spread = div.spreadId.value.flatMap(library.spread), !spread.openEnded {
            for k in div.draws.indices where k >= spread.positions.count {
                div.draws[k].cardId.confidence = min(div.draws[k].cardId.confidence, .low)
            }
        }
    }

    static let ignorable: Set<String> = ["and", "then", "next", "card", "cards", "position", "spread", "is", "was", "in", "first", "second", "third", "last", "i", "drew", "pulled", "got", "um", "uh", "so", "with"]

    // MARK: - Yi Jing

    func parseCast(_ tokens: ArraySlice<Token>, warnings: inout [String]) -> DraftCast {
        var method = YiJingCast.Method.coins
        var values: [Int] = []
        var heard: [String] = []
        for w in words(tokens) {
            if w == "coins" || w == "coin" { method = .coins; continue }
            if w == "yarrow" || w == "stalks" { method = .yarrow; continue }
            if let n = Tokenizer.numberWords[w], (6...9).contains(n) { values.append(n); heard.append(w); continue }
            if w.allSatisfy(\.isNumber) {
                let digits = w.compactMap(\.wholeNumberValue)
                if digits.allSatisfy({ (6...9).contains($0) }) { values.append(contentsOf: digits); heard.append(w) }
            }
        }
        let conf: Confidence = values.count == 6 ? .high : .low
        if values.count != 6 { warnings.append("Yi Jing: heard \(values.count) line values, need 6 (bottom to top)") }
        return DraftCast(lines: Parsed(values, heard: heard.joined(separator: " "), confidence: values.isEmpty ? .missing : conf), method: method)
    }

    /// Keeps the question's original casing and punctuation from the raw transcript.
    static func recoverQuestion(from transcript: String) -> String? {
        guard let r = transcript.range(of: "question", options: [.caseInsensitive]) else { return nil }
        var rest = transcript[r.upperBound...].drop { ":,-–— ".contains($0) }
        if let end = rest.firstIndex(where: { ".?!\n".contains($0) }) {
            let isQ = rest[end] == "?"
            rest = rest[..<end]
            let q = rest.trimmingCharacters(in: .whitespaces)
            return q.isEmpty ? nil : q + (isQ ? "?" : "")
        }
        let q = rest.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? nil : q
    }
}
