import XCTest
@testable import GrimoireCore

final class NudgesTests: XCTestCase {
    let lib = TestSupport.library

    func reading(_ day: String, card: String) -> Inquiry {
        let at = TestSupport.date("\(day)T09:00:00-08:00")
        var i = Inquiry(question: "Q \(day)", askedAt: at, createdAt: at.instant)
        i.divinations = [Divination(system: .cards, deckId: "rws-tarot", spreadId: "freeform", performedAt: at,
                                    draws: [Draw(cardId: card, positionKey: "1")])]
        return i
    }

    func data() -> GrimoireData {
        let repo = MemoryRepository()
        // The Tower four times in nine days, ending 10-29.
        for d in ["2026-10-21", "2026-10-24", "2026-10-27", "2026-10-29"] { repo.save(reading(d, card: "maj-16")) }
        // Three of Cups three times, but long ago.
        for d in ["2026-06-01", "2026-06-03", "2026-06-05"] { repo.save(reading(d, card: "cups-03")) }
        // A crow in an omen, a dream and a vision observation; a mood tag that never counts.
        repo.save(Entry(type: .omen, occurredAt: TestSupport.date("2026-10-25T07:00:00-07:00"), tags: ["entity/animal/crow", "emotion/calm"]))
        repo.save(Entry(type: .dream, occurredAt: TestSupport.date("2026-10-26T07:00:00-07:00"), tags: ["entity/animal/crow", "emotion/calm"]))
        var vision = Entry(type: .vision, occurredAt: TestSupport.date("2026-10-28T21:00:00-07:00"), tags: ["emotion/calm"])
        vision.session = PracticeSession(startedAt: vision.occurredAt, observations: [Observation(offset: 30, tags: ["entity/animal/crow"])])
        repo.save(vision)
        return repo.data
    }

    func testRecentRunsOnly() {
        let n = Patterns(data: data(), library: lib).nudges(today: "2026-10-30")
        XCTAssertEqual(n.map(\.key), ["rws-tarot/maj-16", "#entity/animal/crow"])
        XCTAssertEqual(n.first?.message, "The Tower, 4 times in 9 days")
        XCTAssertEqual(n.last?.message, "Crow, 3 times in 4 days")
        XCTAssertEqual(n.first?.id, "rws-tarot/maj-16@2026-10-21")
    }

    func testFadesWhenQuiet() {
        XCTAssertTrue(Patterns(data: data(), library: lib).nudges(today: "2026-11-20").isEmpty)
        XCTAssertEqual(Patterns(data: data(), library: lib).nudges(today: "2026-06-06").map(\.key), ["rws-tarot/cups-03"])
    }

    func testThreshold() {
        XCTAssertEqual(Patterns(data: data(), library: lib).nudges(today: "2026-10-30", minTimes: 4).map(\.key), ["rws-tarot/maj-16"])
    }
}
