import Foundation

/// One event for an outside calendar. Carries timing and a link back to the record, never its text:
/// whatever lands in Google or Apple Calendar leaves the device, so the reading stays in Grimoire.
public struct CalendarEvent: Hashable, Sendable {
    public enum When: Hashable, Sendable {
        /// A timed event; no `end` means a moment (a lunation, an ingress).
        case timed(start: Date, end: Date?)
        /// An all-day event on a yyyy-MM-dd day.
        case allDay(String)
    }

    /// Stable across exports, so importing the file again updates events instead of duplicating them.
    public var uid: String
    public var summary: String
    public var when: When
    /// `grimoire://entry/<id>` or `grimoire://inquiry/<id>`.
    public var url: String?
    public var categories: [String]
    /// False for sky events and planetary hours, so they don't mark the time as busy.
    public var busy: Bool

    public init(uid: String, summary: String, when: When, url: String? = nil, categories: [String] = [], busy: Bool = true) {
        self.uid = uid; self.summary = summary; self.when = when; self.url = url; self.categories = categories; self.busy = busy
    }
}

/// Planned rituals, outcome check-ins, lunations and chosen planetary hours as an iCalendar (.ics) file
/// that Google Calendar, Apple Calendar or any other calendar can import (RFC 5545).
public struct CalendarExporter: Sendable {
    public var from: Date
    public var to: Date
    public var zone: TimeZone
    /// Rituals dated in the window, with or without a reading attached.
    public var rituals = true
    /// Open outcome check-ins due in the window.
    public var checkIns = true
    /// Which sky events to add. Lunar phases by default; the Moon changes sign every two to three days.
    public var sky: Set<SkyEvent.Kind> = [.newMoon, .firstQuarter, .fullMoon, .lastQuarter]
    /// Planetary hours to add, e.g. [.venus]. Needs `location`.
    public var hoursOf: [Planet] = []
    /// Only hours on the planet's own day (an hour of Venus on a Friday).
    public var hoursOnTheirDay = false
    public var location: GeoLocation?
    /// Length given to a ritual with no `durationMin`.
    public var defaultRitualMinutes = 60

    public init(from: Date, to: Date, zone: TimeZone) {
        self.from = from; self.to = to; self.zone = zone
    }

    /// The window `days` long starting at midnight of `first` (yyyy-MM-dd) in `zone`.
    public init?(first: String, days: Int, zone: TimeZone) {
        guard let start = RitualCalendar.start(of: first, zone: zone),
              let end = RitualCalendar.calendar(zone).date(byAdding: .day, value: max(1, days), to: start) else { return nil }
        self.init(from: start, to: end, zone: zone)
    }

    public func events(for data: GrimoireData) -> [CalendarEvent] {
        var out: [CalendarEvent] = []
        if rituals {
            for e in data.entries where e.type == .ritual && e.status == .filed && e.occurredAt.instant >= from && e.occurredAt.instant < to {
                let minutes = e.fields.durationMin.flatMap { $0 > 0 ? $0 : nil } ?? defaultRitualMinutes
                var summary = "Ritual"
                if let hour = e.timing?.planetaryHour { summary += " · hour of \(hour.rawValue.capitalized)" }
                out.append(CalendarEvent(uid: "ritual-\(e.id)@grimoire", summary: summary,
                                         when: .timed(start: e.occurredAt.instant, end: e.occurredAt.instant.addingTimeInterval(Double(minutes) * 60)),
                                         url: "grimoire://entry/\(e.id)", categories: ["Grimoire", "Ritual"]))
            }
        }
        if checkIns {
            let first = RitualCalendar.dayString(from, zone: zone), last = RitualCalendar.dayString(to.addingTimeInterval(-1), zone: zone)
            let inquiries = Set(data.inquiries.map(\.id))
            for r in data.reminders where r.status != .done && r.dueOn >= first && r.dueOn <= last {
                let kind = inquiries.contains(r.targetId) ? "inquiry" : "entry"
                out.append(CalendarEvent(uid: "checkin-\(r.id)@grimoire", summary: r.step.map { "Outcome check-in (\($0) days)" } ?? "Outcome check-in",
                                         when: .allDay(r.dueOn), url: "grimoire://\(kind)/\(r.targetId)", categories: ["Grimoire", "Check-in"], busy: false))
            }
        }
        if !sky.isEmpty {
            for s in RitualCalendar.events(from: from, to: to, kinds: sky) {
                out.append(CalendarEvent(uid: "sky-\(s.kind.rawValue)-\(GrimoireDateFormat.day(s.at, in: TimeZone(secondsFromGMT: 0)!))@grimoire",
                                         summary: s.title, when: .timed(start: s.at, end: nil), categories: ["Grimoire", "Sky"], busy: false))
            }
        }
        if let location, !hoursOf.isEmpty {
            let days = Int(to.timeIntervalSince(from) / 86_400) + 2
            for planet in hoursOf {
                for h in RitualCalendar.nextHours(of: planet, after: from, location: location, zone: zone, onItsDay: hoursOnTheirDay,
                                                  limit: days * 4, searchDays: days) where h.start < to {
                    out.append(CalendarEvent(uid: "hour-\(planet.rawValue)-\(Self.stamp(h.start).prefix(13))@grimoire",
                                             summary: "Hour of \(planet.rawValue.capitalized)", when: .timed(start: h.start, end: h.end),
                                             categories: ["Grimoire", "Planetary hour"], busy: false))
                }
            }
        }
        return out.sorted { (Self.sortKey($0.when), $0.uid) < (Self.sortKey($1.when), $1.uid) }
    }

    /// The whole .ics file. `now` is the DTSTAMP, so tests can pin it.
    public func ics(for data: GrimoireData, name: String = "Grimoire", now: Date = Date()) -> String {
        Self.ics(events(for: data), name: name, now: now)
    }

    public static func ics(_ events: [CalendarEvent], name: String = "Grimoire", now: Date = Date()) -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Grimoire//Grimoire Calendar Export//EN", "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
                     "X-WR-CALNAME:\(escape(name))"]
        for e in events {
            lines += ["BEGIN:VEVENT", "UID:\(escape(e.uid))", "DTSTAMP:\(stamp(now))"]
            switch e.when {
            case .timed(let start, let end):
                lines.append("DTSTART:\(stamp(start))")
                if let end { lines.append("DTEND:\(stamp(end))") }
            case .allDay(let day):
                lines.append("DTSTART;VALUE=DATE:\(day.replacingOccurrences(of: "-", with: ""))")
                if let next = nextDay(day) { lines.append("DTEND;VALUE=DATE:\(next)") }
            }
            lines.append("SUMMARY:\(escape(e.summary))")
            if let url = e.url { lines.append("URL:\(url)") }
            if !e.categories.isEmpty { lines.append("CATEGORIES:\(e.categories.map(escape).joined(separator: ","))") }
            lines += ["TRANSP:\(e.busy ? "OPAQUE" : "TRANSPARENT")", "END:VEVENT"]
        }
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    /// UTC date-time, e.g. 20261105T134700Z.
    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    static func nextDay(_ day: String) -> String? {
        let next = ReminderPreset.add(days: 1, to: day, calendar: .grimoire)
        return next == day ? nil : next.replacingOccurrences(of: "-", with: "")
    }

    static func sortKey(_ w: CalendarEvent.When) -> String {
        switch w {
        case .timed(let start, _): return stamp(start)
        case .allDay(let day): return day.replacingOccurrences(of: "-", with: "") + "T000000Z"
        }
    }

    /// TEXT escaping (RFC 5545 §3.3.11).
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\r\n", with: "\\n").replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Lines longer than 75 octets continue on the next line after a space (RFC 5545 §3.1),
    /// split between characters so a multi-byte character is never cut.
    static func fold(_ line: String) -> String {
        guard line.utf8.count > 75 else { return line }
        var parts: [String] = [], current = "", size = 0
        for ch in line {
            let n = String(ch).utf8.count
            let limit = parts.isEmpty ? 75 : 74
            if size + n > limit { parts.append(current); current = ""; size = 0 }
            current.append(ch); size += n
        }
        parts.append(current)
        return parts.joined(separator: "\r\n ")
    }
}
