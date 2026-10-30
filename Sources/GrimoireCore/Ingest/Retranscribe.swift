import Foundation

public extension DefinitionLibrary {
    static let readingWords = [
        "reversed", "upright", "question", "Yi Jing", "I Ching", "hexagram", "changing lines",
        "changing line", "moving lines", "becomes", "coins", "yarrow", "omen", "spread", "card", "cards",
    ]

    /// Words and phrases a speech recognizer should expect in a reading: deck, card, spread and
    /// hexagram names plus the words the parser listens for, so names like "Mystagogos" or "Kun"
    /// aren't heard as everyday words. Same list as the Android app's `speechHints()`;
    /// `aliases: false` keeps only names, for recognizers that take fewer hints.
    func speechHints(aliases: Bool = true) -> [String] {
        var seen = Set<String>(), out: [String] = []
        func add(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespaces)
            if t.count > 1, seen.insert(t).inserted { out.append(t) }
        }
        Self.readingWords.forEach(add)
        for d in decks {
            add(d.name)
            if aliases { d.aliases.forEach(add) }
            for c in d.cards { add(c.name); if aliases { c.aliases.forEach(add) } }
        }
        for s in spreads {
            add(s.name)
            if aliases { s.aliases.forEach(add) }
            s.positions.forEach { add($0.label) }
        }
        if aliases { yijing.aliases.forEach(add) }
        for h in yijing.hexagrams { add(h.pinyin); add(h.name) }
        return out
    }
}

public extension InboxItem {
    /// The item with a new transcript (from "Transcribe Again"): the text replaces the old transcript
    /// in the body and the reading is parsed again. A draft checked on the phone is replaced only
    /// when the new text holds a reading. Still waits in the Inbox for Confirm.
    func retranscribed(_ text: String, parser: ReadingParser) -> InboxItem {
        var item = self
        let new = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let old = entry.transcript ?? ""
        if !old.isEmpty, item.entry.body.contains(old) {
            item.entry.body = item.entry.body.replacingOccurrences(of: old, with: new)
        } else if old.isEmpty, !item.entry.body.isEmpty, !new.isEmpty {
            item.entry.body += "\n\n" + new
        } else {
            item.entry.body = new
        }
        item.entry.transcript = new.isEmpty ? nil : new
        let parsed = parser.parse(item.entry.body)
        if !parsed.isEmpty || draft == nil {
            item.draft = parsed.isEmpty ? nil : parsed
        }
        return item
    }
}
