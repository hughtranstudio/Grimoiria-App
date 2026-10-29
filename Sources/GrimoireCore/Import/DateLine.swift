import Foundation

/// A date (and maybe a time) at the start of a line, which starts a new entry when importing
/// (spec §11.3). Recognised: `2026-10-28`, `28 October 2026`, `28th of Oct 2026`,
/// `October 28, 2026`, `Tue 28 Oct 2026`, `10/28/2026` (order set by `SlashOrder`), each
/// optionally followed by a time (`8:14`, `20h14`, `8:14 pm`, `at 9pm`) and a title.
public struct DateLine: Equatable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int
    public var hour: Int?
    public var minute: Int?
    /// What followed the date on the line, separators trimmed.
    public var rest: String
    /// A numeric d/m date where both orders were valid, read using `SlashOrder`.
    public var ambiguous: Bool

    /// How to read `03/04/2026`.
    public enum SlashOrder: String, Codable, Sendable { case monthFirst = "mdy", dayFirst = "dmy" }

    public static func parse(_ line: String, slashOrder: SlashOrder = .monthFirst) -> DateLine? {
        let s = clean(line)
        guard let first = s.first, first.isLetter || first.isNumber else { return nil }
        for pattern in patterns {
            guard let m = pattern.regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { continue }
            func g(_ i: Int) -> String? {
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : Range(r, in: s).map { String(s[$0]) }
            }
            var y: Int, mo: Int, d: Int, ambiguous = false
            switch pattern.kind {
            case .iso:
                guard let a = g(1).flatMap(Int.init), let b = g(2).flatMap(Int.init), let c = g(3).flatMap(Int.init) else { continue }
                (y, mo, d) = (a, b, c)
            case .dayMonthName:
                guard let a = g(1).flatMap(Int.init), let mn = g(2).flatMap(month), let c = g(3).flatMap(Int.init) else { continue }
                (y, mo, d) = (c, mn, a)
            case .monthNameDay:
                guard let mn = g(1).flatMap(month), let a = g(2).flatMap(Int.init), let c = g(3).flatMap(Int.init) else { continue }
                (y, mo, d) = (c, mn, a)
            case .slash:
                guard let a = g(1).flatMap(Int.init), let b = g(2).flatMap(Int.init), let c = g(3).flatMap(Int.init) else { continue }
                y = c
                switch (a > 12, b > 12) {
                case (true, false): (mo, d) = (b, a)
                case (false, true): (mo, d) = (a, b)
                case (false, false):
                    (mo, d) = slashOrder == .monthFirst ? (a, b) : (b, a)
                    ambiguous = a != b
                case (true, true): continue
                }
            }
            if y < 100 { y += y <= (currentYear % 100) + 1 ? 2000 : 1900 }
            guard isValid(y, mo, d) else { continue }

            var out = DateLine(year: y, month: mo, day: d, rest: "", ambiguous: ambiguous)
            var tail = Range(m.range, in: s).map { String(s[$0.upperBound...]) } ?? ""
            if let t = time.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)), let r = Range(t.range, in: tail) {
                func tg(_ i: Int) -> String? {
                    let rr = t.range(at: i)
                    return rr.location == NSNotFound ? nil : Range(rr, in: tail).map { String(tail[$0]) }
                }
                var h = tg(1).flatMap(Int.init) ?? tg(4).flatMap(Int.init) ?? -1
                let mi = tg(2).flatMap(Int.init) ?? 0
                let ampm = (tg(3) ?? tg(5))?.lowercased().filter(\.isLetter)
                if ampm == "pm", h < 12 { h += 12 }
                if ampm == "am", h == 12 { h = 0 }
                if (0...23).contains(h), (0...59).contains(mi) {
                    out.hour = h; out.minute = mi
                    tail = String(tail[r.upperBound...])
                }
            }
            out.rest = tail.trimmingCharacters(in: separators)
            return out
        }
        return nil
    }

    /// Drops Markdown decoration so `## **28 October 2026** —` reads as a date line.
    static func clean(_ line: String) -> String {
        var s = line.replacingOccurrences(of: "\\", with: "")
        s = s.trimmingCharacters(in: .whitespaces)
        // Heading hashes, quote marks, list bullets and emphasis in front of the date.
        while let f = s.first, "#>*_-+ \t".contains(f) { s.removeFirst() }
        return s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    static let separators = CharacterSet(charactersIn: " \t-–—:|,.;()*_").union(.whitespaces)

    static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
    static func month(_ word: String) -> Int? {
        let w = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard w.count >= 3 else { return nil }
        return months.firstIndex { $0.hasPrefix(w) }.map { $0 + 1 }
    }

    static let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())

    static func isValid(_ y: Int, _ m: Int, _ d: Int) -> Bool {
        guard (1...12).contains(m), (1...31).contains(d), (1000...9999).contains(y) else { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return DateComponents(calendar: cal, year: y, month: m, day: d).isValidDate
    }

    enum Kind { case iso, dayMonthName, monthNameDay, slash }

    static let weekday = #"(?:(?:mon|tue|tues|wed|weds|thu|thur|thurs|fri|sat|sun)[a-z]*\.?,?\s+)?"#
    static let end = #"(?=$|[\s\-–—:,|.;()])"#
    static let patterns: [(kind: Kind, regex: NSRegularExpression)] = [
        (.iso, #"(\d{4})[-./](\d{1,2})[-./](\d{1,2})"#),
        (.dayMonthName, #"(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?([a-z]{3,9})\.?,?\s+(\d{4})"#),
        (.monthNameDay, #"([a-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})"#),
        (.slash, #"(\d{1,2})[/.](\d{1,2})[/.](\d{4}|\d{2})"#),
    ].map { kind, p in (kind, try! NSRegularExpression(pattern: "^" + weekday + p + end, options: [.caseInsensitive])) }

    static let time = try! NSRegularExpression(
        pattern: #"^[\s,]*(?:at\s+|@\s*)?(?:(\d{1,2})[:h.](\d{2})\s*([ap]\.?m\.?)?|(\d{1,2})\s*([ap]\.?m\.?))(?=$|[\s\-–—:,|.;()])"#,
        options: [.caseInsensitive])
}
