import Foundation
import GrimoireCore
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

    var data: GrimoireData {
        if let cache { return cache }
        var d = GrimoireData()
        d.entries = fetch(FetchDescriptor<EntryRecord>(sortBy: [SortDescriptor(\.occurredAt)])).compactMap(\.value)
        d.inquiries = fetch(FetchDescriptor<InquiryRecord>(sortBy: [SortDescriptor(\.askedAt)])).compactMap(\.value)
        d.inbox = fetch(FetchDescriptor<InboxRecord>(sortBy: [SortDescriptor(\.id)])).compactMap(\.value)
        d.volumes = fetch(FetchDescriptor<VolumeRecord>(sortBy: [SortDescriptor(\.id)])).compactMap(\.value)
        d.reminders = fetch(FetchDescriptor<ReminderRecord>(sortBy: [SortDescriptor(\.dueOn)])).compactMap(\.value)
        d.corrections = fetch(FetchDescriptor<CorrectionRecord>(sortBy: [SortDescriptor(\.at)])).compactMap(\.value)
        cache = d
        return d
    }

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        (try? context.fetch(descriptor)) ?? []
    }

    private func commit() {
        try? context.save()
        cache = nil
        didChange()
    }

    func save(_ entry: Entry) {
        let id = entry.id.string
        if let row = fetch(FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == id })).first {
            row.value = entry
        } else {
            context.insert(EntryRecord(entry))
        }
        commit()
    }

    func save(_ inquiry: Inquiry) {
        let id = inquiry.id.string
        if let row = fetch(FetchDescriptor<InquiryRecord>(predicate: #Predicate { $0.id == id })).first {
            row.value = inquiry
        } else {
            context.insert(InquiryRecord(inquiry))
        }
        commit()
    }

    func save(_ volume: Volume) {
        let id = volume.id.string
        if let row = fetch(FetchDescriptor<VolumeRecord>(predicate: #Predicate { $0.id == id })).first {
            row.value = volume
        } else {
            context.insert(VolumeRecord(volume))
        }
        commit()
    }

    func save(_ reminder: Reminder) {
        let id = reminder.id.string
        if let row = fetch(FetchDescriptor<ReminderRecord>(predicate: #Predicate { $0.id == id })).first {
            row.value = reminder
        } else {
            context.insert(ReminderRecord(reminder))
        }
        commit()
    }

    func addToInbox(_ item: InboxItem) {
        let id = item.id.string
        if let row = fetch(FetchDescriptor<InboxRecord>(predicate: #Predicate { $0.id == id })).first {
            row.value = item
        } else {
            context.insert(InboxRecord(item))
        }
        commit()
    }

    func removeFromInbox(_ id: ULID) {
        let key = id.string
        for row in fetch(FetchDescriptor<InboxRecord>(predicate: #Predicate { $0.id == key })) { context.delete(row) }
        commit()
    }

    func logCorrections(_ c: [CorrectionLogEntry]) {
        guard !c.isEmpty else { return }
        for entry in c { context.insert(CorrectionRecord(entry)) }
        commit()
    }

    /// Deletes a record the person chose to delete (entries, inquiries, volumes, reminders).
    func delete(_ id: ULID) {
        let key = id.string
        for row in fetch(FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == key })) { context.delete(row) }
        for row in fetch(FetchDescriptor<InquiryRecord>(predicate: #Predicate { $0.id == key })) { context.delete(row) }
        for row in fetch(FetchDescriptor<VolumeRecord>(predicate: #Predicate { $0.id == key })) { context.delete(row) }
        for row in fetch(FetchDescriptor<ReminderRecord>(predicate: #Predicate { $0.id == key || $0.targetId == key })) { context.delete(row) }
        commit()
    }
}
