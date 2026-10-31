import Foundation

/// A quiet notice that a card, hexagram or symbol keeps coming back: "The Tower, 4 times in 9 days".
/// Built from recent runs (see `Patterns.recurrences`); a nudge fades once the run goes quiet.
public struct Nudge: Hashable, Sendable, Identifiable {
    public enum Subject: Hashable, Sendable {
        case card(deckId: String, cardId: String)
        case hexagram(Int)
        /// A symbol tag from entries and session observations, such as `entity/animal/crow`.
        case tag(TagPath)
    }

    public var subject: Subject
    public var name: String
    /// The readings (cards, hexagrams) or entries (tags) in the run, oldest first.
    public var recordIds: [ULID]
    /// First and last day of the run, yyyy-MM-dd.
    public var from: String
    public var to: String
    /// Days from the first to the last, counting both.
    public var days: Int

    public var times: Int { recordIds.count }

    /// A yyyy-MM-dd day as midnight UTC, for counting whole days between two days.
    static func midnight(_ day: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: day)
    }

    /// Stable for one run, so a nudge you hide stays hidden while new runs still show.
    public var id: String { "\(key)@\(from)" }

    public var key: String {
        switch subject {
        case let .card(deckId, cardId): return "\(deckId)/\(cardId)"
        case let .hexagram(n): return "yijing/\(n)"
        case let .tag(t): return "#\(t.path)"
        }
    }

    /// "The Tower, 4 times in 9 days".
    public var message: String { "\(name), \(times) times in \(days) day\(days == 1 ? "" : "s")" }
}

/// Facets whose tags count as symbols that can recur: what was seen or met, not how you felt.
public enum NudgeFacets {
    public static let symbols: Set<String> = ["entity", "place", "symbol", "color", "element", "direction", "planet", "sign", "theme"]
}

extension Patterns {
    /// Cards, hexagrams and symbols that came up at least `minTimes` times with no more than `withinDays`
    /// between one and the next, in a run whose last appearance is no more than `freshDays` before `today`.
    /// Most times first.
    public func nudges(today: String, withinDays: Int = 14, minTimes: Int = 3, freshDays: Int = 7) -> [Nudge] {
        guard let now = Nudge.midnight(today) else { return [] }
        func fresh(_ to: String) -> Bool {
            guard let last = Nudge.midnight(to) else { return false }
            let age = now.timeIntervalSince(last) / 86_400
            return age >= 0 && age <= Double(freshDays)
        }
        func span(_ from: String, _ to: String) -> Int {
            guard let a = Nudge.midnight(from), let b = Nudge.midnight(to) else { return 1 }
            return Int((b.timeIntervalSince(a) / 86_400).rounded()) + 1
        }
        var out: [Nudge] = []
        for r in recurrences(withinDays: withinDays, minReadings: minTimes) where fresh(r.to) {
            switch r.symbol {
            case let .card(deckId, cardId):
                let name = library.deck(deckId)?.card(cardId)?.name ?? cardId
                out.append(Nudge(subject: .card(deckId: deckId, cardId: cardId), name: name, recordIds: r.inquiryIds, from: r.from, to: r.to, days: span(r.from, r.to)))
            case let .hexagram(n):
                let name = library.yijing.hexagram(n).map { "\(n). \($0.name)" } ?? "Hexagram \(n)"
                out.append(Nudge(subject: .hexagram(n), name: name, recordIds: r.inquiryIds, from: r.from, to: r.to, days: span(r.from, r.to)))
            }
        }
        for run in symbolRuns(withinDays: withinDays, minTimes: minTimes) where fresh(run.to) {
            let leaf = run.tag.components.last.map { $0.replacingOccurrences(of: "-", with: " ") } ?? run.tag.path
            out.append(Nudge(subject: .tag(run.tag), name: leaf.prefix(1).uppercased() + leaf.dropFirst(), recordIds: run.ids,
                             from: run.from, to: run.to, days: span(run.from, run.to)))
        }
        return out.sorted { ($1.times, $0.to, $0.key) < ($0.times, $1.to, $1.key) }
    }

    /// Runs of one symbol tag across entries and their session observations, one mark per entry.
    func symbolRuns(withinDays: Int, minTimes: Int) -> [(tag: TagPath, ids: [ULID], from: String, to: String)] {
        var hits: [TagPath: [(Date, String, ULID)]] = [:]
        for e in entries {
            var tags = Set(e.tags)
            for o in e.session?.observations ?? [] { tags.formUnion(o.tags) }
            for t in tags where t.components.count > 1 && NudgeFacets.symbols.contains(t.components[0]) {
                hits[t, default: []].append((e.occurredAt.instant, e.occurredAt.day, e.id))
            }
        }
        var out: [(tag: TagPath, ids: [ULID], from: String, to: String)] = []
        let gap = TimeInterval(withinDays) * 86_400
        for (tag, list) in hits {
            var run: [(Date, String, ULID)] = []
            func close() {
                if run.count >= minTimes { out.append((tag, run.map(\.2), run.first!.1, run.last!.1)) }
                run = []
            }
            for m in list.sorted(by: { $0.0 < $1.0 }) {
                if let last = run.last, m.0.timeIntervalSince(last.0) > gap { close() }
                run.append(m)
            }
            close()
        }
        return out
    }
}
