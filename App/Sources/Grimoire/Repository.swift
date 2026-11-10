import Foundation
import GrimoireCore
import GrimoireAppKit
import SwiftData

/// GrimoireCore's repository seam, stored in SwiftData. `data` is a snapshot
/// of everything, rebuilt after each write (fine at personal scale).
final class SwiftDataRepository: GrimoireRepository {
    let context: ModelContext
    private var cache: GrimoireData?
    /// Called after every write, so the app can refresh its views.
    var didChange: () -> Void = {}

    init(context: ModelContext) {
        self.context = context
    }

    /// Rows that would not decode, the last failed save, and whether writes are refused.
    /// Shown as a banner; any unreadable row pauses export pruning and the phone's library.
    private(set) var health = StoreHealth()

    var data: GrimoireData {
        if let cache { return cache }
        var d = GrimoireData()
        var unreadable: [StoreHealth.Unreadable] = []
        func rows<R: PersistentModel, T>(_ descriptor: FetchDescriptor<R>, _ kind: String, id: (R) -> String,
                                          _ decode: (R) throws -> T) -> [T] {
            fetch(descriptor).compactMap { row in
                do { return try decode(row) } catch {
                    unreadable.append(.init(kind: kind, id: id(row), reason: String(describing: error)))
                    return nil
                }
            }
        }
        d.entries = rows(FetchDescriptor<EntryRecord>(sortBy: [SortDescriptor(\.occurredAt)]), "entry", id: \.id) { try $0.decoded() }
        d.inquiries = rows(FetchDescriptor<InquiryRecord>(sortBy: [SortDescriptor(\.askedAt)]), "inquiry", id: \.id) { try $0.decoded() }
        d.inbox = rows(FetchDescriptor<InboxRecord>(sortBy: [SortDescriptor(\.id)]), "inbox item", id: \.id) { try $0.decoded() }
        d.volumes = rows(FetchDescriptor<VolumeRecord>(sortBy: [SortDescriptor(\.id)]), "volume", id: \.id) { try $0.decoded() }
        d.reminders = rows(FetchDescriptor<ReminderRecord>(sortBy: [SortDescriptor(\.dueOn)]), "reminder", id: \.id) { try $0.decoded() }
        d.corrections = rows(FetchDescriptor<CorrectionRecord>(sortBy: [SortDescriptor(\.at)]), "correction",
                             id: { String($0.at.timeIntervalSinceReferenceDate) }) { try $0.decoded() }
        if !unreadable.isEmpty, unreadable != health.unreadable {
            for u in unreadable { print("Grimoire: unreadable \(u.kind) \(u.id): \(u.reason)") }
        }
        health.unreadable = unreadable
        cache = d
        return d
    }

    /// Set at launch when the store was written by a newer Grimoire: every write is refused.
    func blockWrites(_ reason: String) {
        health.writesBlocked = reason
    }

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        do { return try context.fetch(descriptor) } catch {
            // A fetch that fails would read as "no records"; say so instead.
            health.saveError = "Reading \(T.self) failed: \(error.localizedDescription)"
            return []
        }
    }

    /// Runs one change and saves it. A failure is kept in `health` (the banner) and thrown to
    /// callers that need to know, such as ingest, which must not move a capture that was not saved.
    func write(_ change: () throws -> Void) throws {
        if let blocked = health.writesBlocked { throw RepositoryError.writesBlocked(blocked) }
        defer {
            cache = nil
            didChange()
        }
        do {
            try change()
            try context.save()
            health.saveError = nil
        } catch {
            health.saveError = error.localizedDescription
            print("Grimoire: save failed: \(error)")
            throw error
        }
    }

    /// The GrimoireRepository methods cannot throw; their failures show in the banner.
    private func attempt(_ change: () throws -> Void) {
        try? write(change)
    }

    private func upsert<R: PersistentModel>(_ existing: R?, update: (R) throws -> Void, insert: () throws -> R) throws {
        if let existing { try update(existing) } else { context.insert(try insert()) }
    }

    func save(_ entry: Entry) {
        attempt {
            let id = entry.id.string
            try upsert(fetch(FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == id })).first,
                       update: { try $0.update(entry) }, insert: { try Rows.make(entry) })
        }
    }

    func save(_ inquiry: Inquiry) {
        attempt {
            let id = inquiry.id.string
            try upsert(fetch(FetchDescriptor<InquiryRecord>(predicate: #Predicate { $0.id == id })).first,
                       update: { try $0.update(inquiry) }, insert: { try Rows.make(inquiry) })
        }
    }

    func save(_ volume: Volume) {
        attempt {
            let id = volume.id.string
            try upsert(fetch(FetchDescriptor<VolumeRecord>(predicate: #Predicate { $0.id == id })).first,
                       update: { try $0.update(volume) }, insert: { try Rows.make(volume) })
        }
    }

    func save(_ reminder: Reminder) {
        attempt {
            let id = reminder.id.string
            try upsert(fetch(FetchDescriptor<ReminderRecord>(predicate: #Predicate { $0.id == id })).first,
                       update: { try $0.update(reminder) }, insert: { try Rows.make(reminder) })
        }
    }

    func addToInbox(_ item: InboxItem) {
        attempt { try insertInbox(item) }
    }

    /// Ingest calls this: it throws when the item did not reach the database, so the capture
    /// file stays where it is and is tried again.
    func persistToInbox(_ item: InboxItem) throws {
        try write { try insertInbox(item) }
    }

    private func insertInbox(_ item: InboxItem) throws {
        let id = item.id.string
        try upsert(fetch(FetchDescriptor<InboxRecord>(predicate: #Predicate { $0.id == id })).first,
                   update: { try $0.update(item) }, insert: { try Rows.make(item) })
    }

    func removeFromInbox(_ id: ULID) {
        let key = id.string
        attempt {
            for row in fetch(FetchDescriptor<InboxRecord>(predicate: #Predicate { $0.id == key })) { context.delete(row) }
        }
    }

    func logCorrections(_ c: [CorrectionLogEntry]) {
        guard !c.isEmpty else { return }
        attempt {
            for entry in c { context.insert(try Rows.make(entry)) }
        }
    }

    /// Deletes a record the person chose to delete (entries, inquiries, volumes, reminders).
    func delete(_ id: ULID) {
        let key = id.string
        attempt {
            for row in fetch(FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == key })) { context.delete(row) }
            for row in fetch(FetchDescriptor<InquiryRecord>(predicate: #Predicate { $0.id == key })) { context.delete(row) }
            for row in fetch(FetchDescriptor<VolumeRecord>(predicate: #Predicate { $0.id == key })) { context.delete(row) }
            for row in fetch(FetchDescriptor<ReminderRecord>(predicate: #Predicate { $0.id == key || $0.targetId == key })) { context.delete(row) }
        }
    }
}

enum RepositoryError: LocalizedError {
    case writesBlocked(String)
    var errorDescription: String? {
        switch self { case .writesBlocked(let why): why }
    }
}
