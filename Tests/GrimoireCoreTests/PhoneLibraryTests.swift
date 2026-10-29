import XCTest
@testable import GrimoireCore

/// The Mac → phone library (docs/phone-library.md) and outcomes coming back from the phone.
final class PhoneLibraryTests: XCTestCase {
    let fm = FileManager.default
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// A small grimoire with one of each record the phone shows. Fixed ids so the fixture is stable.
    static func sample() -> GrimoireData {
        let asked = TestSupport.date("2026-10-20T08:14:00-07:00")
        let created = Date(timeIntervalSince1970: 1_792_000_000)
        var inq = Inquiry(id: ULID("01JBQ8Y5X0AAAAAAAAAAAAAAAA")!, question: "Will the move go ahead?", askedAt: asked,
                          context: "Flat on Elm Street", tags: ["question/home", "theme/threshold"], createdAt: created)
        inq.divinations = [
            Divination(id: ULID("01JBQ8Y5X0AAAAAAAAAAAAAAAB")!, system: .cards, deckId: "rws-tarot", spreadId: "three-card", performedAt: asked, order: 0,
                       draws: [Draw(id: ULID("01JBQ8Y5X0AAAAAAAAAAAAAAAC")!, cardId: "cups-03", positionKey: "past", orientation: .reversed),
                               Draw(id: ULID("01JBQ8Y5X0AAAAAAAAAAAAAAAD")!, cardId: "maj-16", positionKey: "present"),
                               Draw(id: ULID("01JBQ8Y5X0AAAAAAAAAAAAAAAE")!, cardId: "wands-11", positionKey: "future")]),
            Divination(id: ULID("01JBQ8Y5X0AAAAAAAAAAAAAAAF")!, system: .yijing, performedAt: asked, method: "coins", order: 1,
                       cast: try! YiJingCast(lines: [7, 8, 9, 7, 8, 6], method: .coins)),
        ]
        inq.synthesis = Synthesis(body: "Upheaval first, then a quick move.", writtenAt: asked, confidence: 3)
        inq.addOutcome(Outcome(id: ULID("01JBQ8Y5X0AAAAAAAAAAAAAAAG")!, recordedAt: TestSupport.date("2026-10-27T19:00:00-07:00"),
                               body: "The landlord said yes.", fulfilled: .partly))

        var vision = Entry(id: ULID("01JBQ8Y5X0AAAAAAAAAAAAAAAH")!, type: .vision, title: "Inner library",
                           occurredAt: TestSupport.date("2026-10-21T21:30:00-07:00"), createdAt: created,
                           body: "A red door in the desert.", tags: ["place/inner-library"])
        vision.session = PracticeSession(startedAt: TestSupport.date("2026-10-21T21:30:00-07:00"),
                                         endedAt: TestSupport.date("2026-10-21T22:05:00-07:00"),
                                         phases: [PhaseMark(.opening, at: 0), PhaseMark(.working, at: 300)],
                                         observations: [Observation(id: ULID("01JBQ8Y5X0AAAAAAAAAAAAAAAJ")!, offset: 640, kind: .entity,
                                                                    text: "Robed figure at the door", tags: ["entity/being/guardian"], capture: .live)],
                                         before: StateCheck(energy: 3, calm: 2, focus: 3), after: StateCheck(energy: 4, calm: 4, focus: 4),
                                         outcome: "Came back calm.")
        let journal = Entry(id: ULID("01JBQ8Y5X0AAAAAAAAAAAAAAAK")!, type: .journal, occurredAt: TestSupport.date("2026-10-22T07:00:00-07:00"),
                            createdAt: created, body: "Woke early. Crow on the fence.", tags: ["entity/animal/crow"])
        var d = GrimoireData()
        d.inquiries = [inq]
        d.entries = [vision, journal]
        d.reminders = [Reminder(id: ULID("01JBQ8Y5X0AAAAAAAAAAAAAAAM")!, targetId: inq.id, dueOn: "2026-11-19",
                                prompt: OutcomeCheckIn.prompt(days: 30), repeat: .ladder, anchorOn: "2026-10-20", step: 30)]
        return d
    }

    func testWritesLibraryAndOnlyRewritesWhenSomethingChanged() throws {
        let root = TestSupport.tempDir()
        let lib = PhoneLibrary(library: TestSupport.library, vocabulary: .standard)
        XCTAssertTrue(try lib.write(Self.sample(), to: root, now: t0))
        let folder = root.appendingPathComponent("library")
        for f in ["grimoire.jsonl", "tag-vocabulary.json", "manifest.json"] {
            XCTAssertTrue(fm.fileExists(atPath: folder.appendingPathComponent(f).path), f)
        }
        let manifest = try JSONDecoder().decode(PhoneLibrary.Manifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        XCTAssertEqual(manifest.entries, 2)
        XCTAssertEqual(manifest.inquiries, 1)
        XCTAssertEqual(manifest.reminders, 1)

        // Same data an hour later: nothing is touched, so Syncthing has nothing to send.
        XCTAssertFalse(try lib.write(Self.sample(), to: root, now: t0.addingTimeInterval(3600)))

        var changed = Self.sample()
        changed.entries[1].body += " It called three times."
        XCTAssertTrue(try lib.write(changed, to: root, now: t0.addingTimeInterval(7200)))
    }

    /// The phone's Kotlin reader is tested against this file (android/core LibraryTest).
    /// Regenerate with GRIMOIRE_REGENERATE_GOLDEN=1 after a deliberate format change.
    func testSampleMatchesTheSharedFixture() throws {
        let (jsonl, _, _) = try PhoneLibrary(library: TestSupport.library, vocabulary: .standard).files(Self.sample(), now: t0)
        let fixture = TestSupport.fixture("phone-library/grimoire.jsonl")
        if ProcessInfo.processInfo.environment["GRIMOIRE_REGENERATE_GOLDEN"] == "1" {
            let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/phone-library/grimoire.jsonl")
            try fm.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
            try jsonl.write(to: source, atomically: true, encoding: .utf8)
            return
        }
        XCTAssertEqual(jsonl, try String(contentsOf: fixture, encoding: .utf8))
    }

    func testOutcomeFromThePhoneWaitsInTheInboxThenJoinsItsReading() async throws {
        let repo = MemoryRepository()
        for i in Self.sample().inquiries { repo.save(i) }
        let root = TestSupport.tempDir()
        let ingestor = InboxIngestor(root: root, transcriber: SidecarTextTranscriber(), parser: TestSupport.parser)
        ingestor.stableSeconds = 0
        try fm.createDirectory(at: ingestor.incoming, withIntermediateDirectories: true)
        let sidecar = """
        {"contract_version":1,"id":"20261110-090000-1234","captured_at":"2026-11-10T09:00:00-08:00","device":"pixel",
         "kind_hint":"outcome","inquiry_id":"01JBQ8Y5X0AAAAAAAAAAAAAAAA","text":"Moved in on the 9th.","outcome":{"fulfilled":"yes"}}
        """
        try Data(sidecar.utf8).write(to: ingestor.incoming.appendingPathComponent("20261110-090000-1234.json"))
        let out = await ingestor.scan(now: t0, isKnown: repo.knowsCapture, deliver: repo.addToInbox)
        XCTAssertEqual(out, [.ingested(captureId: "20261110-090000-1234")])

        let item = try XCTUnwrap(repo.data.inbox.first)
        XCTAssertNil(item.draft, "an outcome is never parsed as a reading")
        XCTAssertEqual(item.outcome?.fulfilled, .yes)
        XCTAssertEqual(repo.inquiry(ULID("01JBQ8Y5X0AAAAAAAAAAAAAAAA")!)?.outcomes.count, 1, "nothing changes before Confirm")

        let result = try repo.confirm(item.id, corrected: nil, library: TestSupport.library)
        let inq = try XCTUnwrap(result.inquiry)
        XCTAssertEqual(inq.outcomes.count, 2)
        XCTAssertEqual(inq.outcomes.last?.body, "Moved in on the 9th.")
        XCTAssertEqual(inq.status, .revisited)
        XCTAssertTrue(repo.data.inbox.isEmpty)
        XCTAssertTrue(repo.data.entries.isEmpty, "the carrier entry is not filed")
    }

    /// The phone checks library files with the same hash (android/core LibraryTest).
    func testChecksumIsFNV1a64() {
        XCTAssertEqual(PhoneLibrary.checksum(""), "0-cbf29ce484222325")
        XCTAssertEqual(PhoneLibrary.checksum("abc"), "3-e71fa2190541574b")
    }

    func testOutcomeWithoutAReadingIsRejected() {
        let s = #"{"contract_version":1,"id":"x1","captured_at":"2026-11-10T09:00:00-08:00","kind_hint":"outcome","text":"?"}"#
        XCTAssertThrowsError(try CaptureSidecar.decode(Data(s.utf8)))
    }
}
