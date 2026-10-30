import XCTest
@testable import GrimoireCore

final class MeaningsTests: XCTestCase {
    let lib = TestSupport.library

    func reading(_ day: String, question: String, category: TagPath? = nil, card: String, orientation: Orientation = .upright,
                 note: String? = nil, outcome: (Outcome.Fulfilled, String)? = nil) -> Inquiry {
        let at = TestSupport.date("\(day)T09:00:00-08:00")
        var i = Inquiry(question: question, askedAt: at, category: category, createdAt: at.instant)
        i.divinations = [Divination(system: .cards, deckId: "rws-tarot", spreadId: "freeform", performedAt: at,
                                    draws: [Draw(cardId: card, positionKey: "1", orientation: orientation, notes: note)])]
        if let (f, body) = outcome {
            i.addOutcome(Outcome(recordedAt: ZonedDate(at.instant.addingTimeInterval(7 * 86_400), timeZone: at.timeZone), body: body, fulfilled: f))
        }
        return i
    }

    func data() throws -> GrimoireData {
        let repo = MemoryRepository()
        repo.save(reading("2026-01-05", question: "Take the new job?", category: "question/work", card: "maj-16",
                          note: "Felt like the floor dropping", outcome: (.yes, "The team was cut a month later")))
        repo.save(reading("2026-02-10", question: "Move flats?", category: "question/home", card: "maj-16", orientation: .reversed,
                          outcome: (.no, "Nothing changed")))
        repo.save(reading("2026-03-01", question: "Pitch the client?", category: "question/work", card: "maj-16",
                          outcome: (.partly, "Half the project was dropped")))
        repo.save(reading("2026-03-02", question: "Something else", card: "cups-03"))
        var cast = Inquiry(question: "What now?", askedAt: TestSupport.date("2026-03-05T09:00:00-08:00"))
        cast.divinations = [Divination(system: .yijing, performedAt: cast.askedAt, notes: "Strong, steady", cast: try YiJingCast(quick: "777779"))]
        repo.save(cast)
        return repo.data
    }

    func testCardMeaning() throws {
        let m = try XCTUnwrap(Patterns(data: try data(), library: lib).meaning(card: "maj-16", deckId: "rws-tarot"))
        XCTAssertEqual(m.name, "The Tower")
        XCTAssertEqual(m.times, 3)
        XCTAssertEqual(m.timesReversed, 1)
        XCTAssertEqual(m.appearances.map(\.day), ["2026-03-01", "2026-02-10", "2026-01-05"])
        XCTAssertEqual(m.topics.first, Tally(TagPath("question/work"), 2))
        XCTAssertEqual(m.outcomes.answered, 3)
        XCTAssertEqual(m.outcomes.byFulfilled[.yes], 1)
        XCTAssertEqual(m.inYourWords.map(\.text), ["Felt like the floor dropping"])
        XCTAssertEqual(m.whenItCameTrue.map(\.question), ["Pitch the client?", "Take the new job?"])
        XCTAssertEqual(m.summary, "Came up 3 times, 1 reversed, mostly about work and home. "
                       + "Of the 3 readings with an outcome, 1 came true, 1 partly and 1 didn't.")
    }

    func testHexagramMeaningCountsAReadingOnce() throws {
        let p = Patterns(data: try data(), library: lib)
        let cast = try XCTUnwrap(p.meaning(hexagram: 1))
        XCTAssertEqual(cast.times, 1)
        XCTAssertEqual(cast.appearances.first?.position, "cast")
        XCTAssertEqual(cast.appearances.first?.changingLines, [6])
        XCTAssertEqual(cast.appearances.first?.note, "Strong, steady")
        XCTAssertEqual(try XCTUnwrap(p.meaning(hexagram: 43)).appearances.first?.position, "changed into")
        XCTAssertTrue(try XCTUnwrap(p.meaning(hexagram: 1)).summary.hasSuffix("No outcomes recorded yet."))
        XCTAssertNil(p.meaning(hexagram: 2))
    }

    func testAllMeaningsMostFirst() throws {
        let all = Patterns(data: try data(), library: lib).meanings()
        XCTAssertEqual(all.first?.key, "rws-tarot/maj-16")
        XCTAssertEqual(all.count, 4)
    }

    func testFindByName() {
        XCTAssertEqual(lib.symbol(named: "the tower"), .card(deckId: "rws-tarot", cardId: "maj-16"))
        XCTAssertEqual(lib.symbol(named: "rws-tarot/cups-03"), .card(deckId: "rws-tarot", cardId: "cups-03"))
        XCTAssertEqual(lib.symbol(named: "yijing/29"), .hexagram(29))
        XCTAssertEqual(lib.symbol(named: "hexagram 1"), .hexagram(1))
        XCTAssertNil(lib.symbol(named: "nothing like this"))
    }

    func testObsidianCardNoteHasMeaning() throws {
        let files = ObsidianExporter(library: lib).files(for: try data())
        let note = try XCTUnwrap(files.first { $0.key.hasPrefix("Cards/") && $0.value.contains("# The Tower") }?.value)
        XCTAssertTrue(note.contains("## What it has meant for you"))
        XCTAssertTrue(note.contains("### In your words"))
        XCTAssertTrue(note.contains("Felt like the floor dropping"))
        XCTAssertTrue(note.contains("### When it came true"))
        XCTAssertTrue(note.contains("readings_with_outcome: 3"))
        XCTAssertTrue(note.contains("## Every reading"))
    }

    func testReportJSON() throws {
        let m = try XCTUnwrap(Patterns(data: try data(), library: lib).meaning(card: "maj-16", deckId: "rws-tarot"))
        let r = m.report
        XCTAssertEqual(r.key, "rws-tarot/maj-16")
        XCTAssertEqual(r.readings.count, 3)
        XCTAssertEqual(r.outcomes["no"], 1)
        XCTAssertNoThrow(try JSONEncoder().encode(r))
        XCTAssertTrue(m.text.contains("When it came true"))
    }
}
