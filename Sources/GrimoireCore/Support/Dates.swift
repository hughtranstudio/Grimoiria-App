import Foundation

/// An instant plus the IANA time zone where it was recorded (spec §2).
public struct ZonedDate: Hashable, Codable, Sendable {
    public var instant: Date
    public var timeZone: String

    public init(_ instant: Date, timeZone: String = TimeZone.current.identifier) {
        self.instant = instant
        self.timeZone = timeZone
    }

    public var zone: TimeZone { TimeZone(identifier: timeZone) ?? TimeZone(secondsFromGMT: 0)! }

    /// ISO 8601 with the local offset, e.g. 2026-10-28T08:14:00-07:00
    public var iso8601: String { GrimoireDateFormat.iso(instant, in: zone) }

    /// yyyy-MM-dd in the recorded zone.
    public var day: String { GrimoireDateFormat.day(instant, in: zone) }

    /// Parses an ISO 8601 string with offset. The zone is taken from `timeZone`
    /// when given, otherwise a fixed-offset zone is derived from the string.
    public static func parse(_ string: String, timeZone: String? = nil) -> ZonedDate? {
        guard let date = GrimoireDateFormat.parseISO(string) else { return nil }
        if let tz = timeZone { return ZonedDate(date, timeZone: tz) }
        return ZonedDate(date, timeZone: GrimoireDateFormat.offsetZoneIdentifier(string) ?? "UTC")
    }
}

public enum GrimoireDateFormat {
    public static func iso(_ date: Date, in zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return f.string(from: date)
    }

    public static func day(_ date: Date, in zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    public static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    /// For "…-07:00" returns a GMT-offset identifier usable by TimeZone(identifier:).
    static func offsetZoneIdentifier(_ s: String) -> String? {
        if s.hasSuffix("Z") { return "UTC" }
        guard s.count >= 6 else { return nil }
        let tail = String(s.suffix(6))
        guard let sign = tail.first, sign == "+" || sign == "-" else { return nil }
        let parts = tail.dropFirst().split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let seconds = (h * 3600 + m * 60) * (sign == "-" ? -1 : 1)
        return TimeZone(secondsFromGMT: seconds)?.identifier
    }
}
