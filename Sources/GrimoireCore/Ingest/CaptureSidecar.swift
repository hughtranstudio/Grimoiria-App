import Foundation

/// The phone → Mac sidecar, contract v1 (spec §12). Only `contract_version`, `id` and
/// `captured_at` are required.
///
/// `transcript` and `draft` are optional additions written by the Android capture app, which
/// transcribes on the phone and lets the user check the parsed reading there. When present the
/// Mac uses them instead of transcribing and parsing again; the Inbox confirm step still applies.
public struct CaptureSidecar: Codable, Hashable, Sendable {
    public var contractVersion: Int
    public var id: String
    public var capturedAt: String
    public var device: String?
    public var kindHint: String?
    public var text: String?
    public var audio: String?
    public var tags: [String]?
    public var inquiryId: String?
    public var location: Location?
    public var draws: [SidecarDraw]?
    /// On-phone transcript of `audio`, as corrected by the user.
    public var transcript: String?
    /// Reading as checked on the phone, in `DraftReading`'s own JSON shape.
    public var draft: DraftReading?
    /// A recorded ritual, meditation or vision (docs/session-recording.md).
    public var session: SidecarSession?

    public struct Location: Codable, Hashable, Sendable { public var lat: Double; public var lon: Double }
    public struct SidecarDraw: Codable, Hashable, Sendable {
        public var deck: String
        public var card: String
        public var orientation: Orientation?
    }

    /// The phone's session: times, phase changes and markers by offset in seconds.
    public struct SidecarSession: Codable, Hashable, Sendable {
        public var type: String?
        public var startedAt: String?
        public var endedAt: String?
        public var intention: String?
        public var technique: String?
        public var marks: [Mark]?
        /// Timed transcript, when the phone made one.
        public var segments: [TranscriptSegment]?
        public var before: StateCheck?
        public var after: StateCheck?
        public var outcome: String?

        public struct Mark: Codable, Hashable, Sendable {
            public var offsetS: Double
            public var phase: SessionPhase?
            public var kind: ObservationKind?
            public var text: String?
            public var tags: [String]?
            enum CodingKeys: String, CodingKey { case offsetS = "offset_s", phase, kind, text, tags }
        }

        enum CodingKeys: String, CodingKey {
            case type, startedAt = "started_at", endedAt = "ended_at", intention, technique, marks, segments, before, after, outcome
        }
    }

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version", id, capturedAt = "captured_at", device, kindHint = "kind_hint"
        case text, audio, tags, inquiryId = "inquiry_id", location, draws, transcript, draft, session
    }

    public static let supportedVersion = 1

    public static func decode(_ data: Data) throws -> CaptureSidecar {
        let s: CaptureSidecar
        do { s = try JSONDecoder().decode(CaptureSidecar.self, from: data) }
        catch { throw IngestError.badSidecar("not valid sidecar JSON: \(error)") }
        guard s.contractVersion == supportedVersion else { throw IngestError.badSidecar("unsupported contract_version \(s.contractVersion)") }
        guard !s.id.trimmingCharacters(in: .whitespaces).isEmpty else { throw IngestError.badSidecar("empty id") }
        guard ZonedDate.parse(s.capturedAt) != nil else { throw IngestError.badSidecar("captured_at is not ISO 8601 with offset: \(s.capturedAt)") }
        if let a = s.audio, a.contains("/") || a.hasPrefix(".") { throw IngestError.badSidecar("audio must be a bare file name") }
        if let ss = s.session {
            for (name, value) in [("started_at", ss.startedAt), ("ended_at", ss.endedAt)] {
                if let v = value, ZonedDate.parse(v) == nil { throw IngestError.badSidecar("session \(name) is not ISO 8601 with offset: \(v)") }
            }
            if let t = ss.type, !EntryType.sessionTypes.map(\.rawValue).contains(t) { throw IngestError.badSidecar("session type must be ritual, meditation or vision, not \(t)") }
        }
        return s
    }

    /// Entry type from `kind_hint`; `draw`/`yijing` and unknown hints map to divination/insight.
    public var entryType: EntryType {
        if let t = session?.type.flatMap(EntryType.init(rawValue:)) { return t }
        guard let k = kindHint?.lowercased() else { return .insight }
        if k == "draw" || k == "yijing" { return .divination }
        return EntryType(rawValue: k) ?? .insight
    }

    public var expectsReading: Bool { session == nil && ["draw", "yijing"].contains(kindHint?.lowercased() ?? "") }
}

public enum IngestError: Error, Equatable, CustomStringConvertible {
    case badSidecar(String)
    case transcription(String)
    case io(String)
    public var description: String {
        switch self {
        case .badSidecar(let s): return "Bad sidecar: \(s)"
        case .transcription(let s): return "Transcription failed: \(s)"
        case .io(let s): return "File error: \(s)"
        }
    }
}
