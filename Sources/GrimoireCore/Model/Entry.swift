import Foundation

public enum EntryType: String, Codable, CaseIterable, Sendable {
    case journal, ritual, meditation, vision, contact, omen, insight, dream, divination
    /// Something that happened in life ("I just launched a website"), usually with a Uranika chart.
    case event
}

public enum EntryMode: String, Codable, Sendable { case quick, reflective }
public enum EntryStatus: String, Codable, Sendable { case inbox, filed }

/// The common core of every record (spec §3.1) plus type-specific fields (§3.2).
public struct Entry: Codable, Hashable, Sendable, Identifiable {
    public var id: ULID
    public var type: EntryType
    public var title: String?
    public var occurredAt: ZonedDate
    public var createdAt: Date
    public var updatedAt: Date
    public var body: String
    public var tags: [TagPath]
    public var links: [Link]
    public var inquiryId: ULID?
    public var physicalRef: PhysicalRef?
    public var attachments: [Attachment]
    public var timing: TimingContext?
    public var mode: EntryMode
    public var status: EntryStatus
    public var fields: TypeFields
    /// Per-type "extra notes" field for anything the schema misses.
    public var extraNotes: String?
    /// Phone capture id, kept for de-duplication of ingested items (spec §12).
    public var captureId: String?
    /// Raw transcript of the attached audio, when ingested.
    public var transcript: String?
    /// The recorded session behind a ritual, meditation or vision: clock, phases, observations.
    public var session: PracticeSession?
    /// The chart of the moment from Uranika, when that integration is on.
    public var astro: AstroSnapshot?

    public init(
        id: ULID = ULID(),
        type: EntryType,
        title: String? = nil,
        occurredAt: ZonedDate,
        createdAt: Date = Date(),
        body: String = "",
        tags: [TagPath] = [],
        links: [Link] = [],
        inquiryId: ULID? = nil,
        physicalRef: PhysicalRef? = nil,
        attachments: [Attachment] = [],
        timing: TimingContext? = nil,
        mode: EntryMode = .reflective,
        status: EntryStatus = .filed,
        fields: TypeFields = TypeFields(),
        extraNotes: String? = nil,
        captureId: String? = nil,
        transcript: String? = nil,
        session: PracticeSession? = nil,
        astro: AstroSnapshot? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.body = body
        self.tags = tags
        self.links = links
        self.inquiryId = inquiryId
        self.physicalRef = physicalRef
        self.attachments = attachments
        self.timing = timing
        self.mode = mode
        self.status = status
        self.fields = fields
        self.extraNotes = extraNotes
        self.captureId = captureId
        self.transcript = transcript
        self.session = session
        self.astro = astro
    }

    /// Title, or the first line of the body when blank (spec §3.1).
    public var displayTitle: String {
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        let first = body.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces)) ?? ""
        if first.isEmpty { return type.rawValue.capitalized }
        return first.count > 60 ? String(first.prefix(57)) + "…" : first
    }
}

/// Type-specific fields. All optional; which ones apply depends on `Entry.type`.
public struct TypeFields: Codable, Hashable, Sendable {
    // ritual
    public var intention: String?
    public var tools: [String]?
    public var location: String?
    public var durationMin: Int?
    public var steps: String?
    public var result: String?
    // meditation
    public var technique: String?
    public var depth: Int?
    public var observations: String?
    // vision
    public var setting: String?
    public var beings: [TagPath]?
    public var places: [TagPath]?
    public var clarity: Int?
    // contact
    public var being: TagPath?
    public var nature: String?
    public var communication: String?
    // omen
    public var observedIn: String?
    public var interpretation: String?
    public var resolved: Bool?
    // insight
    public var domain: String?
    // dream
    public var lucid: Bool?
    public var recurring: Bool?
    public var figures: [TagPath]?

    public init() {}

    /// Field names that apply to each entry type, for editors and validation.
    public static let keys: [EntryType: [String]] = [
        .journal: [],
        .ritual: ["intention", "tools", "location", "durationMin", "steps", "result"],
        .meditation: ["technique", "durationMin", "depth", "observations"],
        .vision: ["setting", "beings", "places", "clarity"],
        .contact: ["being", "nature", "communication"],
        .omen: ["observedIn", "interpretation", "resolved"],
        .insight: ["domain"],
        .dream: ["lucid", "recurring", "figures"],
        .divination: [],
        .event: [],
    ]

    /// Problems with 1–5 scales and enum-like strings.
    public func problems(for type: EntryType) -> [String] {
        var out: [String] = []
        func scale(_ name: String, _ v: Int?) { if let v, !(1...5).contains(v) { out.append("\(name) must be 1–5") } }
        scale("depth", depth)
        scale("clarity", clarity)
        if let s = setting, !["meditation", "ritual", "spontaneous", "liminal"].contains(s) { out.append("setting '\(s)' is not one of meditation/ritual/spontaneous/liminal") }
        if let n = nature, !["ally", "neutral", "hostile", "unknown"].contains(n) { out.append("nature '\(n)' is not one of ally/neutral/hostile/unknown") }
        if let o = observedIn, !["nature", "people", "media", "body", "other"].contains(o) { out.append("observedIn '\(o)' is not one of nature/people/media/body/other") }
        if let d = domain, !["magical", "mundane"].contains(d) { out.append("domain '\(d)' is not magical/mundane") }
        if let b = being, !b.isUnder("entity") { out.append("being should be a tag under entity/") }
        return out
    }
}

public struct Attachment: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case image, audio, document }
    public var kind: Kind
    /// Path relative to the app's attachments folder.
    public var path: String
    public var originalName: String?
    public init(kind: Kind, path: String, originalName: String? = nil) {
        self.kind = kind; self.path = path; self.originalName = originalName
    }
}
