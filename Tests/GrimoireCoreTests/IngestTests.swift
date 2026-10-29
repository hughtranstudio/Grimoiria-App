import XCTest
@testable import GrimoireCore

final class IngestTests: XCTestCase {
    var root: URL!
    var repo: MemoryRepository!
    var ingestor: InboxIngestor!
    let fm = FileManager.default
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        root = TestSupport.tempDir()
        repo = MemoryRepository()
        ingestor = InboxIngestor(root: root, transcriber: SidecarTextTranscriber(), parser: TestSupport.parser)
        ingestor.location = GeoLocation(latitude: 37.77, longitude: -122.42)
        ingestor.defaultTimeZone = "America/Los_Angeles"
    }

    func dropFixturePair() throws {
        try fm.createDirectory(at: ingestor.incoming, withIntermediateDirectories: true)
        for ext in ["m4a", "txt", "json"] {
            let name = "20261028-081400-4821.\(ext)"
            let dest = ingestor.incoming.appendingPathComponent(name)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: TestSupport.fixture("capture/\(name)"), to: dest)
        }
    }

    func scan(_ at: Date) async -> [InboxIngestor.Outcome] {
        await ingestor.scan(now: at, isKnown: repo.knowsCapture, deliver: repo.addToInbox)
    }

    func testCapturePairArrivesParsedInInboxAfterAudioIsStable() async throws {
        try dropFixturePair()
        // First sighting of the audio: wait for its size to be stable for 3 s.
        let first = await scan(t0)
        XCTAssertEqual(first, [.waiting(file: "20261028-081400-4821.json", reason: "audio still being written")])
        XCTAssertTrue(repo.data.inbox.isEmpty)
        let second = await scan(t0.addingTimeInterval(3.5))
        XCTAssertEqual(second, [.ingested(captureId: "20261028-081400-4821")])

        let item = try XCTUnwrap(repo.data.inbox.first)
        XCTAssertEqual(item.entry.status, .inbox)
        XCTAssertEqual(item.entry.captureId, "20261028-081400-4821")
        XCTAssertEqual(item.entry.occurredAt.iso8601, "2026-10-28T08:14:00-07:00")
        XCTAssertEqual(item.entry.occurredAt.timeZone, "America/Los_Angeles")
        XCTAssertEqual(item.entry.tags, ["theme/threshold"])
        XCTAssertEqual(item.entry.attachments.first?.kind, .audio)
        XCTAssertNotNil(item.entry.timing?.planetaryHour)
        let draft = try XCTUnwrap(item.draft)
        XCTAssertEqual(draft.question.value, "will the move go ahead?")
        XCTAssertEqual(draft.divinations.first?.draws.map(\.cardId.value), ["cups-03", "maj-16", "wands-11"])

        // Files moved to processed/
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: ingestor.incoming.path), [])
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: ingestor.processed.path)).count, 3)
        // Nothing filed yet.
        XCTAssertTrue(repo.data.entries.isEmpty && repo.data.inquiries.isEmpty)
    }

    func testDroppingTheSameCaptureAgainIsANoOp() async throws {
        ingestor.stableSeconds = 0
        try dropFixturePair()
        _ = await scan(t0)
        try dropFixturePair()
        let again = await scan(t0.addingTimeInterval(10))
        XCTAssertEqual(again, [.duplicate(captureId: "20261028-081400-4821")])
        XCTAssertEqual(repo.data.inbox.count, 1)
        XCTAssertFalse(fm.fileExists(atPath: ingestor.incoming.appendingPathComponent("20261028-081400-4821.json").path))
    }

    func testWaitsForMissingAudioAndICloudPlaceholder() async throws {
        try fm.createDirectory(at: ingestor.incoming, withIntermediateDirectories: true)
        let json = try Data(contentsOf: TestSupport.fixture("capture/20261028-081400-4821.json"))
        try json.write(to: ingestor.incoming.appendingPathComponent("20261028-081400-4821.json"))
        var out = await scan(t0)
        XCTAssertEqual(out, [.waiting(file: "20261028-081400-4821.json", reason: "audio not arrived yet")])
        try Data().write(to: ingestor.incoming.appendingPathComponent(".20261028-081400-4821.m4a.icloud"))
        out = await scan(t0)
        XCTAssertEqual(out, [.waiting(file: "20261028-081400-4821.json", reason: "audio is an iCloud placeholder; download requested")])
    }

    func testBadSidecarMovesToFailedWithReason() async throws {
        try fm.createDirectory(at: ingestor.incoming, withIntermediateDirectories: true)
        try Data(#"{"contract_version": 2, "id": "x", "captured_at": "2026-10-28T08:14:00-07:00"}"#.utf8)
            .write(to: ingestor.incoming.appendingPathComponent("x.json"))
        let out = await scan(t0)
        guard case .failed(let file, let reason) = out.first else { return XCTFail("\(out)") }
        XCTAssertEqual(file, "x.json")
        XCTAssertTrue(reason.contains("unsupported contract_version 2"))
        let err = try String(contentsOf: ingestor.failed.appendingPathComponent("x.error.txt"), encoding: .utf8)
        XCTAssertTrue(err.contains("contract_version"))
        XCTAssertTrue(fm.fileExists(atPath: ingestor.failed.appendingPathComponent("x.json").path))
    }

    func testTranscriptionFailureMovesPairToFailed() async throws {
        ingestor.stableSeconds = 0
        try dropFixturePair()
        try fm.removeItem(at: ingestor.incoming.appendingPathComponent("20261028-081400-4821.txt"))
        let out = await scan(t0)
        guard case .failed = out.first else { return XCTFail("\(out)") }
        XCTAssertTrue(fm.fileExists(atPath: ingestor.failed.appendingPathComponent("20261028-081400-4821.m4a").path))
        XCTAssertTrue(repo.data.inbox.isEmpty)
    }

    func testTextOnlyOmenCapture() async throws {
        try fm.createDirectory(at: ingestor.incoming, withIntermediateDirectories: true)
        try Data(#"{"contract_version":1,"id":"20261028-090000-1111","captured_at":"2026-10-28T09:00:00Z","kind_hint":"omen","text":"Crow on the gate","tags":["entity/crow"]}"#.utf8)
            .write(to: ingestor.incoming.appendingPathComponent("20261028-090000-1111.json"))
        let out = await scan(t0)
        XCTAssertEqual(out, [.ingested(captureId: "20261028-090000-1111")])
        let item = try XCTUnwrap(repo.data.inbox.first)
        XCTAssertEqual(item.entry.type, .omen)
        XCTAssertNil(item.draft)
        XCTAssertEqual(item.entry.body, "Crow on the gate")
    }

    /// The Android app sends its own transcript and the reading the user checked on the phone.
    /// The Mac keeps both (no second transcription, no re-parse) but the item still waits in the Inbox.
    func testAndroidCaptureKeepsPhoneTranscriptAndCheckedDraft() async throws {
        struct NoTranscriber: Transcriber {
            func transcribe(_ audio: URL) async throws -> String { throw IngestError.transcription("should not be called") }
        }
        ingestor = InboxIngestor(root: root, transcriber: NoTranscriber(), parser: TestSupport.parser)
        ingestor.defaultTimeZone = "America/Los_Angeles"
        ingestor.stableSeconds = 0
        try fm.createDirectory(at: ingestor.incoming, withIntermediateDirectories: true)
        for ext in ["wav", "json"] {
            let name = "20261029-071500-3307.\(ext)"
            try fm.copyItem(at: TestSupport.fixture("capture-android/\(name)"), to: ingestor.incoming.appendingPathComponent(name))
        }
        let out = await scan(t0)
        XCTAssertEqual(out, [.ingested(captureId: "20261029-071500-3307")])
        let item = try XCTUnwrap(repo.data.inbox.first)
        XCTAssertEqual(item.source, "phone:pixel")
        XCTAssertEqual(item.entry.status, .inbox)
        XCTAssertEqual(item.entry.type, .divination)
        XCTAssertTrue(item.entry.transcript?.hasPrefix("Question: will the move go ahead.") ?? false)
        let d = try XCTUnwrap(item.draft?.divinations.first)
        XCTAssertEqual(d.draws.map(\.cardId.value), ["cups-03", "maj-16", "wands-11"])
        XCTAssertEqual(d.draws[1].cardId.heard, "tour") // corrected on the phone, heard text kept
        XCTAssertEqual(item.draft?.weakest, .high)
        XCTAssertTrue(repo.data.entries.isEmpty)
    }

    func testSidecarSchemaRequirements() {
        XCTAssertThrowsError(try CaptureSidecar.decode(Data(#"{"contract_version":1,"id":"a"}"#.utf8)))
        XCTAssertThrowsError(try CaptureSidecar.decode(Data(#"{"contract_version":1,"id":"a","captured_at":"yesterday"}"#.utf8)))
        XCTAssertThrowsError(try CaptureSidecar.decode(Data(#"{"contract_version":1,"id":"a","captured_at":"2026-10-28T08:14:00Z","audio":"../x.m4a"}"#.utf8)))
        XCTAssertNoThrow(try CaptureSidecar.decode(Data(#"{"contract_version":1,"id":"a","captured_at":"2026-10-28T08:14:00Z"}"#.utf8)))
    }
}
