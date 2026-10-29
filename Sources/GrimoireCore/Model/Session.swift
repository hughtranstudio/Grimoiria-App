import Foundation

/// The parts of a ritual, meditation or vision, in order.
public enum SessionPhase: String, Codable, CaseIterable, Sendable {
    case preparation, opening, working, closing, aftermath
}

/// What kind of thing an observation records. The set is fixed so counts stay comparable over years.
public enum ObservationKind: String, Codable, CaseIterable, Sendable {
    case imagery, entity, place, symbol, message, sound, sensation, emotion, insight, omen, event, action, note
}

/// How an observation got into the record. Matters for analysis: recalled ones carry hindsight,
/// spoken ones come through speech to text.
public enum ObservationCapture: String, Codable, Sendable {
    /// Typed during the session.
    case live
    /// Transcribed from the session's audio.
    case spoken
    /// Written after the session ended.
    case recalled
    /// A bare "something happened here" marker, text to fill in later.
    case marker
}

/// One thing seen, heard, met or felt inside a session, at a time (one row in the ML export).
public struct Observation: Codable, Hashable, Sendable, Identifiable {
    public var id: ULID
    /// Seconds since the session started. Recalled observations use the end of the session.
    public var offset: Double
    public var phase: SessionPhase?
    public var kind: ObservationKind
    public var text: String
    public var tags: [TagPath]
    /// 1–5, how strong.
    public var intensity: Int?
    /// 1–5, how clear or certain.
    public var clarity: Int?
    public var capture: ObservationCapture
    /// False for observations made by speech to text or keyword guesses, until confirmed.
    public var reviewed: Bool
    /// A Contact or Omen entry made from this observation.
    public var linkedEntryId: ULID?

    public init(id: ULID = ULID(), offset: Double, phase: SessionPhase? = nil, kind: ObservationKind = .note, text: String = "",
                tags: [TagPath] = [], intensity: Int? = nil, clarity: Int? = nil, capture: ObservationCapture = .live,
                reviewed: Bool = true, linkedEntryId: ULID? = nil) {
        self.id = id
        self.offset = max(0, offset)
        self.phase = phase
        self.kind = kind
        self.text = text
        self.tags = tags
        self.intensity = intensity
        self.clarity = clarity
        self.capture = capture
        self.reviewed = reviewed
        self.linkedEntryId = linkedEntryId
    }
}

/// When a phase began, in seconds since the session started.
public struct PhaseMark: Codable, Hashable, Sendable {
    public var phase: SessionPhase
    public var offset: Double
    public init(_ phase: SessionPhase, at offset: Double) { self.phase = phase; self.offset = max(0, offset) }
}

/// A piece of transcript with the time it was spoken, in seconds from the start of its recording.
public struct TranscriptSegment: Codable, Hashable, Sendable {
    public var offset: Double
    public var text: String
    public init(offset: Double, text: String) { self.offset = offset; self.text = text }
}

/// An audio file recorded during the session.
public struct SessionRecording: Codable, Hashable, Sendable {
    /// Path relative to the attachments folder, as on `Attachment`.
    public var path: String
    /// Seconds after the session start that the recording began.
    public var offset: Double
    public var duration: Double?
    public var segments: [TranscriptSegment]
    public init(path: String, offset: Double = 0, duration: Double? = nil, segments: [TranscriptSegment] = []) {
        self.path = path; self.offset = offset; self.duration = duration; self.segments = segments
    }
}

/// A quick self-rating before and after, each 1–5.
public struct StateCheck: Codable, Hashable, Sendable {
    public var energy: Int?
    public var calm: Int?
    public var focus: Int?
    public init(energy: Int? = nil, calm: Int? = nil, focus: Int? = nil) { self.energy = energy; self.calm = calm; self.focus = focus }
    public var isEmpty: Bool { energy == nil && calm == nil && focus == nil }
}

/// A recorded ritual, meditation or vision: the clock, its phases and the observations made inside it.
/// Lives on the Entry it belongs to (`Entry.session`).
public struct PracticeSession: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var startedAt: ZonedDate
    public var endedAt: ZonedDate?
    public var phases: [PhaseMark]
    public var observations: [Observation]
    public var recordings: [SessionRecording]
    public var before: StateCheck?
    public var after: StateCheck?
    public var outcome: String?
    public var interrupted: Bool?

    public init(startedAt: ZonedDate, endedAt: ZonedDate? = nil, phases: [PhaseMark] = [], observations: [Observation] = [],
                recordings: [SessionRecording] = [], before: StateCheck? = nil, after: StateCheck? = nil,
                outcome: String? = nil, interrupted: Bool? = nil) {
        self.schemaVersion = Self.currentSchemaVersion
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.phases = phases.sorted { $0.offset < $1.offset }
        self.observations = observations
        self.recordings = recordings
        self.before = before
        self.after = after
        self.outcome = outcome
        self.interrupted = interrupted
        normalize()
    }

    /// Seconds from start to end, when ended.
    public var duration: Double? { endedAt.map { $0.instant.timeIntervalSince(startedAt.instant) } }

    /// The phase in force at `offset`, from the phase marks.
    public func phase(at offset: Double) -> SessionPhase? {
        if let end = duration, offset > end, !phases.isEmpty { return .aftermath }
        return phases.last { $0.offset <= offset }?.phase
    }

    /// Seconds spent in each phase that has a mark, for a session that has ended.
    public var phaseDurations: [SessionPhase: Double] {
        guard let end = duration else { return [:] }
        var out: [SessionPhase: Double] = [:]
        for (i, m) in phases.enumerated() {
            let next = i + 1 < phases.count ? phases[i + 1].offset : end
            out[m.phase, default: 0] += max(0, min(next, end) - m.offset)
        }
        return out
    }

    /// The wall-clock time of an observation.
    public func time(of o: Observation) -> ZonedDate {
        ZonedDate(startedAt.instant.addingTimeInterval(o.offset), timeZone: startedAt.timeZone)
    }

    /// Adds an observation in time order, taking its phase from the marks when it has none.
    public mutating func add(_ o: Observation) {
        observations.append(o)
        normalize()
    }

    /// Sorts observations and phases and fills missing phases. Stable for equal offsets.
    public mutating func normalize() {
        phases = phases.enumerated().sorted { ($0.element.offset, $0.offset) < ($1.element.offset, $1.offset) }.map(\.element)
        observations = observations.enumerated().sorted { ($0.element.offset, $0.offset) < ($1.element.offset, $1.offset) }.map(\.element)
        for i in observations.indices where observations[i].phase == nil {
            observations[i].phase = phase(at: observations[i].offset)
        }
    }

    /// Every tag on any observation, sorted and unique.
    public var observationTags: [TagPath] { Array(Set(observations.flatMap(\.tags))).sorted() }

    /// Observations still waiting for a person to check them.
    public var unreviewedCount: Int { observations.filter { !$0.reviewed }.count }

    /// Problems with the 1–5 scales and the clock.
    public var problems: [String] {
        var out: [String] = []
        func scale(_ name: String, _ v: Int?) { if let v, !(1...5).contains(v) { out.append("\(name) must be 1–5") } }
        for (label, s) in [("before", before), ("after", after)] {
            scale("\(label) energy", s?.energy); scale("\(label) calm", s?.calm); scale("\(label) focus", s?.focus)
        }
        for o in observations {
            scale("intensity", o.intensity); scale("clarity", o.clarity)
        }
        if let d = duration, d < 0 { out.append("session ends before it starts") }
        return out
    }
}
