import Foundation

/// The few counts Mission Control shows about the Grimoire: what is due, what is open, what waits in the Inbox,
/// and when practice last happened. Written as JSON for the vault's state file; nothing here is stored.
public struct StatusSummary: Codable, Equatable, Sendable {
    public var today: String
    /// Outcome check-ins due on or before today.
    public var checkInsDue: Int
    /// Inquiries still open (no outcome closes them).
    public var openInquiries: Int
    /// Inbox items waiting for you to confirm.
    public var inboxWaiting: Int
    /// The newest practice day (ritual, meditation or vision), yyyy-MM-dd, if any.
    public var lastPractice: String?
    /// Whether any practice is recorded for today.
    public var practicedToday: Bool

    public init(data: GrimoireData, today: String) {
        self.today = today
        checkInsDue = data.reminders.filter { $0.isDue(today: today) }.count
        openInquiries = data.inquiries.filter { $0.status == .open }.count
        inboxWaiting = data.inbox.count
        let practice: Set<EntryType> = [.ritual, .meditation, .vision]
        let days = data.entries.filter { practice.contains($0.type) }.map { $0.occurredAt.day }
        lastPractice = days.max()
        practicedToday = days.contains(today)
    }

    /// Stable, sorted JSON: one object, for `grimoire status --json` and the vault.
    public func json() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try e.encode(self)
    }
}
