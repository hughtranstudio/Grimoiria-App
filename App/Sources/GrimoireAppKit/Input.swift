import Foundation
import GrimoireCore

/// Tags typed as one line: "entity/ally/crow, place/garden" or with spaces
/// between them. Duplicates drop out; order is kept.
public enum TagInput {
    public static func parse(_ text: String) -> [TagPath] {
        var seen = Set<TagPath>()
        return text.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == "#" })
            .flatMap { $0.split(separator: " ") }
            .map { TagPath(String($0)) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public static func format(_ tags: [TagPath]) -> String { tags.map(\.path).joined(separator: ", ") }

    /// The fragment being typed: everything after the last comma or space.
    public static func fragment(of text: String) -> String {
        String(text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "," || $0 == " " }).last ?? "")
    }

    /// Replaces the fragment being typed with a chosen tag.
    public static func complete(_ text: String, with tag: TagPath) -> String {
        let frag = fragment(of: text)
        return String(text.dropLast(frag.count)) + tag.path + ", "
    }
}

/// "Volume III pp. 40–50", "III 40-50", "vol 3 p 12": a volume name and an
/// optional page range, for the search field.
public struct PageQuery: Equatable, Sendable {
    public var volume: String
    public var pages: ClosedRange<Int>?

    public init(volume: String, pages: ClosedRange<Int>?) { self.volume = volume; self.pages = pages }

    public static func parse(_ text: String) -> PageQuery? {
        let pattern = #"^\s*(?:vol(?:ume)?\.?\s+)?([ivxlcdm]+|\d+)\s*,?\s*(?:pp?\.?|pages?)?\s*(\d+)?\s*(?:[-–—]|to)?\s*(\d+)?\s*$"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ i: Int) -> String? { Range(m.range(at: i), in: text).map { String(text[$0]) } }
        guard let vol = group(1) else { return nil }
        // A bare number with no "volume" word is not a page query.
        if Int(vol) != nil, !text.lowercased().contains("vol") { return nil }
        var range: ClosedRange<Int>?
        if let lo = group(2).flatMap(Int.init) {
            let hi = group(3).flatMap(Int.init) ?? lo
            range = min(lo, hi)...max(lo, hi)
        }
        return PageQuery(volume: vol, pages: range)
    }

    /// Volume names match by their numeral: "III" matches "Volume III" and "Grimoire III".
    public func matches(volumeName: String) -> Bool {
        let wanted = Self.number(volume)
        let words = volumeName.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if words.contains(where: { $0.caseInsensitiveCompare(volume) == .orderedSame }) { return true }
        guard let wanted else { return false }
        return words.contains { Self.number($0) == wanted }
    }

    /// Roman or Arabic numeral as a number.
    public static func number(_ s: String) -> Int? {
        if let n = Int(s) { return n }
        let values: [Character: Int] = ["i": 1, "v": 5, "x": 10, "l": 50, "c": 100, "d": 500, "m": 1000]
        let digits = s.lowercased().compactMap { values[$0] }
        guard digits.count == s.count, !digits.isEmpty else { return nil }
        var total = 0
        for (i, v) in digits.enumerated() {
            total += (i + 1 < digits.count && v < digits[i + 1]) ? -v : v
        }
        return total
    }
}

/// The quick-log panel's one-key types.
public enum QuickKind: String, CaseIterable, Sendable {
    case journal, omen, insight, dream, cardDraw, yijing, vision

    public var key: Character {
        switch self {
        case .journal: "j"
        case .omen: "o"
        case .insight: "i"
        case .dream: "d"
        case .cardDraw: "c"
        case .yijing: "y"
        case .vision: "v"
        }
    }

    public var title: String {
        switch self {
        case .cardDraw: "Card draw"
        case .yijing: "Yi Jing"
        default: rawValue.capitalized
        }
    }

    /// The entry type a plain-text kind saves as; nil for the divination kinds.
    public var entryType: EntryType? {
        switch self {
        case .journal: .journal
        case .omen: .omen
        case .insight: .insight
        case .dream: .dream
        case .vision: .vision
        case .cardDraw, .yijing: nil
        }
    }

    public static func forKey(_ c: Character) -> QuickKind? {
        allCases.first { $0.key == Character(c.lowercased()) }
    }
}

/// Reminder choices on the New Inquiry sheet: the presets plus a custom day count.
public enum ReminderChoice: Hashable, Sendable {
    case preset(ReminderPreset)
    case customDays(Int)

    public static let menu: [ReminderChoice] = ReminderPreset.allCases.map { .preset($0) }

    public var title: String {
        switch self {
        case .preset(.none): "None"
        case .preset(.oneWeek): "In 1 week"
        case .preset(.oneMonth): "In 1 month"
        case .preset(.threeMonths): "In 3 months"
        case .customDays(let n): "In \(n) days"
        }
    }

    /// The due day (yyyy-MM-dd) counted from `day`, or nil for None.
    public func dueOn(from day: String) -> String? {
        switch self {
        case .preset(let p): return p.dueOn(from: day)
        case .customDays(let n):
            guard n > 0 else { return nil }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(secondsFromGMT: 0)!
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.calendar = cal
            f.timeZone = cal.timeZone
            f.dateFormat = "yyyy-MM-dd"
            guard let d = f.date(from: day), let r = cal.date(byAdding: .day, value: n, to: d) else { return nil }
            return f.string(from: r)
        }
    }
}
