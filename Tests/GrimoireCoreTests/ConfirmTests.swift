import XCTest
@testable import GrimoireCore

final class ConfirmTests: XCTestCase {
    let lib = TestSupport.library

    func makeItem(_ transcript: String) -> InboxItem {
        let entry = Entry(type: .divination, occurredAt: TestSupport.date("2026-10-28T08:14:00-07:00"), body: transcript,
                          mode: .quick, status: .inbox, captureId: "cap-1", transcript: transcript)
        return InboxItem(entry: entry, draft: TestSupport.parser.parse(transcript), source: "phone:iphone")
    }

    func testNothingIsFiledUntilConfirm() throws {
        let repo = MemoryRepository()
        let item = makeItem("Question: will it rain. Deck RWS three card. The Sun, the Moon, the Star")
        repo.addToInbox(item)
        XCTAssertTrue(repo.data.inquiries.isEmpty)
        XCTAssertTrue(repo.data.entries.isEmpty)
        XCTAssertTrue(repo.search(SearchQuery(text: "rain")).isEmpty) // inbox items are not in normal search
        XCTAssertTrue(repo.knowsCapture("cap-1"))

        let result = try repo.confirm(item.id, corrected: item.draft, library: lib, reminder: .oneWeek)
        XCTAssertEqual(repo.data.inbox.count, 0)
        XCTAssertEqual(repo.data.entries.first?.status, .filed)
        let inq = try XCTUnwrap(result.inquiry)
        XCTAssertEqual(inq.question, "will it rain")
        XCTAssertEqual(inq.divinations[0].draws.map(\.cardId), ["maj-19", "maj-18", "maj-17"])
        XCTAssertEqual(repo.data.entries[0].inquiryId, inq.id)
        XCTAssertEqual(repo.data.reminders.first?.dueOn, "2026-11-04")
        XCTAssertTrue(result.corrections.isEmpty)
        XCTAssertTrue(repo.knowsCapture("cap-1"))
    }

    func testCorrectionsAreLogged() throws {
        let repo = MemoryRepository()
        let item = makeItem("Deck RWS three card. Three of cups reversed. The tour. Page of wands.")
        repo.addToInbox(item)
        var fixed = try XCTUnwrap(item.draft)
        // Parser missed "the tour"; Hugh inserts the Tower in position 2 and makes the cups upright.
        fixed.divinations[0].draws.insert(DraftDraw(cardId: Parsed("maj-16", confidence: .high), orientation: Parsed(.upright, confidence: .high), positionKey: "present"), at: 1)
        fixed.divinations[0].draws[2].positionKey = "future"
        fixed.divinations[0].draws[0].orientation = Parsed(.upright, confidence: .high)
        let result = try repo.confirm(item.id, corrected: fixed, library: lib)
        XCTAssertEqual(result.inquiry?.divinations[0].draws.map(\.cardId), ["cups-03", "maj-16", "wands-11"])
        let fields = result.corrections.map(\.field)
        XCTAssertTrue(fields.contains("orientation"))
        XCTAssertTrue(result.corrections.contains { $0.field == "card" && $0.heard == nil && $0.corrected == "maj-16" })
        XCTAssertEqual(result.corrections.count, 2)
        XCTAssertEqual(repo.data.corrections.count, 2)
    }

    func testConfirmRefusesIncompleteDraft() {
        let item = makeItem("Deck RWS. The Fool")
        var bad = item.draft!
        bad.divinations[0].draws[0].cardId = .missing
        XCTAssertThrowsError(try Confirmation.confirm(item, corrected: bad, library: lib)) {
            XCTAssertEqual($0 as? ConfirmError, .unresolvedCard(divination: 0, draw: 0))
        }
        var unknown = item.draft!
        unknown.divinations[0].draws[0].cardId = Parsed("maj-99", confidence: .high)
        XCTAssertThrowsError(try Confirmation.confirm(item, corrected: unknown, library: lib))
    }

    func testYiJingConfirm() throws {
        let item = makeItem("Yi Jing coins seven eight nine")
        var fixed = item.draft!
        XCTAssertThrowsError(try Confirmation.confirm(item, corrected: fixed, library: lib))
        fixed.divinations[0].cast?.lines = Parsed([7, 8, 9, 6, 7, 7], confidence: .high)
        let r = try Confirmation.confirm(item, corrected: fixed, library: lib)
        XCTAssertEqual(r.inquiry?.divinations[0].cast?.primaryHexagram(in: lib.yijing), 37)
        XCTAssertEqual(r.corrections.first?.field, "yijing-lines")
    }

    func testPlainCaptureFilesAsEntryOnly() throws {
        var entry = Entry(type: .omen, occurredAt: TestSupport.date("2026-10-28T08:14:00-07:00"), body: "Crow on the gate", status: .inbox)
        entry.tags = ["entity/crow"]
        let item = InboxItem(entry: entry, draft: nil, source: "phone:iphone")
        let r = try Confirmation.confirm(item, corrected: nil, library: lib)
        XCTAssertNil(r.inquiry)
        XCTAssertEqual(r.entry.type, .omen)
        XCTAssertEqual(r.entry.status, .filed)
    }
}
