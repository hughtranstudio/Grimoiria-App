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

    // The ecosystem's status card (my-website ecosystem/README.md): the same shape every app writes,
    // `{ app, format, written, ok, headline, needs_you, counts{}, links{} }`. Counts and links only.
    public var app: String
    /// The day these counts were taken (yyyy-MM-dd), so a reader can tell a stale card.
    public var written: String
    public var ok: Bool
    /// One plain line for the Chamber and the Back office.
    public var headline: String
    /// What waits on you: captures to confirm plus check-ins due.
    public var needs_you: Int
    public var counts: [String: Int]
    public var links: [String: String]
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
        app = "grimoiria"
        written = today
        ok = true
        needs_you = inboxWaiting + checkInsDue
        var counts = ["inbox": inboxWaiting, "checkInsDue": checkInsDue, "openInquiries": openInquiries]
        if let nudges { counts["nudges"] = nudges }
        self.counts = counts
        links = ["open": GrimoireLink.today.url.absoluteString, "inbox": GrimoireLink.inbox(nil).url.absoluteString]
        headline = Self.headline(inbox: inboxWaiting, oldestDays: inboxOldestDays, due: checkInsDue,
                                 practicedToday: practicedToday, lastPractice: lastPractice)
    }

    /// "9 in the Inbox (oldest 6 days), 1 check-in due, last practice 2026-10-29".
    static func headline(inbox: Int, oldestDays: Int?, due: Int, practicedToday: Bool, lastPractice: String?) -> String {
        var bits: [String] = []
        if inbox > 0 {
            let age = oldestDays.map { $0 == 0 ? " (from today)" : " (oldest \($0) day\($0 == 1 ? "" : "s"))" } ?? ""
            bits.append("\(inbox) in the Inbox\(age)")
        }
        if due > 0 { bits.append("\(due) check-in\(due == 1 ? "" : "s") due") }
        bits.append(practicedToday ? "practised today" : lastPractice.map { "last practice \($0)" } ?? "no practice recorded yet")
        return bits.joined(separator: ", ")
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
