import Foundation
import GrimoireCore
import SwiftData

/// SwiftData rows for the GrimoireCore value types. Each row keeps the whole
/// value as JSON (`payload`) plus the few columns that are queried or
/// indexed. `init(_ value:)` and `value` convert both ways, so the rest of
/// the app works with the tested GrimoireCore structs only.
nonisolated enum Records {
    static let all: [any PersistentModel.Type] = [
        EntryRecord.self, InquiryRecord.self, VolumeRecord.self, ReminderRecord.self, InboxRecord.self, CorrectionRecord.self,
    ]

    static func encode<T: Encodable>(_ value: T) -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        // Dates as plain numbers round-trip exactly.
        return (try? enc.encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
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

    init(_ value: Entry) {
        id = value.id.string
        type = value.type.rawValue
        occurredAt = value.occurredAt.instant
        captureId = value.captureId
        status = value.status.rawValue
        payload = Records.encode(value)
    }

    var value: Entry? {
        get { Records.decode(Entry.self, payload) }
        set {
            guard let v = newValue else { return }
            type = v.type.rawValue
            occurredAt = v.occurredAt.instant
            captureId = v.captureId
            status = v.status.rawValue
            payload = Records.encode(v)
        }
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

    init(_ value: Inquiry) {
        id = value.id.string
        askedAt = value.askedAt.instant
        status = value.status.rawValue
        payload = Records.encode(value)
    }

    var value: Inquiry? {
        get { Records.decode(Inquiry.self, payload) }
        set {
            guard let v = newValue else { return }
            askedAt = v.askedAt.instant
            status = v.status.rawValue
            payload = Records.encode(v)
        }
    }
}

@Model
final class VolumeRecord {
    #Index<VolumeRecord>([\.id])
    @Attribute(.unique) var id: String
    var payload: Data

    init(_ value: Volume) {
        id = value.id.string
        payload = Records.encode(value)
    }

    var value: Volume? {
        get { Records.decode(Volume.self, payload) }
        set { if let v = newValue { payload = Records.encode(v) } }
    }
}

@Model
final class ReminderRecord {
    #Index<ReminderRecord>([\.id], [\.dueOn], [\.status])
    @Attribute(.unique) var id: String
    var targetId: String
    var dueOn: String
    var status: String
    var payload: Data

    init(_ value: Reminder) {
        id = value.id.string
        targetId = value.targetId.string
        dueOn = value.dueOn
        status = value.status.rawValue
        payload = Records.encode(value)
    }

    var value: Reminder? {
        get { Records.decode(Reminder.self, payload) }
        set {
            guard let v = newValue else { return }
            targetId = v.targetId.string
            dueOn = v.dueOn
            status = v.status.rawValue
            payload = Records.encode(v)
        }
    }
}

/// A capture waiting in the Inbox: the inbox Entry plus its parsed draft.
@Model
final class InboxRecord {
    #Index<InboxRecord>([\.id], [\.captureId])
    @Attribute(.unique) var id: String
    var captureId: String?
    var payload: Data

    init(_ value: InboxItem) {
        id = value.id.string
        captureId = value.entry.captureId
        payload = Records.encode(value)
    }

    var value: InboxItem? {
        get { Records.decode(InboxItem.self, payload) }
        set {
            guard let v = newValue else { return }
            captureId = v.entry.captureId
            payload = Records.encode(v)
        }
    }
}

/// One heard → corrected change from the Inbox, for growing the parser's aliases.
@Model
final class CorrectionRecord {
    #Index<CorrectionRecord>([\.at])
    var at: Date
    var payload: Data

    init(_ value: CorrectionLogEntry) {
        at = value.at
        payload = Records.encode(value)
    }

    var value: CorrectionLogEntry? { Records.decode(CorrectionLogEntry.self, payload) }
}

/// SwiftUI has its own Link; in this app Link means a GrimoireCore record link.
typealias Link = GrimoireCore.Link
