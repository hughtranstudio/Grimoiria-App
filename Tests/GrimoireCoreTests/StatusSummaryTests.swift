import XCTest
@testable import GrimoireCore

final class StatusSummaryTests: XCTestCase {
    func testCountsAndLastPractice() throws {
        let repo = MemoryRepository()
        let open = Inquiry(question: "Work?", askedAt: TestSupport.date("2026-10-20T09:00:00-07:00"))
        var done = Inquiry(question: "Old", askedAt: TestSupport.date("2026-06-01T09:00:00-07:00"))
        done.status = .resolved
        repo.save(open)
        repo.save(done)
        repo.save(Entry(type: .ritual, occurredAt: TestSupport.date("2026-10-29T07:00:00-07:00")))
        repo.save(Entry(type: .journal, occurredAt: TestSupport.date("2026-10-31T07:00:00-07:00")))
        let s = StatusSummary(data: repo.data, today: "2026-10-31")
        XCTAssertEqual(s.openInquiries, 1)
        XCTAssertEqual(s.inboxWaiting, 0)
        XCTAssertEqual(s.lastPractice, "2026-10-29")
        XCTAssertFalse(s.practicedToday)
    }

    func testPracticedToday() {
        let repo = MemoryRepository()
        repo.save(Entry(type: .meditation, occurredAt: TestSupport.date("2026-10-31T07:00:00-07:00")))
        let s = StatusSummary(data: repo.data, today: "2026-10-31")
        XCTAssertTrue(s.practicedToday)
        XCTAssertEqual(s.lastPractice, "2026-10-31")
    }

    func testEmptyStoreJSON() throws {
        let s = StatusSummary(data: GrimoireData(), today: "2026-10-31")
        XCTAssertNil(s.lastPractice)
        let text = String(decoding: try s.json(), as: UTF8.self)
        XCTAssertTrue(text.contains("\"checkInsDue\" : 0"))
    }

    func testNudgesNeedTheLibrary() {
        let repo = MemoryRepository()
        for d in ["2026-10-21", "2026-10-24", "2026-10-29"] {
            let at = TestSupport.date("\(d)T09:00:00-07:00")
            var i = Inquiry(question: "Q \(d)", askedAt: at)
            i.divinations = [Divination(system: .cards, deckId: "rws-tarot", spreadId: "freeform", performedAt: at,
                                        draws: [Draw(cardId: "maj-16", positionKey: "1")])]
            repo.save(i)
        }
        XCTAssertNil(StatusSummary(data: repo.data, today: "2026-10-30").nudges)
        XCTAssertEqual(StatusSummary(data: repo.data, today: "2026-10-30", library: TestSupport.library).nudges, 1)
        XCTAssertEqual(StatusSummary(data: repo.data, today: "2026-10-30").openInquiries, 3)
    }
}
