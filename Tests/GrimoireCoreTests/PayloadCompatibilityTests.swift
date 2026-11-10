import XCTest
@testable import GrimoireCore

/// The Mac app stores each record as a JSON payload. A payload written by an older build must
/// still decode after the model grows, or that record silently disappears from the grimoire.
///
/// Fixtures/payloads/2026-10-28 was written by the first GrimoireCore (commit 18869f8) with the
/// app's encoder (sorted keys, default date strategy). Fixtures/payloads/minimal holds only the
/// identity fields, plus a key no build knows yet.
final class PayloadCompatibilityTests: XCTestCase {
    private func load<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
        let data = try Data(contentsOf: TestSupport.fixture("payloads/\(path)"))
        return try JSONDecoder().decode(type, from: data)
    }

    func testFirstReleasePayloadsDecode() throws {
        let entry = try load(Entry.self, "2026-10-28/entry.json")
        XCTAssertEqual(entry.title, "Fixture ritual")
        XCTAssertEqual(entry.tags, ["practice/fixture"])
        XCTAssertEqual(entry.physicalRef?.page, "12v")
        XCTAssertEqual(entry.fields.durationMin, 20)
        XCTAssertNil(entry.session)
        XCTAssertNil(entry.astro)

        let inquiry = try load(Inquiry.self, "2026-10-28/inquiry.json")
        XCTAssertEqual(inquiry.divinations.count, 2)
        XCTAssertEqual(inquiry.divinations[0].draws.first?.orientation, .reversed)
        XCTAssertEqual(inquiry.divinations[1].cast?.lines, [7, 8, 9, 6, 7, 7])
        XCTAssertEqual(inquiry.outcomes.first?.fulfilled, .partly)

        let reminder = try load(Reminder.self, "2026-10-28/reminder.json")
        XCTAssertEqual(reminder.repeat, .none)
        XCTAssertNil(reminder.anchorOn)

        let item = try load(InboxItem.self, "2026-10-28/inbox-item.json")
        XCTAssertEqual(item.source, "phone:fixture")
        XCTAssertNil(item.notes)
        XCTAssertNil(item.outcome)

        XCTAssertEqual(try load(Volume.self, "2026-10-28/volume.json").pagination, .page)
    }

    func testIdentityOnlyPayloadsDecodeWithDefaults() throws {
        let entry = try load(Entry.self, "minimal/entry.json")
        XCTAssertEqual(entry.body, "")
        XCTAssertEqual(entry.status, .filed)
        XCTAssertEqual(entry.mode, .reflective)
        XCTAssertEqual(entry.createdAt, entry.occurredAt.instant)
        XCTAssertEqual(entry.updatedAt, entry.createdAt)

        let inquiry = try load(Inquiry.self, "minimal/inquiry.json")
        XCTAssertEqual(inquiry.status, .open)
        XCTAssertEqual(inquiry.question, "")
        XCTAssertEqual(inquiry.divinations.first?.draws.first?.orientation, .upright)

        XCTAssertEqual(try load(Reminder.self, "minimal/reminder.json").status, .pending)
        XCTAssertEqual(try load(Volume.self, "minimal/volume.json").name, "")
        let item = try load(InboxItem.self, "minimal/inbox-item.json")
        XCTAssertEqual(item.entry.status, .inbox)
        XCTAssertEqual(item.source, "unknown")
    }

    /// What the app writes today reads back unchanged.
    func testCurrentPayloadsRoundTrip() throws {
        let old = try load(Inquiry.self, "2026-10-28/inquiry.json")
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try JSONDecoder().decode(Inquiry.self, from: enc.encode(old)), old)
        let entry = try load(Entry.self, "2026-10-28/entry.json")
        XCTAssertEqual(try JSONDecoder().decode(Entry.self, from: enc.encode(entry)), entry)
    }

    /// A broken identity field still fails loudly: a record without an id is not a record.
    func testMissingIdentityStillFails() {
        let data = Data(#"{"type":"journal","occurredAt":{"instant":0,"timeZone":"UTC"}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Entry.self, from: data))
    }
}
