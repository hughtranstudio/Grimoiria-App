import Foundation
import GrimoireCore

/// How dates read in the app: MM-DD-YYYY, in the record's own time zone.
public enum DisplayDate {
    public static func day(_ date: ZonedDate) -> String { format(date, "MM-dd-yyyy") }
    public static func dayTime(_ date: ZonedDate) -> String { format(date, "MM-dd-yyyy h:mm a") }

    /// A stored yyyy-MM-dd day (reminders, volumes) as MM-DD-YYYY.
    public static func day(_ stored: String) -> String {
        let p = stored.split(separator: "-")
        guard p.count == 3 else { return stored }
        return "\(p[1])-\(p[2])-\(p[0])"
    }

    static func format(_ date: ZonedDate, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = date.zone
        f.dateFormat = pattern
        return f.string(from: date.instant)
    }
}

/// Glyphs shown beside card names: suit or element, sign or planet.
public enum CardGlyph {
    static let elements: [String: String] = ["fire": "🜂", "water": "🜄", "air": "🜁", "earth": "🜃"]
    static let suits: [String: String] = ["wands": "fire", "cups": "water", "swords": "air", "pentacles": "earth"]
    static let astro: [String: String] = [
        "sun": "☉", "moon": "☽", "mercury": "☿", "venus": "♀", "mars": "♂", "jupiter": "♃", "saturn": "♄",
        "aries": "♈︎", "taurus": "♉︎", "gemini": "♊︎", "cancer": "♋︎", "leo": "♌︎", "virgo": "♍︎",
        "libra": "♎︎", "scorpio": "♏︎", "sagittarius": "♐︎", "capricorn": "♑︎", "aquarius": "♒︎", "pisces": "♓︎",
    ]

    public static func symbol(for card: DeckDefinition.Card) -> String? {
        func value(_ key: String) -> String? {
            if case .string(let s)? = card.attributes[key] { return s.lowercased() }
            return nil
        }
        if let a = value("attribution") { return astro[a] ?? elements[a] }
        if let e = value("element") { return elements[e] }
        if let s = value("suit"), let e = suits[s] { return elements[e] }
        return nil
    }

    public static func symbol(for sign: ZodiacSign) -> String { astro[sign.rawValue] ?? "" }
    public static func symbol(for planet: Planet) -> String { astro[planet.rawValue] ?? "" }
}

/// Short words for the timing line on records. Signs near a cusp get "≈".
public enum TimingText {
    public static func line(_ t: TimingContext) -> String {
        let cusp = t.nearCusp ? "≈" : ""
        var parts = [
            "\(phase(t.moonPhase)) moon \(t.moonIllumination)%",
            "☽ in \(cusp)\(t.moonSign.rawValue.capitalized)",
            "☉ in \(cusp)\(t.sunSign.rawValue.capitalized)",
        ]
        if let d = t.planetaryDay, let h = t.planetaryHour {
            parts.append("day of \(d.rawValue.capitalized), hour of \(h.rawValue.capitalized)")
        }
        return parts.joined(separator: " · ")
    }

    public static func phase(_ p: MoonPhase) -> String {
        p.rawValue.replacingOccurrences(of: "-", with: " ").capitalized
    }
}
