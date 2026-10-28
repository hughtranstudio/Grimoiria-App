import Foundation

/// Outcome reminders (spec §4): layer and backfill insight over time.
public struct Reminder: Codable, Hashable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable { case pending, done, snoozed }
    public enum Repeat: String, Codable, Sendable { case none, weekly, monthly }

    public var id: ULID
    /// The Inquiry or Entry this reminder is about.
    public var targetId: ULID
    /// Calendar day the reminder is due (yyyy-MM-dd in the user's zone).
    public var dueOn: String
    public var prompt: String?
    public var status: Status
    public var `repeat`: Repeat

    public init(id: ULID = ULID(), targetId: ULID, dueOn: String, prompt: String? = nil, status: Status = .pending, repeat: Repeat = .none) {
        self.id = id
        self.targetId = targetId
        self.dueOn = dueOn
        self.prompt = prompt
        self.status = status
        self.repeat = `repeat`
    }

    public func isDue(today: String) -> Bool { status != .done && dueOn <= today }

    /// Snooze moves the due day forward and keeps it pending.
    public mutating func snooze(days: Int, calendar: Calendar = .grimoire) {
        dueOn = ReminderPreset.add(days: days, to: dueOn, calendar: calendar)
        status = .snoozed
    }

    /// Marks done; repeating reminders roll forward and stay pending.
    public mutating func complete(calendar: Calendar = .grimoire) {
        switch `repeat` {
        case .none: status = .done
        case .weekly: dueOn = ReminderPreset.add(days: 7, to: dueOn, calendar: calendar); status = .pending
        case .monthly: dueOn = ReminderPreset.add(months: 1, to: dueOn, calendar: calendar); status = .pending
        }
    }
}

/// Presets offered when creating an Inquiry. The default is still an open question for Hugh (spec §16.3).
public enum ReminderPreset: String, CaseIterable, Sendable {
    case none, oneWeek = "1w", oneMonth = "1m", threeMonths = "3m"

    public func dueOn(from day: String, calendar: Calendar = .grimoire) -> String? {
        switch self {
        case .none: return nil
        case .oneWeek: return Self.add(days: 7, to: day, calendar: calendar)
        case .oneMonth: return Self.add(months: 1, to: day, calendar: calendar)
        case .threeMonths: return Self.add(months: 3, to: day, calendar: calendar)
        }
    }

    static func parse(_ day: String, calendar: Calendar) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: day)
    }

    static func format(_ date: Date, calendar: Calendar) -> String {
        GrimoireDateFormat.day(date, in: calendar.timeZone)
    }

    static func add(days: Int = 0, months: Int = 0, to day: String, calendar: Calendar) -> String {
        guard let d = parse(day, calendar: calendar),
              let r = calendar.date(byAdding: DateComponents(month: months, day: days), to: d) else { return day }
        return format(r, calendar: calendar)
    }
}

public extension Calendar {
    /// Gregorian calendar in UTC, used for pure day arithmetic.
    static var grimoire: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }
}
