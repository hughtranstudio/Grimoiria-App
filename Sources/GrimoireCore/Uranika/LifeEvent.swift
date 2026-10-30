import Foundation

/// Recognises a spoken life event ("Hey so I just launched a website") and proposes a title and
/// tags. Only a guess: the Inbox confirm step is where Hugh accepts or changes it.
public enum LifeEvent {
    public struct Guess: Equatable, Sendable {
        public var title: String
        public var tags: [TagPath]
    }

    /// Words people open a voice note with, dropped before reading the sentence.
    static let fillers: Set<String> = ["hey", "hi", "hello", "ok", "okay", "so", "um", "uh", "er", "well", "right", "alright", "grimoire", "and", "yeah", "oh"]

    /// "I just …", "we've just …", "I finally …". The captured clause becomes the title.
    static let patterns = [
        #"^(?:i|we)(?: have|'ve| had|'d)? (?:just|finally|officially) (.+)$"#,
        #"^just (.+)$"#,
        #"^(?:life event|big news|news)[:,]? (.+)$"#,
    ]

    /// `kindHint == "event"` (the phone's Event button) always counts; otherwise the first
    /// sentence must read like an event.
    public static func detect(_ text: String, kindHint: String?, vocabulary: [TagPath] = []) -> Guess? {
        let sentence = firstSentence(stripFillers(text))
        guard !sentence.isEmpty else { return nil }
        var clause: String?
        for p in patterns {
            if let r = sentence.range(of: p, options: [.regularExpression, .caseInsensitive]) {
                let m = String(sentence[r])
                clause = m.replacingOccurrences(of: p, with: "$1", options: [.regularExpression, .caseInsensitive])
                break
            }
        }
        if clause == nil && kindHint?.lowercased() != "event" { return nil }
        var title = (clause ?? sentence).trimmingCharacters(in: .whitespaces)
        if title.count > 60 { title = String(title.prefix(57)).trimmingCharacters(in: .whitespaces) + "…" }
        title = title.prefix(1).uppercased() + title.dropFirst()
        return Guess(title: title, tags: suggestTags(text, vocabulary: vocabulary))
    }

    /// Existing tags whose last part is said in the note ("website" → projects/website), most specific first.
    public static func suggestTags(_ text: String, vocabulary: [TagPath], limit: Int = 5) -> [TagPath] {
        let words = " " + Tokenizer.fold(text).map { $0.isLetter || $0.isNumber ? $0 : " " }.reduce(into: "") { $0.append($1) } + " "
        let compact = words.split(separator: " ").joined(separator: " ")
        var out: [TagPath] = []
        for t in Set(vocabulary).sorted(by: { ($0.components.count, $0.path) > ($1.components.count, $1.path) }) {
            guard let leaf = t.components.last else { continue }
            let phrase = leaf.replacingOccurrences(of: "-", with: " ")
            guard phrase.count >= 3, (" " + compact + " ").contains(" \(phrase) ") else { continue }
            // Keep the deepest tag for a word: projects/website beats website.
            if out.contains(where: { $0.isUnder(t) }) { continue }
            out.append(t)
            if out.count == limit { break }
        }
        return out.sorted()
    }

    static func stripFillers(_ text: String) -> String {
        var s = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        while true {
            let word = s.prefix { $0.isLetter || $0 == "'" }
            guard !word.isEmpty, fillers.contains(word.lowercased()) else { break }
            s = s.dropFirst(word.count).drop { $0 == " " || $0 == "," || $0 == "." || $0 == "!" || $0 == "-" }
        }
        return String(s)
    }

    static func firstSentence(_ text: String) -> String {
        let end = text.firstIndex { ".!?\n".contains($0) } ?? text.endIndex
        return String(text[..<end]).trimmingCharacters(in: .whitespaces)
    }
}
