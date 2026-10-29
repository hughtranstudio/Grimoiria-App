import Foundation

public extension EntryType {
    /// Entry types that can carry a recorded session.
    static let sessionTypes: [EntryType] = [.ritual, .meditation, .vision]
}

/// The clock and notebook of a session while it runs. The Mac recorder window drives one of these;
/// it has no audio or UI of its own, so the rules are tested here.
public struct SessionRecorder: Sendable {
    public var type: EntryType
    public var intention: String?
    public var technique: String?
    public var tags: [TagPath]
    public private(set) var session: PracticeSession

    public init(type: EntryType, startedAt: ZonedDate, intention: String? = nil, technique: String? = nil,
                tags: [TagPath] = [], before: StateCheck? = nil, firstPhase: SessionPhase? = .opening) {
        self.type = type
        self.intention = intention
        self.technique = technique
        self.tags = tags
        session = PracticeSession(startedAt: startedAt, phases: firstPhase.map { [PhaseMark($0, at: 0)] } ?? [],
                                  before: before?.isEmpty == true ? nil : before)
    }

    public var isFinished: Bool { session.endedAt != nil }

    /// Seconds since the start at `date`.
    public func elapsed(at date: Date) -> Double { max(0, date.timeIntervalSince(session.startedAt.instant)) }

    public var currentPhase: SessionPhase? { session.phases.last?.phase }

    /// Moves to a phase. Choosing the phase already in force does nothing.
    public mutating func setPhase(_ phase: SessionPhase, at date: Date) {
        guard !isFinished, currentPhase != phase else { return }
        session.phases.append(PhaseMark(phase, at: elapsed(at: date)))
        session.normalize()
    }

    /// "Something happened here": a marker to fill in afterwards.
    @discardableResult
    public mutating func mark(at date: Date) -> Observation {
        add(Observation(offset: elapsed(at: date), kind: .note, capture: .marker, reviewed: true))
    }

    /// An observation typed during the session, or written afterwards once it has ended.
    @discardableResult
    public mutating func observe(_ kind: ObservationKind, _ text: String, tags: [TagPath] = [], intensity: Int? = nil,
                                 clarity: Int? = nil, at date: Date) -> Observation {
        let recalled = isFinished
        let offset = recalled ? (session.duration ?? elapsed(at: date)) : elapsed(at: date)
        return add(Observation(offset: offset, phase: recalled ? .aftermath : nil, kind: kind,
                               text: text.trimmingCharacters(in: .whitespacesAndNewlines), tags: tags,
                               intensity: intensity, clarity: clarity, capture: recalled ? .recalled : .live))
    }

    private mutating func add(_ o: Observation) -> Observation {
        session.add(o)
        return session.observations.first { $0.id == o.id } ?? o
    }

    /// Stops the clock.
    public mutating func finish(at date: Date, after: StateCheck? = nil, outcome: String? = nil, interrupted: Bool = false) {
        guard !isFinished else { return }
        session.endedAt = ZonedDate(date, timeZone: session.startedAt.timeZone)
        session.after = after?.isEmpty == true ? nil : after
        let o = outcome?.trimmingCharacters(in: .whitespacesAndNewlines)
        session.outcome = o?.isEmpty == true ? nil : o
        session.interrupted = interrupted ? true : nil
    }

    /// The Inbox item for this session: an Entry of `type` with the session, its audio, the timed
    /// transcript, and the observations heard in it (unreviewed). Nothing is filed until Confirm.
    public func inboxItem(recording: SessionRecording?, extractor: ObservationExtractor, timing: TimingContext?,
                          source: String = "session:mac", captureId: String? = nil, now: Date = Date()) -> InboxItem {
        SessionAssembler.inboxItem(type: type, session: session, intention: intention, technique: technique, tags: tags,
                                   recording: recording, extractor: extractor, timing: timing, source: source,
                                   captureId: captureId, now: now)
    }
}

/// Builds a session's Inbox item, from the Mac recorder or from a phone sidecar.
public enum SessionAssembler {
    public static func inboxItem(type: EntryType, session base: PracticeSession, intention: String?, technique: String?,
                                 tags: [TagPath], recording: SessionRecording?, extractor: ObservationExtractor,
                                 timing: TimingContext?, source: String, captureId: String?, now: Date) -> InboxItem {
        var session = base
        var attachments: [Attachment] = []
        var notes: [String] = []
        var transcript: String?
        if let rec = recording {
            session.recordings.append(rec)
            attachments.append(Attachment(kind: .audio, path: rec.path, originalName: (rec.path as NSString).lastPathComponent))
            if !rec.segments.isEmpty {
                let found = extractor.extract(rec.segments, recordingOffset: rec.offset)
                session.phases += found.phases
                for o in found.observations { session.observations.append(o) }
                transcript = TimedTranscript.format(rec.segments)
            } else {
                notes.append("No transcript yet: use Transcribe Again once the speech model is installed")
            }
        }
        session.normalize()
        let heard = session.unreviewedCount
        if heard > 0 { notes.append("\(heard) observation\(heard == 1 ? " was" : "s were") made from speech: check kinds, text and tags") }
        let markers = session.observations.filter { $0.capture == .marker && $0.text.isEmpty }.count
        if markers > 0 { notes.append("\(markers) marker\(markers == 1 ? "" : "s") without text") }

        var fields = TypeFields()
        let cleanIntention = intention?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = cleanIntention, !i.isEmpty { fields.intention = i }
        if let t = technique?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { fields.technique = t }
        if let d = session.duration { fields.durationMin = Int((d / 60).rounded()) }
        if type == .vision { fields.setting = "meditation" }

        let title = cleanIntention.flatMap { $0.isEmpty ? nil : "\(type.rawValue.capitalized): \($0)" }
        let entry = Entry(id: ULID(date: session.startedAt.instant), type: type, title: title, occurredAt: session.startedAt,
                          createdAt: now, body: session.outcome ?? "", tags: tags, attachments: attachments, timing: timing,
                          mode: .reflective, status: .inbox, fields: fields, captureId: captureId, transcript: transcript,
                          session: session)
        return InboxItem(entry: entry, draft: nil, source: source, notes: notes)
    }

    /// Replaces the speech-made observations and phases of an Inbox session after transcribing
    /// again. Typed observations, markers and phases set by hand are kept.
    public static func retranscribed(_ item: InboxItem, segments: [TranscriptSegment], extractor: ObservationExtractor) -> InboxItem {
        guard var session = item.entry.session else { return item }
        var out = item
        let offset = session.recordings.first?.offset ?? 0
        if !session.recordings.isEmpty { session.recordings[0].segments = segments }
        session.observations.removeAll { !$0.reviewed && ($0.capture == .spoken || $0.capture == .marker) }
        let found = extractor.extract(segments, recordingOffset: offset)
        let handPhases = session.phases
        session.phases = handPhases + found.phases.filter { p in !handPhases.contains { abs($0.offset - p.offset) < 1 } }
        session.observations += found.observations
        session.normalize()
        out.entry.session = session
        out.entry.transcript = TimedTranscript.format(segments)
        var notes = (out.notes ?? []).filter { !$0.hasPrefix("No transcript yet") && !$0.contains("made from speech") }
        let heard = session.unreviewedCount
        if heard > 0 { notes.insert("\(heard) observation\(heard == 1 ? " was" : "s were") made from speech: check kinds, text and tags", at: 0) }
        out.notes = notes.isEmpty ? nil : notes
        return out
    }
}
