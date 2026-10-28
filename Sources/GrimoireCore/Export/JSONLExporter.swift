import Foundation

/// `grimoire.jsonl`: one record per line for ML use (spec §11.1). Keys are sorted and records
/// ordered by type then id, so the file is byte-stable when nothing changed.
public struct JSONLExporter: Sendable {
    public let library: DefinitionLibrary
    public init(library: DefinitionLibrary) { self.library = library }

    struct Line<T: Encodable>: Encodable {
        let record_type: String
        let grimoire_export_version: Int
        let record: T
        let derived: Derived?
    }

    /// Derived values that ML tools shouldn't have to recompute.
    struct Derived: Encodable {
        var card_names: [String: String]?
        var hexagrams: [CastSummary]?
        var outcome_days_after: [Int]?
    }
    struct CastSummary: Encodable { let primary: Int; let changing: [Int]; let resulting: Int? }

    public func export(_ data: GrimoireData) throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        var lines: [String] = []
        func add<T: Encodable>(_ type: String, _ r: T, _ d: Derived? = nil) throws {
            lines.append(String(decoding: try enc.encode(Line(record_type: type, grimoire_export_version: ObsidianExporter.formatVersion, record: r, derived: d)), as: UTF8.self))
        }
        for e in data.entries.filter({ $0.status == .filed }).sorted(by: { $0.id < $1.id }) { try add("entry", e) }
        for i in data.inquiries.sorted(by: { $0.id < $1.id }) {
            var names: [String: String] = [:]
            var casts: [CastSummary] = []
            for d in i.divinations {
                if let deck = d.deckId.flatMap(library.deck) {
                    for w in d.draws { names["\(deck.id)/\(w.cardId)"] = deck.card(w.cardId)?.name ?? w.cardId }
                }
                if let c = d.cast {
                    casts.append(CastSummary(primary: c.primaryHexagram(in: library.yijing), changing: c.changingLines, resulting: c.resultingHexagram(in: library.yijing)))
                }
            }
            try add("inquiry", i, Derived(card_names: names.isEmpty ? nil : names, hexagrams: casts.isEmpty ? nil : casts,
                                          outcome_days_after: i.outcomes.isEmpty ? nil : i.outcomes.map(i.daysAfter)))
        }
        for v in data.volumes.sorted(by: { $0.id < $1.id }) { try add("volume", v) }
        for r in data.reminders.sorted(by: { $0.id < $1.id }) { try add("reminder", r) }
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }
}
