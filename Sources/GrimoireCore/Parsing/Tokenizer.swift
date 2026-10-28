import Foundation

/// Lower-cases, strips accents, and splits text into word tokens. Sentence punctuation
/// becomes a `boundary` token so matches never span "One, three of cups".
enum Token: Equatable {
    case word(String)
    case boundary
}

enum Tokenizer {
    /// Words dropped before matching card and spread names.
    static let fillers: Set<String> = ["the", "of", "a", "an"]

    static let numberWords: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "twenty-one": 21,
    ]

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func tokenize(_ text: String) -> [Token] {
        var out: [Token] = []
        var cur = ""
        func flush() { if !cur.isEmpty { out.append(.word(cur)); cur = "" } }
        for ch in fold(text) {
            if ch.isLetter || ch.isNumber || ch == "'" {
                cur.append(ch)
            } else if ch == "-" || ch == "–" {
                flush() // "Rider-Waite" → rider waite
            } else if ".,;:!?\n()".contains(ch) {
                flush()
                if out.last != .boundary { out.append(.boundary) }
            } else {
                flush()
            }
        }
        flush()
        return out
    }

    /// Normalized key for alias comparison: fillers dropped, digits spelled out.
    static func key(_ text: String) -> String {
        tokenize(text).compactMap { tok -> String? in
            guard case .word(let w) = tok, !fillers.contains(w) else { return nil }
            return w
        }.map(spell).joined(separator: " ")
    }

    static func spell(_ w: String) -> String {
        if let n = Int(w), let word = numberWords.first(where: { $0.value == n })?.key { return word }
        return w
    }
}

enum Fuzzy {
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    /// 1.0 for identical strings, falling towards 0.
    static func similarity(_ a: String, _ b: String) -> Double {
        let m = max(a.count, b.count)
        return m == 0 ? 1 : 1 - Double(levenshtein(a, b)) / Double(m)
    }
}
