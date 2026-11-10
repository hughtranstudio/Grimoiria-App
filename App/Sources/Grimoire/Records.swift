import Foundation
import GrimoireCore
import SwiftData

/// SwiftData rows for the GrimoireCore value types. Each row keeps the whole
/// value as JSON (`payload`) plus the few columns that are queried or
/// indexed. `Rows.make`, `decoded()` and `update(_:)` convert both ways and throw
/// rather than lose data, so the rest of the app works with the tested GrimoireCore structs only.
nonisolated enum Records {
    static let all: [any PersistentModel.Type] = [
        EntryRecord.self, InquiryRecord.self, VolumeRecord.self, ReminderRecord.self, InboxRecord.self, CorrectionRecord.self,
    ]

    /// Throws instead of writing an empty payload: a record that cannot be encoded keeps the
    /// payload it had, and the caller reports the failure.
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        // Dates as plain numbers round-trip exactly.
        let data = try enc.encode(value)
        guard !data.isEmpty else { throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "empty payload")) }
        return data
    }

    /// Throws so the repository can list the row as unreadable instead of dropping it.
    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}

/// New rows, encoded first so a value that cannot be encoded never becomes a row.
enum Rows {
    static func make(_ v: Entry) throws -> EntryRecord { EntryRecord(v, payload: try Records.encode(v)) }
    static func make(_ v: Inquiry) throws -> InquiryRecord { InquiryRecord(v, payload: try Records.encode(v)) }
    static func make(_ v: Volume) throws -> VolumeRecord { VolumeRecord(v, payload: try Records.encode(v)) }
    static func make(_ v: Reminder) throws -> ReminderRecord { ReminderRecord(v, payload: try Records.encode(v)) }
    static func make(_ v: InboxItem) throws -> InboxRecord { InboxRecord(v, payload: try Records.encode(v)) }
    static func make(_ v: CorrectionLogEntry) throws -> CorrectionRecord { CorrectionRecord(v, payload: try Records.encode(v)) }
}

@Model
final class EntryRecord {
    #Index<EntryRecord>([\.id], [\.occurredAt], [\.captureId], [\.status])
    @Attribute(.unique) var id: String
    var type: String
    var occurredAt: Date
    var captureId: String?
    var status: String
    var payload: Data

    /// Encode first (`Rows.make`), so a value that cannot be encoded never becomes a row.
    init(_ value: Entry, payload: Data) {
        id = value.id.string
        type = value.type.rawValue
        occurredAt = value.occurredAt.instant
        captureId = value.captureId
        status = value.status.rawValue
        self.payload = payload
    }

    func decoded() throws -> Entry { try Records.decode(Entry.self, payload) }

    /// Encodes first, so a failure leaves the row exactly as it was.
    func update(_ v: Entry) throws {
        let data = try Records.encode(v)
        type = v.type.rawValue
        occurredAt = v.occurredAt.instant
        captureId = v.captureId
        status = v.status.rawValue
        payload = data
    }
}

/// An Inquiry with its divinations, draws, casts, synthesis and outcomes.
@Model
final class InquiryRecord {
    #Index<InquiryRecord>([\.id], [\.askedAt], [\.status])
    @Attribute(.unique) var id: String
    var askedAt: Date
    var status: String
    var payload: Data

    /// Encode first (`Rows.make`), so a value that cannot be encoded never becomes a row.
    init(_ value: Inquiry, payload: Data) {
        id = value.id.string
        askedAt = value.askedAt.instant
        status = value.status.rawValue
        self.payload = payload
    }

    func decoded() throws -> Inquiry { try Records.decode(Inquiry.self, payload) }

    /// Encodes first, so a failure leaves the row exactly as it was.
    func update(_ v: Inquiry) throws {
        let data = try Records.encode(v)
        askedAt = v.askedAt.instant
        status = v.status.rawValue
        payload = data
    }
}

@Model
final class VolumeRecord {
    #Index<VolumeRecord>([\.id])
    @Attribute(.unique) var id: String
    var payload: Data

    /// Encode first (`Rows.make`), so a value that cannot be encoded never becomes a row.
    init(_ value: Volume, payload: Data) {
        id = value.id.string
        self.payload = payload
    }

    func decoded() throws -> Volume { try Records.decode(Volume.self, payload) }

    func update(_ v: Volume) throws { payload = try Records.encode(v) }
}

@Model
final class ReminderRecord {
    #Index<ReminderRecord>([\.id], [\.dueOn], [\.status])
    @Attribute(.unique) var id: String
    var targetId: String
    var dueOn: String
    var status: String
    var payload: Data

    /// Encode first (`Rows.make`), so a value that cannot be encoded never becomes a row.
    init(_ value: Reminder, payload: Data) {
        id = value.id.string
        targetId = value.targetId.string
        dueOn = value.dueOn
        status = value.status.rawValue
        self.payload = payload
    }

    func decoded() throws -> Reminder { try Records.decode(Reminder.self, payload) }

    /// Encodes first, so a failure leaves the row exactly as it was.
    func update(_ v: Reminder) throws {
        let data = try Records.encode(v)
        targetId = v.targetId.string
        dueOn = v.dueOn
        status = v.status.rawValue
        payload = data
    }
}

/// A capture waiting in the Inbox: the inbox Entry plus its parsed draft.
@Model
final class InboxRecord {
    #Index<InboxRecord>([\.id], [\.captureId])
    @Attribute(.unique) var id: String
    var captureId: String?
    var payload: Data

    /// Encode first (`Rows.make`), so a value that cannot be encoded never becomes a row.
    init(_ value: InboxItem, payload: Data) {
        id = value.id.string
        captureId = value.entry.captureId
        self.payload = payload
    }

    func decoded() throws -> InboxItem { try Records.decode(InboxItem.self, payload) }

    /// Encodes first, so a failure leaves the row exactly as it was.
    func update(_ v: InboxItem) throws {
        let data = try Records.encode(v)
        captureId = v.entry.captureId
        payload = data
    }
}

/// One heard → corrected change from the Inbox, for growing the parser's aliases.
@Model
final class CorrectionRecord {
    #Index<CorrectionRecord>([\.at])
    var at: Date
    var payload: Data

    /// Encode first (`Rows.make`), so a value that cannot be encoded never becomes a row.
    init(_ value: CorrectionLogEntry, payload: Data) {
        at = value.at
        self.payload = payload
    }

    func decoded() throws -> CorrectionLogEntry { try Records.decode(CorrectionLogEntry.self, payload) }
}

/// SwiftUI has its own Link; in this app Link means a GrimoireCore record link.
typealias Link = GrimoireCore.Link
