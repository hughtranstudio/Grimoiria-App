import Foundation

/// Session and observation tables for analysis (docs/session-recording.md, docs/analyzing-sessions.md):
///
/// - `ML/sessions.jsonl` / `.csv`: one row per recorded session.
/// - `ML/observations.jsonl` / `.csv`: one row per observation, with its session's context copied in
///   and its tags split into controlled, free and one column per facet.
/// - `ML/tag-vocabulary.json`: the vocabulary the tags were checked against.
///
/// Columns are fixed (`sessionColumns`, `observationColumns`); new ones are only ever appended, and
/// `schema_version` in the manifest goes up when they are. Rows are sorted, so unchanged data
/// exports byte for byte the same.
public struct SessionExporter: Sendable {
    public static let schemaVersion = 1
    public let vocabulary: TagVocabulary

    public init(vocabulary: TagVocabulary = .standard) { self.vocabulary = vocabulary }

    /// One cell of a table: JSON keeps the type, CSV writes text (lists joined with ";").
    public enum Cell: Encodable, Equatable, Sendable {
        case string(String), int(Int), double(Double), bool(Bool), list([String]), null

        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .string(let s): try c.encode(s)
            case .int(let i): try c.encode(i)
            case .double(let d): try c.encode(d)
            case .bool(let b): try c.encode(b)
            case .list(let l): try c.encode(l)
            case .null: try c.encodeNil()
            }
        }

        var csv: String {
            switch self {
            case .string(let s): return s
            case .int(let i): return String(i)
            case .double(let d): return String(d)
            case .bool(let b): return b ? "true" : "false"
            case .list(let l): return l.joined(separator: ";")
            case .null: return ""
            }
        }
    }

    public typealias Row = [String: Cell]

    /// The facets that get their own column. Fixed, so the CSV shape doesn't move when the
    /// vocabulary grows; tags in other facets are still in `tags_controlled`.
    public static let facetColumns = ["entity", "place", "symbol", "color", "element", "direction", "sense", "emotion", "state", "technique", "planet", "sign", "theme"]

    static let timingColumns = ["moon_phase", "moon_illumination", "moon_sign", "sun_sign", "planetary_day", "planetary_hour", "planetary_hour_number", "near_cusp"]

    public static let sessionColumns: [String] = {
        var c: [String] = ["session_id", "session_type", "title", "started_at", "ended_at", "day", "weekday", "local_hour", "time_zone", "duration_s"]
        c += SessionPhase.allCases.map { "\($0.rawValue)_s" }
        c += ["before_energy", "before_calm", "before_focus", "after_energy", "after_calm", "after_focus",
              "intention", "technique", "depth", "clarity", "outcome", "interrupted"]
        c += ["observations", "observations_spoken", "observations_live", "observations_recalled", "markers", "unreviewed"]
        c += ObservationKind.allCases.map { "n_\($0.rawValue)" }
        c += ["tags", "observed_tags", "observed_tags_free"]
        c += timingColumns
        c += ["inquiry_id", "audio"]
        return c
    }()

    public static let observationColumns: [String] = {
        var c: [String] = ["observation_id", "session_id", "session_type", "session_started_at", "session_day", "observed_at", "offset_s", "minute"]
        c += ["phase", "kind", "capture", "reviewed", "text", "intensity", "clarity", "tags", "tags_controlled", "tags_free"]
        c += facetColumns
        c += ["session_tags", "intention", "technique"]
        c += timingColumns
        c += ["inquiry_id", "linked_entry_id"]
        return c
    }()

    // MARK: Rows

    func sessions(_ data: GrimoireData) -> [Entry] {
        data.entries.filter { $0.status == .filed && $0.session != nil }.sorted { $0.id < $1.id }
    }

    func timingCells(_ t: TimingContext?) -> Row {
        [
            "moon_phase": t.map { .string($0.moonPhase.rawValue) } ?? .null,
            "moon_illumination": t.map { .int($0.moonIllumination) } ?? .null,
            "moon_sign": t.map { .string($0.moonSign.rawValue) } ?? .null,
            "sun_sign": t.map { .string($0.sunSign.rawValue) } ?? .null,
            "planetary_day": t?.planetaryDay.map { .string($0.rawValue) } ?? .null,
            "planetary_hour": t?.planetaryHour.map { .string($0.rawValue) } ?? .null,
            "planetary_hour_number": t?.planetaryHourNumber.map { .int($0) } ?? .null,
            "near_cusp": t.map { .bool($0.nearCusp) } ?? .null,
        ]
    }

    static func str(_ s: String?) -> Cell { s.map { $0.isEmpty ? .null : .string($0) } ?? .null }
    static func int(_ i: Int?) -> Cell { i.map { .int($0) } ?? .null }
    static func seconds(_ d: Double?) -> Cell { d.map { .double(($0 * 10).rounded() / 10) } ?? .null }
    static func paths(_ t: [TagPath]) -> Cell { .list(t.map(\.path)) }

    public func sessionRows(_ data: GrimoireData) -> [Row] {
        sessions(data).map { e in
            let s = e.session!
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = s.startedAt.zone
            let weekday = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"][cal.component(.weekday, from: s.startedAt.instant) - 1]
            let obsTags = s.observationTags
            var r: Row = [
                "session_id": .string(e.id.string), "session_type": .string(e.type.rawValue), "title": .string(e.displayTitle),
                "started_at": .string(s.startedAt.iso8601), "ended_at": Self.str(s.endedAt?.iso8601), "day": .string(s.startedAt.day),
                "weekday": .string(weekday), "local_hour": .int(cal.component(.hour, from: s.startedAt.instant)),
                "time_zone": .string(s.startedAt.timeZone), "duration_s": Self.seconds(s.duration),
                "before_energy": Self.int(s.before?.energy), "before_calm": Self.int(s.before?.calm), "before_focus": Self.int(s.before?.focus),
                "after_energy": Self.int(s.after?.energy), "after_calm": Self.int(s.after?.calm), "after_focus": Self.int(s.after?.focus),
                "intention": Self.str(e.fields.intention), "technique": Self.str(e.fields.technique),
                "depth": Self.int(e.fields.depth), "clarity": Self.int(e.fields.clarity),
                "outcome": Self.str(s.outcome), "interrupted": .bool(s.interrupted == true),
                "observations": .int(s.observations.count),
                "observations_spoken": .int(s.observations.filter { $0.capture == .spoken }.count),
                "observations_live": .int(s.observations.filter { $0.capture == .live }.count),
                "observations_recalled": .int(s.observations.filter { $0.capture == .recalled }.count),
                "markers": .int(s.observations.filter { $0.capture == .marker }.count),
                "unreviewed": .int(s.unreviewedCount),
                "tags": Self.paths(e.tags),
                "observed_tags": Self.paths(obsTags),
                "observed_tags_free": Self.paths(vocabulary.classify(obsTags).free),
                "inquiry_id": Self.str(e.inquiryId?.string),
                "audio": .list(s.recordings.map(\.path)),
            ]
            let phases = s.phaseDurations
            for p in SessionPhase.allCases { r["\(p.rawValue)_s"] = Self.seconds(phases[p]) }
            for k in ObservationKind.allCases { r["n_\(k.rawValue)"] = .int(s.observations.filter { $0.kind == k }.count) }
            r.merge(timingCells(e.timing)) { a, _ in a }
            return r
        }
    }

    public func observationRows(_ data: GrimoireData) -> [Row] {
        var rows: [Row] = []
        for e in sessions(data) {
            let s = e.session!
            let context: Row = [
                "session_id": .string(e.id.string), "session_type": .string(e.type.rawValue),
                "session_started_at": .string(s.startedAt.iso8601), "session_day": .string(s.startedAt.day),
                "session_tags": Self.paths(e.tags), "intention": Self.str(e.fields.intention), "technique": Self.str(e.fields.technique),
                "inquiry_id": Self.str(e.inquiryId?.string),
            ].merging(timingCells(e.timing)) { a, _ in a }
            for o in s.observations {
                let split = vocabulary.classify(o.tags)
                let facets = vocabulary.byFacet(o.tags)
                var r = context
                r["observation_id"] = .string(o.id.string)
                r["observed_at"] = .string(s.time(of: o).iso8601)
                r["offset_s"] = Self.seconds(o.offset)
                r["minute"] = .int(Int(o.offset / 60))
                r["phase"] = Self.str(o.phase?.rawValue)
                r["kind"] = .string(o.kind.rawValue)
                r["capture"] = .string(o.capture.rawValue)
                r["reviewed"] = .bool(o.reviewed)
                r["text"] = Self.str(o.text)
                r["intensity"] = Self.int(o.intensity)
                r["clarity"] = Self.int(o.clarity)
                r["tags"] = Self.paths(o.tags.sorted())
                r["tags_controlled"] = Self.paths(split.controlled)
                r["tags_free"] = Self.paths(split.free)
                for f in Self.facetColumns { r[f] = Self.paths(facets[f] ?? []) }
                r["linked_entry_id"] = Self.str(o.linkedEntryId?.string)
                rows.append(r)
            }
        }
        return rows
    }

    // MARK: Files

    /// Export-relative path → contents.
    public func files(for data: GrimoireData) throws -> [String: String] {
        let sessions = sessionRows(data), observations = observationRows(data)
        return [
            "ML/sessions.jsonl": try Self.jsonl(sessions, columns: Self.sessionColumns),
            "ML/sessions.csv": Self.csv(sessions, columns: Self.sessionColumns),
            "ML/observations.jsonl": try Self.jsonl(observations, columns: Self.observationColumns),
            "ML/observations.csv": Self.csv(observations, columns: Self.observationColumns),
            "ML/tag-vocabulary.json": try vocabulary.json(),
        ]
    }

    public func counts(for data: GrimoireData) -> (sessions: Int, observations: Int) {
        (sessionRows(data).count, observationRows(data).count)
    }

    static func jsonl(_ rows: [Row], columns: [String]) throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let lines = try rows.map { r -> String in
            var full = r
            for c in columns where full[c] == nil { full[c] = .null }
            return String(decoding: try enc.encode(full), as: UTF8.self)
        }
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    /// RFC 4180: a header row, fields quoted when they hold a comma, quote or line break.
    static func csv(_ rows: [Row], columns: [String]) -> String {
        func field(_ s: String) -> String {
            s.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        var lines = [columns.joined(separator: ",")]
        for r in rows { lines.append(columns.map { field((r[$0] ?? .null).csv) }.joined(separator: ",")) }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
