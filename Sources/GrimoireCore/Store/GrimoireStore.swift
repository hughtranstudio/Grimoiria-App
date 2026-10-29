import Foundation

/// Everything the app stores. The Mac app keeps this in SwiftData behind `GrimoireRepository`;
/// this value type is also the on-disk format of the CLI's JSON store and the export input.
public struct GrimoireData: Codable, Sendable, Equatable {
    public var entries: [Entry] = []
    public var inquiries: [Inquiry] = []
    public var inbox: [InboxItem] = []
    public var volumes: [Volume] = []
    public var reminders: [Reminder] = []
    public var corrections: [CorrectionLogEntry] = []
    public init() {}
}

/// All model access goes through this protocol so a move from SwiftData to GRDB/SQLite later
/// touches one module (spec §2). Writes never delete user records except Inbox items on confirm.
public protocol GrimoireRepository: AnyObject {
    var data: GrimoireData { get }
    func save(_ entry: Entry)
    func save(_ inquiry: Inquiry)
    func save(_ volume: Volume)
    func save(_ reminder: Reminder)
    func addToInbox(_ item: InboxItem)
    func removeFromInbox(_ id: ULID)
    func logCorrections(_ c: [CorrectionLogEntry])
}

public extension GrimoireRepository {
    func entry(_ id: ULID) -> Entry? { data.entries.first { $0.id == id } }
    func inquiry(_ id: ULID) -> Inquiry? { data.inquiries.first { $0.id == id } }
    func volume(_ id: ULID) -> Volume? { data.volumes.first { $0.id == id } }

    /// True if a phone capture with this id is already in the Inbox or filed (idempotent ingest).
    func knowsCapture(_ captureId: String) -> Bool {
        data.inbox.contains { $0.entry.captureId == captureId } || data.entries.contains { $0.captureId == captureId }
    }

    /// Confirms an Inbox item and files the results in one step.
    @discardableResult
    func confirm(_ itemId: ULID, corrected: DraftReading?, entryType: EntryType? = nil, library: DefinitionLibrary,
                 reminder: ReminderPreset = .none, now: Date = Date()) throws -> ConfirmResult {
        guard let item = data.inbox.first(where: { $0.id == itemId }) else { throw StoreError.notFound(itemId.string) }
        let result = try Confirmation.confirm(item, corrected: corrected, entryType: entryType, library: library, now: now)
        if let inq = result.inquiry {
            save(inq)
            scheduleOutcomeCheckIn(for: inq, preset: reminder, today: GrimoireDateFormat.day(now, in: inq.askedAt.zone))
        }
        save(result.entry)
        logCorrections(result.corrections)
        removeFromInbox(itemId)
        return result
    }

    /// Reminders due on or before `today` (yyyy-MM-dd), for the Today screen's "Needs outcome".
    func needsOutcome(today: String) -> [Reminder] {
        data.reminders.filter { $0.isDue(today: today) }.sorted { ($0.dueOn, $0.id) < ($1.dueOn, $1.id) }
    }

    /// Creates the outcome reminder for an Inquiry unless it already has an open one.
    @discardableResult
    func scheduleOutcomeCheckIn(for inquiry: Inquiry, preset: ReminderPreset = .ladder, today: String) -> Reminder? {
        guard !data.reminders.contains(where: { $0.targetId == inquiry.id && $0.status != .done }),
              let r = OutcomeCheckIn.reminder(for: inquiry.id, askedOn: inquiry.askedAt.day, today: today, preset: preset) else { return nil }
        save(r)
        return r
    }

    /// Stacks an outcome on an Inquiry and completes the reminders it answers: those due on or before
    /// the outcome's day. A ladder then rolls on to its next check-in, so later outcomes layer on.
    @discardableResult
    func addOutcome(_ outcome: Outcome, to inquiryId: ULID, now: Date = Date()) throws -> Inquiry {
        guard var inq = inquiry(inquiryId) else { throw StoreError.notFound(inquiryId.string) }
        inq.addOutcome(outcome)
        inq.updatedAt = now
        save(inq)
        for var r in data.reminders where r.targetId == inquiryId && r.status != .done && r.dueOn <= outcome.recordedAt.day {
            r.complete()
            save(r)
        }
        return inq
    }

    /// "No more nudges" for this record: every open reminder on it is marked done.
    func stopReminders(for targetId: ULID) {
        for var r in data.reminders where r.targetId == targetId && r.status != .done {
            r.status = .done
            save(r)
        }
    }

    /// Backfill for imported or older readings: open Inquiries with no outcome and no reminder yet
    /// get a check-in, starting at the latest step already past (see `OutcomeCheckIn.reminder`).
    @discardableResult
    func backfillOutcomeCheckIns(today: String, preset: ReminderPreset = .ladder) -> [Reminder] {
        let reminded = Set(data.reminders.map(\.targetId))
        return data.inquiries
            .filter { $0.outcomes.isEmpty && $0.status == .open && !reminded.contains($0.id) }
            .sorted { $0.id < $1.id }
            .compactMap { scheduleOutcomeCheckIn(for: $0, preset: preset, today: today) }
    }

    /// Records that link to `id` (backlinks, spec §6).
    func backlinks(to id: ULID) -> [(source: ULID, kind: Link.Kind)] {
        var out: [(ULID, Link.Kind)] = []
        for e in data.entries { for l in e.links where l.target == id.string { out.append((e.id, l.kind)) } }
        return out.sorted { $0.0 < $1.0 }
    }

    var tagTree: TagTree {
        var all: [TagPath] = data.entries.flatMap(\.tags)
        for i in data.inquiries {
            all += i.tags
            if let c = i.category { all.append(c) }
            for d in i.divinations { for w in d.draws { all += w.tags } }
        }
        return TagTree(all)
    }
}

public enum StoreError: Error, CustomStringConvertible {
    case notFound(String)
    public var description: String { switch self { case .notFound(let id): return "Not found: \(id)" } }
}

/// In-memory repository, used by tests and as the base of the JSON file store.
public class MemoryRepository: GrimoireRepository {
    public private(set) var data: GrimoireData
    public init(_ data: GrimoireData = GrimoireData()) { self.data = data }

    func upsert<T: Identifiable>(_ list: inout [T], _ value: T) where T.ID == ULID {
        if let i = list.firstIndex(where: { $0.id == value.id }) { list[i] = value } else { list.append(value) }
    }

    public func save(_ entry: Entry) { upsert(&data.entries, entry) }
    public func save(_ inquiry: Inquiry) { upsert(&data.inquiries, inquiry) }
    public func save(_ volume: Volume) { upsert(&data.volumes, volume) }
    public func save(_ reminder: Reminder) { upsert(&data.reminders, reminder) }
    public func addToInbox(_ item: InboxItem) { upsert(&data.inbox, item) }
    public func removeFromInbox(_ id: ULID) { data.inbox.removeAll { $0.id == id } }
    public func logCorrections(_ c: [CorrectionLogEntry]) { data.corrections.append(contentsOf: c) }
}

/// A single JSON file store for the CLI and for tests on Linux.
public final class JSONFileRepository: MemoryRepository {
    public let url: URL

    public init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .custom { d in
                let raw = try d.singleValueContainer().decode(String.self)
                guard let date = GrimoireDateFormat.parseISO(raw) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "bad date \(raw)"))
                }
                return date
            }
            super.init(try dec.decode(GrimoireData.self, from: Data(contentsOf: url)))
        } else {
            super.init()
        }
    }

    public func flush() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Millisecond precision so timestamps survive a round trip closely.
        enc.dateEncodingStrategy = .custom { date, e in
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var c = e.singleValueContainer()
            try c.encode(f.string(from: date))
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try enc.encode(data).write(to: url, options: .atomic)
    }
}
