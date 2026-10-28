import Foundation

/// The centre of all divination (spec §4). A compound reading is one Inquiry with several Divinations.
public struct Inquiry: Codable, Hashable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable { case open, resolved, revisited }

    public var id: ULID
    public var question: String
    public var askedAt: ZonedDate
    public var context: String
    /// Tag under `question/…`.
    public var category: TagPath?
    public var status: Status
    public var tags: [TagPath]
    public var divinations: [Divination]
    public var synthesis: Synthesis?
    public var outcomes: [Outcome]
    public var physicalRef: PhysicalRef?
    public var timing: TimingContext?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: ULID = ULID(), question: String, askedAt: ZonedDate, context: String = "", category: TagPath? = nil,
                status: Status = .open, tags: [TagPath] = [], divinations: [Divination] = [], synthesis: Synthesis? = nil,
                outcomes: [Outcome] = [], physicalRef: PhysicalRef? = nil, timing: TimingContext? = nil, createdAt: Date = Date()) {
        self.id = id
        self.question = question
        self.askedAt = askedAt
        self.context = context
        self.category = category
        self.status = status
        self.tags = tags
        self.divinations = divinations
        self.synthesis = synthesis
        self.outcomes = outcomes
        self.physicalRef = physicalRef
        self.timing = timing
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    /// Adds an outcome; outcomes stack chronologically, never overwrite (spec §4).
    public mutating func addOutcome(_ outcome: Outcome) {
        outcomes.append(outcome)
        outcomes.sort { $0.recordedAt.instant < $1.recordedAt.instant }
        if status == .open { status = .resolved } else if status == .resolved { status = .revisited }
    }

    public func daysAfter(_ outcome: Outcome) -> Int {
        Int(((outcome.recordedAt.instant.timeIntervalSince(askedAt.instant)) / 86_400).rounded(.down))
    }
}

public struct Divination: Codable, Hashable, Sendable, Identifiable {
    public enum System: String, Codable, Sendable { case cards, yijing, other }

    public var id: ULID
    public var system: System
    public var deckId: String?
    public var spreadId: String?
    public var performedAt: ZonedDate
    public var method: String?
    public var notes: String?
    public var order: Int
    public var draws: [Draw]
    public var cast: YiJingCast?

    public init(id: ULID = ULID(), system: System, deckId: String? = nil, spreadId: String? = nil, performedAt: ZonedDate,
                method: String? = nil, notes: String? = nil, order: Int = 0, draws: [Draw] = [], cast: YiJingCast? = nil) {
        self.id = id
        self.system = system
        self.deckId = deckId
        self.spreadId = spreadId
        self.performedAt = performedAt
        self.method = method
        self.notes = notes
        self.order = order
        self.draws = draws
        self.cast = cast
    }
}

public enum Orientation: String, Codable, Sendable { case upright, reversed, na = "n/a" }

/// One card in one position.
public struct Draw: Codable, Hashable, Sendable, Identifiable {
    public var id: ULID
    public var cardId: String
    public var positionKey: String
    public var orientation: Orientation
    public var notes: String?
    public var tags: [TagPath]

    public init(id: ULID = ULID(), cardId: String, positionKey: String, orientation: Orientation = .upright, notes: String? = nil, tags: [TagPath] = []) {
        self.id = id
        self.cardId = cardId
        self.positionKey = positionKey
        self.orientation = orientation
        self.notes = notes
        self.tags = tags
    }
}

public struct Synthesis: Codable, Hashable, Sendable {
    public var body: String
    public var writtenAt: ZonedDate
    /// 1–5
    public var confidence: Int?
    public init(body: String, writtenAt: ZonedDate, confidence: Int? = nil) {
        self.body = body; self.writtenAt = writtenAt; self.confidence = confidence
    }
}

public struct Outcome: Codable, Hashable, Sendable, Identifiable {
    public enum Fulfilled: String, Codable, Sendable { case yes, partly, no, unclear }
    public var id: ULID
    /// May be in the past when transcribing old notes.
    public var recordedAt: ZonedDate
    public var body: String
    public var fulfilled: Fulfilled
    public init(id: ULID = ULID(), recordedAt: ZonedDate, body: String, fulfilled: Fulfilled) {
        self.id = id; self.recordedAt = recordedAt; self.body = body; self.fulfilled = fulfilled
    }
}
