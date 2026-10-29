import Foundation

/// Files shaped for local models and notebooks (spec §11.1, "open format export for later ML"):
///
/// - `ML/draws.jsonl`: one flat row per card drawn or hexagram cast, with the card's attributes,
///   the timing and how the reading turned out, ready for pandas or a spreadsheet.
/// - `ML/corpus.jsonl`: the writing, cut into passages of about `chunkSize` characters with their
///   record, kind, date and tags, ready for a local embedding model.
/// - `ML/manifest.json`: what each file holds and how many rows.
///
/// Everything is sorted and carries no export time, so re-exporting unchanged data changes nothing.
/// Nothing leaves the Mac; the files sit in the export folder for tools you run yourself.
public struct MLExporter: Sendable {
    public static let formatVersion = 1
    public let library: DefinitionLibrary
    public var chunkSize = 1200

    public init(library: DefinitionLibrary) { self.library = library }

    struct DrawRow: Encodable {
        var inquiry_id: String
        var asked_at: String
        var day: String
        var question: String
        var category: String?
        var tags: [String]
        var system: String
        var deck: String?
        var spread: String?
        var position: String?
        var card: String?
        var card_name: String?
        var orientation: String?
        var attributes: [String: String]?
        var hexagram: Int?
        var hexagram_role: String?
        var changing_lines: [Int]?
        var moon_phase: String?
        var moon_illumination: Int?
        var moon_sign: String?
        var sun_sign: String?
        var planetary_day: String?
        var planetary_hour: String?
        var synthesis_confidence: Int?
        var fulfilled: String?
        var days_to_first_outcome: Int?
    }

    struct Passage: Encodable {
        var id: String
        var record_id: String
        var record_type: String
        var kind: String
        var day: String
        var tags: [String]
        var text: String
    }

    struct Manifest: Encodable {
        struct File: Encodable { var path: String; var rows: Int; var about: String }
        var grimoire_ml_export_version: Int
        var privacy: String
        var files: [File]
    }

    /// Vault-relative path → contents.
    public func files(for data: GrimoireData) throws -> [String: String] {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        func line<T: Encodable>(_ v: T) throws -> String { String(decoding: try enc.encode(v), as: UTF8.self) }
        func jsonl(_ lines: [String]) -> String { lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n") }

        let draws = try drawRows(data).map(line)
        let passages = try corpus(data).map(line)
        let manifest = Manifest(
            grimoire_ml_export_version: Self.formatVersion,
            privacy: "Written by Grimoire on this Mac for tools you run locally. Nothing here is sent anywhere.",
            files: [
                .init(path: "ML/draws.jsonl", rows: draws.count,
                      about: "One row per card drawn or hexagram cast (primary and resulting), with deck attributes, timing, synthesis confidence and the latest outcome."),
                .init(path: "ML/corpus.jsonl", rows: passages.count,
                      about: "Passages of about \(chunkSize) characters from entries, questions, context, syntheses, outcomes and transcripts, for local embeddings or search."),
                .init(path: "grimoire.jsonl", rows: -1, about: "Every record whole, one per line (see grimoire_export_version)."),
            ])
        let pretty = JSONEncoder()
        pretty.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return [
            "ML/draws.jsonl": jsonl(draws),
            "ML/corpus.jsonl": jsonl(passages),
            "ML/manifest.json": String(decoding: try pretty.encode(manifest), as: UTF8.self) + "\n",
        ]
    }

    func drawRows(_ data: GrimoireData) -> [DrawRow] {
        var rows: [DrawRow] = []
        for i in data.inquiries.sorted(by: { $0.id < $1.id }) {
            let t = i.timing
            let base = DrawRow(
                inquiry_id: i.id.string, asked_at: i.askedAt.iso8601, day: i.askedAt.day, question: i.question,
                category: i.category?.path, tags: i.tags.map(\.path), system: "",
                moon_phase: t?.moonPhase.rawValue, moon_illumination: t?.moonIllumination, moon_sign: t?.moonSign.rawValue,
                sun_sign: t?.sunSign.rawValue, planetary_day: t?.planetaryDay?.rawValue, planetary_hour: t?.planetaryHour?.rawValue,
                synthesis_confidence: i.synthesis?.confidence, fulfilled: i.outcomes.last?.fulfilled.rawValue,
                days_to_first_outcome: i.outcomes.first.map(i.daysAfter))
            for d in i.divinations.sorted(by: { $0.order < $1.order }) {
                for w in d.draws {
                    var r = base
                    let card = d.deckId.flatMap(library.deck)?.card(w.cardId)
                    r.system = d.system.rawValue
                    r.deck = d.deckId
                    r.spread = d.spreadId
                    r.position = w.positionKey
                    r.card = w.cardId
                    r.card_name = card?.name
                    r.orientation = w.orientation.rawValue
                    r.attributes = card.map { c in c.attributes.mapValues(\.description) }
                    rows.append(r)
                }
                if let c = d.cast {
                    var r = base
                    r.system = d.system.rawValue
                    r.hexagram = c.primaryHexagram(in: library.yijing)
                    r.hexagram_role = "primary"
                    r.changing_lines = c.changingLines
                    rows.append(r)
                    if let n = c.resultingHexagram(in: library.yijing) {
                        r.hexagram = n
                        r.hexagram_role = "resulting"
                        r.changing_lines = nil
                        rows.append(r)
                    }
                }
            }
        }
        return rows
    }

    func corpus(_ data: GrimoireData) -> [Passage] {
        var out: [Passage] = []
        func add(_ record: ULID, _ type: String, _ kind: String, _ day: String, _ tags: [TagPath], _ text: String?) {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            for (n, piece) in Self.chunks(text, size: chunkSize).enumerated() {
                out.append(Passage(id: "\(record)-\(kind)-\(n)", record_id: record.string, record_type: type, kind: kind,
                                   day: day, tags: tags.map(\.path), text: piece))
            }
        }
        for e in data.entries.filter({ $0.status == .filed }).sorted(by: { $0.id < $1.id }) {
            let day = e.occurredAt.day
            add(e.id, e.type.rawValue, "body", day, e.tags, [e.title, e.body].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n"))
            let f = e.fields
            add(e.id, e.type.rawValue, "fields", day, e.tags,
                [f.intention, f.steps, f.result, f.observations, f.interpretation, f.communication, e.extraNotes].compactMap { $0 }.joined(separator: "\n\n"))
            if e.transcript != e.body { add(e.id, e.type.rawValue, "transcript", day, e.tags, e.transcript) }
        }
        for i in data.inquiries.sorted(by: { $0.id < $1.id }) {
            let day = i.askedAt.day
            add(i.id, "inquiry", "question", day, i.tags, [i.question, i.context].filter { !$0.isEmpty }.joined(separator: "\n\n"))
            add(i.id, "inquiry", "synthesis", day, i.tags, i.synthesis?.body)
            for (n, o) in i.outcomes.enumerated() { add(i.id, "inquiry", "outcome\(n + 1)", o.recordedAt.day, i.tags, "\(o.fulfilled.rawValue): \(o.body)") }
        }
        return out
    }

    /// Splits at paragraph, then sentence, then word boundaries into pieces of at most `size` characters.
    static func chunks(_ text: String, size: Int) -> [String] {
        guard text.count > size else { return [text] }
        var out: [String] = []
        var current = ""
        func flush() { let t = current.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty { out.append(t) }; current = "" }
        let units = text.components(separatedBy: "\n\n").flatMap { para -> [String] in
            guard para.count > size else { return [para + "\n\n"] }
            // A long paragraph: sentences, and words for a run-on sentence.
            var pieces: [String] = [], sentence = ""
            for ch in para {
                sentence.append(ch)
                if ch == " ", let last = sentence.dropLast().last, ".!?".contains(last) { pieces.append(sentence); sentence = "" }
            }
            if !sentence.isEmpty { pieces.append(sentence + " ") }
            return pieces.flatMap { s in s.count > size ? s.split(separator: " ").map { $0 + " " } : [s] }
        }
        for u in units {
            if current.count + u.count > size { flush() }
            current += u
        }
        flush()
        return out
    }
}
