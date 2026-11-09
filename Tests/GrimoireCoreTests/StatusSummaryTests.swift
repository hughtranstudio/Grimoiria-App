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

final class InboxAgeAndLinkTests: XCTestCase {
    func testOldestInboxCaptureAndItsAge() {
        let repo = MemoryRepository()
        let older = Entry(type: .journal, occurredAt: TestSupport.date("2026-10-29T07:00:00-07:00"),
                          createdAt: TestSupport.date("2026-10-29T12:00:00Z").instant, status: .inbox)
        let newer = Entry(type: .journal, occurredAt: TestSupport.date("2026-11-02T07:00:00-07:00"),
                          createdAt: TestSupport.date("2026-11-02T12:00:00Z").instant, status: .inbox)
        repo.addToInbox(InboxItem(entry: newer, draft: nil, source: "phone:pixel"))
        repo.addToInbox(InboxItem(entry: older, draft: nil, source: "phone:pixel"))
        let s = StatusSummary(data: repo.data, today: "2026-11-04")
        XCTAssertEqual(s.inboxWaiting, 2)
        XCTAssertEqual(s.inboxOldest, "2026-10-29")
        XCTAssertEqual(s.inboxOldestDays, 6)
        XCTAssertEqual(s.inboxLink, "grimoire://inbox")
    }

    func testEmptyInboxHasNoAge() throws {
        let s = StatusSummary(data: GrimoireData(), today: "2026-11-04")
        XCTAssertNil(s.inboxOldest)
        XCTAssertNil(s.inboxOldestDays)
        let text = String(decoding: try s.json(), as: UTF8.self)
        XCTAssertTrue(text.contains("\"inboxLink\" : \"grimoire://inbox\""))
    }

    func testDaysNeverNegative() {
        XCTAssertEqual(StatusSummary.days(from: "2026-10-31", to: "2026-11-01"), 1)
        XCTAssertEqual(StatusSummary.days(from: "2026-11-05", to: "2026-11-04"), 0)
        XCTAssertNil(StatusSummary.days(from: "soon", to: "2026-11-04"))
    }

    func testLinksRoundTrip() {
        let id = ULID()
        for link in [GrimoireLink.today, .inbox(nil), .inbox(id), .entry(id), .inquiry(id)] {
            XCTAssertEqual(GrimoireLink(link.url), link)
        }
        XCTAssertEqual(GrimoireLink(string: "grimoire://entry/\(id)"), .entry(id))
        XCTAssertEqual(GrimoireLink(string: "GRIMOIRE://Inbox"), .inbox(nil))
    }

    func testBadLinksAreRefused() {
        XCTAssertNil(GrimoireLink(string: "https://inbox"))
        XCTAssertNil(GrimoireLink(string: "grimoire://entry"))
        XCTAssertNil(GrimoireLink(string: "grimoire://entry/not-an-id"))
        XCTAssertNil(GrimoireLink(string: "grimoire://altar/\(ULID())"))
        XCTAssertNil(GrimoireLink(string: "grimoire://entry/\(ULID())/extra"))
    }

    /// The calendar export's links are ones the app can open.
    func testCalendarLinksParse() {
        let id = ULID()
        XCTAssertNotNil(GrimoireLink(string: "grimoire://entry/\(id)"))
        XCTAssertNotNil(GrimoireLink(string: "grimoire://inquiry/\(id)"))
    }
}

final class StatusCardTests: XCTestCase {
    func testTheEcosystemCardShape() throws {
        let repo = MemoryRepository()
        let at = TestSupport.date("2026-11-01T09:00:00-07:00")
        repo.addToInbox(InboxItem(entry: Entry(type: .journal, occurredAt: at, createdAt: at.instant, status: .inbox), draft: nil, source: "phone:pixel"))
        let s = StatusSummary(data: repo.data, today: "2026-11-09")
        XCTAssertEqual(s.app, "grimoiria")
        XCTAssertEqual(s.written, "2026-11-09")
        XCTAssertTrue(s.ok)
        XCTAssertEqual(s.needs_you, 1)
        XCTAssertEqual(s.counts["inbox"], 1)
        XCTAssertNil(s.counts["nudges"])
        XCTAssertEqual(s.links["inbox"], "grimoire://inbox")
        XCTAssertEqual(s.links["open"], "grimoire://today")
        XCTAssertTrue(s.headline.hasPrefix("1 in the Inbox (oldest"), s.headline)
        let json = try JSONSerialization.jsonObject(with: s.json()) as? [String: Any]
        for key in ["app", "format", "written", "ok", "headline", "needs_you", "counts", "links"] {
            XCTAssertNotNil(json?[key], key)
        }
        // The keys Mission Control already reads stay.
        for key in ["today", "inboxWaiting", "checkInsDue", "openInquiries", "lastPractice", "practicedToday"] where key != "lastPractice" {
            XCTAssertNotNil(json?[key], key)
        }
    }

    func testHeadlineWording() {
        XCTAssertEqual(StatusSummary.headline(inbox: 0, oldestDays: nil, due: 0, practicedToday: true, lastPractice: "2026-11-09"), "practised today")
        XCTAssertEqual(StatusSummary.headline(inbox: 9, oldestDays: 6, due: 1, practicedToday: false, lastPractice: "2026-10-29"),
                       "9 in the Inbox (oldest 6 days), 1 check-in due, last practice 2026-10-29")
        XCTAssertEqual(StatusSummary.headline(inbox: 1, oldestDays: 0, due: 2, practicedToday: false, lastPractice: nil),
                       "1 in the Inbox (from today), 2 check-ins due, no practice recorded yet")
    }
}
