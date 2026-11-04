import Foundation

/// The few counts Mission Control shows about the Grimoire: what is due, what is open, what waits in the Inbox,
/// what keeps coming back, and when practice last happened. Counts only, never questions or readings, because
/// Mission Control's snapshot leaves the Mac. Written as `grimoire-status.json` beside the Obsidian export.
public struct StatusSummary: Codable, Equatable, Sendable {
    public static let fileName = "grimoire-status.json"
    public static let formatVersion = 1

    public var format: Int
    public var today: String
    /// Outcome check-ins due on or before today.
    public var checkInsDue: Int
    /// Inquiries still open (no outcome closes them).
    public var openInquiries: Int
    /// Inbox items waiting for you to confirm.
    public var inboxWaiting: Int
    /// The day the oldest waiting capture was made, yyyy-MM-dd; nil when the Inbox is empty.
    public var inboxOldest: String?
    /// Whole days that capture has waited, so "Needs you" can say "9 waiting, oldest 6 days".
    public var inboxOldestDays: Int?
    /// Where a click on the Inbox line goes: `grimoire://inbox`, which opens the Mac app's Inbox.
    public var inboxLink: String
    /// The newest practice day (ritual, meditation or vision), yyyy-MM-dd, if any.
    public var lastPractice: String?
    /// Whether any practice is recorded for today.
    public var practicedToday: Bool
    /// Cards, hexagrams and symbols coming back right now (see `Patterns.nudges`); nil without the definitions.
    public var nudges: Int?

    public init(data: GrimoireData, today: String, library: DefinitionLibrary? = nil) {
        format = Self.formatVersion
        self.today = today
        checkInsDue = data.reminders.filter { $0.isDue(today: today) }.count
        openInquiries = data.inquiries.filter { $0.status == .open }.count
        inboxWaiting = data.inbox.count
        inboxOldest = data.inbox.map { $0.entry.createdAt }.min().map { GrimoireDateFormat.day($0, in: .current) }
        inboxOldestDays = inboxOldest.flatMap { Self.days(from: $0, to: today) }
        inboxLink = GrimoireLink.inbox(nil).url.absoluteString
        let practice: Set<EntryType> = [.ritual, .meditation, .vision]
        let days = data.entries.filter { practice.contains($0.type) }.map { $0.occurredAt.day }
        lastPractice = days.max()
        practicedToday = days.contains(today)
        nudges = library.map { Patterns(data: data, library: $0).nudges(today: today).count }
    }

    /// Whole days between two yyyy-MM-dd days; never negative.
    static func days(from start: String, to end: String) -> Int? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        func parse(_ s: String) -> Date? {
            let p = s.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3 else { return nil }
            return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
        }
        guard let a = parse(start), let b = parse(end),
              let n = cal.dateComponents([.day], from: a, to: b).day else { return nil }
        return max(0, n)
    }

    /// Stable, sorted JSON: one object, for `grimoire status --json` and the vault.
    public func json() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try e.encode(self)
    }
}
