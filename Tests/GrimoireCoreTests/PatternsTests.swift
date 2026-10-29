import XCTest
@testable import GrimoireCore

final class PatternsTests: XCTestCase {
    let lib = TestSupport.library

    func reading(_ day: String, cards: [(String, Orientation)] = [], cast: String? = nil, outcome: Outcome.Fulfilled? = nil,
                 confidence: Int? = nil, home: GeoLocation? = GeoLocation(latitude: 37.77, longitude: -122.42)) throws -> Inquiry {
        let at = TestSupport.date("\(day)T09:00:00-08:00")
        var i = Inquiry(question: "Q \(day)", askedAt: at, createdAt: at.instant)
        var order = 0
        if !cards.isEmpty {
            i.divinations.append(Divination(system: .cards, deckId: "rws-tarot", spreadId: "freeform", performedAt: at, order: order,
                                            draws: cards.enumerated().map { Draw(cardId: $1.0, positionKey: "\($0 + 1)", orientation: $1.1) }))
            order += 1
        }
        if let cast { i.divinations.append(Divination(system: .yijing, performedAt: at, order: order, cast: try YiJingCast(quick: cast))) }
        if let confidence { i.synthesis = Synthesis(body: "", writtenAt: at, confidence: confidence) }
        if let outcome {
            i.addOutcome(Outcome(recordedAt: ZonedDate(at.instant.addingTimeInterval(10 * 86_400), timeZone: at.timeZone), body: "", fulfilled: outcome))
        }
        i.timing = TimingContext.compute(at: at, location: home)
        return i
    }

    func data() throws -> GrimoireData {
        let repo = MemoryRepository()
        repo.save(try reading("2026-01-05", cards: [("maj-16", .upright), ("cups-03", .reversed)], cast: "777777", outcome: .yes, confidence: 4))
        repo.save(try reading("2026-01-20", cards: [("maj-16", .reversed)], outcome: .no, confidence: 2))
        repo.save(try reading("2026-03-30", cards: [("maj-16", .upright), ("wands-11", .upright)], cast: "777779", outcome: .partly))
        repo.save(try reading("2026-04-02", cast: "777777"))
        var omen = Entry(type: .omen, occurredAt: TestSupport.date("2026-01-06T07:00:00-08:00"), tags: ["entity/ally/crow", "theme/threshold"])
        omen.timing = TimingContext.compute(at: omen.occurredAt, location: nil)
        repo.save(omen)
        repo.save(Entry(type: .dream, occurredAt: TestSupport.date("2026-01-07T07:00:00-08:00"), tags: ["entity/ally/owl"]))
        repo.save(Entry(type: .dream, occurredAt: TestSupport.date("2026-01-08T07:00:00-08:00"), status: .inbox))
        return repo.data
    }

    func testCardAndAttributeCounts() throws {
        let p = Patterns(data: try data(), library: lib)
        XCTAssertEqual(p.cardCounts(deckId: "rws-tarot").first, Tally("maj-16", 3))
        XCTAssertEqual(p.cardCounts().first, Tally("rws-tarot/maj-16", 3))
        XCTAssertEqual(p.decksUsed, [Tally("rws-tarot", 5)])
        let arcana = p.attributeCounts(deckId: "rws-tarot", attribute: "arcana")
        XCTAssertEqual(arcana, [Tally("major", 3), Tally("minor", 2)])
        XCTAssertEqual(p.reversedShare(deckId: "rws-tarot")!, 2.0 / 5.0, accuracy: 0.001)
    }

    func testHexagrams() throws {
        let p = Patterns(data: try data(), library: lib)
        XCTAssertEqual(p.hexagramCounts().first, Tally(1, 3))
        XCTAssertEqual(p.hexagramCounts(role: .resulting), [Tally(43, 1)])
        XCTAssertEqual(p.changingLineCounts[5], Tally(6, 1))
        XCTAssertEqual(p.readings(withHexagram: 1).count, 3)
    }

    func testRecurrenceSplitsOnLongGaps() throws {
        let p = Patterns(data: try data(), library: lib)
        let rec = p.recurrences(withinDays: 30)
        let tower = rec.filter { $0.symbol == .card(deckId: "rws-tarot", cardId: "maj-16") }
        // Jan 5 and Jan 20 are one run; Mar 30 is more than 30 days later and stands alone.
        XCTAssertEqual(tower.count, 1)
        XCTAssertEqual(tower.first?.from, "2026-01-05")
        XCTAssertEqual(tower.first?.to, "2026-01-20")
        // Hexagram 1 on Mar 30 and Apr 2 is a run; Jan 5 is too far before it.
        let qian = rec.filter { $0.symbol == .hexagram(1) }
        XCTAssertEqual(qian.map(\.inquiryIds.count), [2])
        XCTAssertEqual(p.recurrences(withinDays: 120).first?.inquiryIds.count, 3)
    }

    func testTimingTablesListEveryValue() throws {
        let p = Patterns(data: try data(), library: lib)
        let phases = p.timing(.moonPhase)
        XCTAssertEqual(phases.count, 8)
        XCTAssertEqual(phases.map(\.count).reduce(0, +), 5, "4 readings + the omen with timing; the dream has none")
        let days = p.timing(.planetaryDay, includeReadings: true)
        XCTAssertEqual(days.map(\.key), ["sun", "moon", "mars", "mercury", "jupiter", "venus", "saturn"])
        XCTAssertEqual(days.map(\.count).reduce(0, +), 4, "the omen has no location, so no planetary day")
        XCTAssertEqual(p.timing(.moonPhase, forCard: "maj-16", deckId: "rws-tarot").map(\.count).reduce(0, +), 3)
    }

    func testOutcomesAndPractice() throws {
        let p = Patterns(data: try data(), library: lib)
        let s = p.outcomes()
        XCTAssertEqual(s.total, 4)
        XCTAssertEqual(s.answered, 3)
        XCTAssertEqual(s.hitRate!, 0.5, accuracy: 0.001)
        XCTAssertEqual(s.medianDaysToFirstOutcome, 10)
        XCTAssertEqual(p.outcomes(system: .yijing).total, 3)
        XCTAssertEqual(p.outcomesByConfidence[4]?.byFulfilled[.yes], 1)
        XCTAssertEqual(p.typeCounts, [Tally("dream", 1), Tally("omen", 1)], "inbox items are not counted")
        XCTAssertEqual(p.monthly.first, Tally("2026-01", 4))
        XCTAssertEqual(p.tagCounts.first { $0.key == "entity/ally" }?.count, 2)
        XCTAssertEqual(p.tagCounts.first { $0.key == "entity" }?.count, 2)
    }

    func testWindow() throws {
        let p = Patterns(data: try data(), library: lib, from: TestSupport.date("2026-03-01T00:00:00-08:00").instant)
        XCTAssertEqual(p.inquiries.count, 2)
        XCTAssertEqual(p.cardCounts(deckId: "rws-tarot").first, Tally("maj-16", 1))
    }

    func testReport() throws {
        let r = Patterns(data: try data(), library: lib).report(top: 3)
        XCTAssertEqual(r.readings, 4)
        XCTAssertEqual(r.decks.first?.topCards.first?.name, "The Tower")
        XCTAssertEqual(r.decks.first?.byAttribute["arcana"]?.first?.name, "Major")
        XCTAssertEqual(r.topHexagrams.first?.name, "1 \(lib.yijing.hexagram(1)!.name)")
        XCTAssertTrue(r.text.contains("Rider–Waite–Smith Tarot: 5 draws, 40% reversed"), r.text)
        XCTAssertTrue(r.text.contains("Outcomes: 3 of 4 readings answered (yes 1, partly 1, no 1, unclear 0); came true 50%"), r.text)
        XCTAssertTrue(r.text.contains("2×  The Tower (Rider–Waite–Smith Tarot)  2026-01-05 to 2026-01-20"), r.text)
        let json = try JSONEncoder().encode(r)
        XCTAssertEqual(try JSONDecoder().decode(PatternsReport.self, from: json), r)
    }

    func testSearchByCardAndHexagram() throws {
        let repo = MemoryRepository()
        let d = try data()
        d.inquiries.forEach(repo.save)
        d.entries.forEach(repo.save)
        var q = SearchQuery()
        q.card = "rws-tarot/maj-16"
        XCTAssertEqual(repo.search(q, library: lib).count, 3)
        q.card = "rws-tarot/wands-11"
        XCTAssertEqual(repo.search(q, library: lib).count, 1)
        q = SearchQuery()
        q.hexagram = 43
        XCTAssertEqual(repo.search(q, library: lib).count, 1, "resulting hexagrams count")
    }
}
