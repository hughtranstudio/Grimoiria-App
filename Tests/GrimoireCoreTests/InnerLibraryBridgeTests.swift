import XCTest
@testable import GrimoireCore

/// A pretend Inner Library: answers each action from a script and records what the bridge sent.
final class FakeLibrary: BridgeTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [[String: Any]] = []
    var waiting: [[String: Any]]
    var status = 200

    init(waiting: [[String: Any]]) { self.waiting = waiting }

    var sent: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return _sent }
    var actions: [String] { sent.compactMap { $0["action"] as? String } }

    func post(_ body: Data) async throws -> (Int, Data) {
        let o = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        lock.lock(); _sent.append(o); lock.unlock()
        if status != 200 { return (status, Data(#"{"error":"Not allowed"}"#.utf8)) }
        let reply: [String: Any]
        switch o["action"] as? String {
        case "hello": reply = ["ok": true, "waiting": waiting.count]
        case "pull": reply = ["captures": waiting]
        case "ack": reply = ["collected": (o["ids"] as? [String])?.count ?? 0]
        case "status": reply = ["ok": true]
        default: return (400, Data(#"{"error":"Unknown action"}"#.utf8))
        }
        return (200, try JSONSerialization.data(withJSONObject: reply))
    }
}

final class InnerLibraryBridgeTests: XCTestCase {
    var root: URL!

    override func setUp() { root = TestSupport.tempDir() }

    func capture(_ id: String, kind: String = "omen", text: String = "Two crows on the fence.", device: String = "inner-library") -> [String: Any] {
        ["contract_version": 1, "id": id, "captured_at": "2026-11-09T05:42:21-08:00", "device": device,
         "kind_hint": kind, "text": text, "tags": ["entity/animal/crow", "source/inner-library"]]
    }

    func testSyncWritesCapturesAcksThemAndSendsTheStatusCard() async throws {
        let site = FakeLibrary(waiting: [capture("20261109-054221-il9da8d6"), capture("20261109-054218-il65eab5", kind: "dream", text: "The red door\n\nA red door in the desert.")])
        let bridge = InnerLibraryBridge(inbox: root, transport: site)
        let status = Data(#"{"app":"grimoiria","format":1,"inboxWaiting":9,"checkInsDue":0,"openInquiries":0,"today":"2026-11-09"}"#.utf8)

        let report = try await bridge.sync(status: status)

        XCTAssertEqual(report.delivered, ["20261109-054221-il9da8d6", "20261109-054218-il65eab5"])
        XCTAssertEqual(report.collected, 2)
        XCTAssertTrue(report.statusSent)
        XCTAssertEqual(site.actions, ["pull", "ack", "status"])
        XCTAssertEqual(site.sent[1]["ids"] as? [String], report.delivered)
        XCTAssertEqual((site.sent[2]["status"] as? [String: Any])?["inboxWaiting"] as? Int, 9)

        // What landed is a sidecar the normal ingest accepts, as a dream from the Inner Library.
        let file = bridge.incoming.appendingPathComponent("20261109-054218-il65eab5.json")
        let sidecar = try CaptureSidecar.decode(Data(contentsOf: file))
        XCTAssertEqual(sidecar.entryType, .dream)
        XCTAssertEqual(sidecar.device, "inner-library")
        XCTAssertEqual(sidecar.text, "The red door\n\nA red door in the desert.")
    }

    func testTheIngestorFilesARoomCaptureInTheInbox() async throws {
        let site = FakeLibrary(waiting: [capture("20261109-054221-il9da8d6")])
        _ = try await InnerLibraryBridge(inbox: root, transport: site).sync()
        let ingestor = InboxIngestor(root: root, transcriber: SidecarTextTranscriber(), parser: TestSupport.parser)
        ingestor.defaultTimeZone = "America/Los_Angeles"
        let repo = MemoryRepository()
        let outcomes = await ingestor.scan(now: Date(), isKnown: repo.knowsCapture, deliver: repo.addToInbox)
        XCTAssertEqual(outcomes, [.ingested(captureId: "20261109-054221-il9da8d6")])
        XCTAssertEqual(repo.data.inbox.first?.entry.type, .omen)
        XCTAssertEqual(repo.data.inbox.first?.source, "phone:inner-library")
    }

    func testACaptureAlreadyOnDiskIsNotRewrittenButIsStillCleared() async throws {
        let id = "20261109-054221-il9da8d6"
        try FileManager.default.createDirectory(at: root.appendingPathComponent("processed"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appendingPathComponent("processed/\(id).json"))
        let site = FakeLibrary(waiting: [capture(id)])
        let report = try await InnerLibraryBridge(inbox: root, transport: site).sync()
        XCTAssertEqual(report.delivered, [])
        XCTAssertEqual(report.alreadyHere, [id])
        XCTAssertEqual(site.sent.last?["ids"] as? [String], [id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("incoming/\(id).json").path))
    }

    func testUnsafeOrForeignCapturesAreRefusedAndLeftOnTheSite() async throws {
        var withAudio = capture("20261109-054221-ilaaaaaa")
        withAudio["audio"] = "x.m4a"
        let site = FakeLibrary(waiting: [
            capture("../../evil"),
            capture("20261109-054221-ilbbbbbb", device: "iphone"),
            withAudio,
            ["contract_version": 2, "id": "20261109-054221-ilcccccc", "captured_at": "2026-11-09T05:42:21-08:00"],
        ])
        let report = try await InnerLibraryBridge(inbox: root, transport: site).sync()
        XCTAssertEqual(report.delivered, [])
        XCTAssertEqual(report.refused.count, 4)
        XCTAssertEqual(site.actions, ["pull"], "nothing to ack")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        XCTAssertFalse(names.contains("evil"))
    }

    func testARefusalSaysWhyInPlainWords() async throws {
        let site = FakeLibrary(waiting: [])
        site.status = 401
        do {
            _ = try await InnerLibraryBridge(inbox: root, transport: site).hello()
            XCTFail("should throw")
        } catch let e as BridgeError {
            XCTAssertEqual(e, .refused(401, "Not allowed"))
            XCTAssertTrue(e.description.contains("INTIMA_BRIDGE_TOKEN"))
        }
    }

    func testTheHTTPTransportNeedsALongTokenAndHttps() throws {
        let token = String(repeating: "a", count: 64)
        XCTAssertThrowsError(try HTTPBridgeTransport(site: "https://hughtranstudio.com", token: "short"))
        XCTAssertThrowsError(try HTTPBridgeTransport(site: "http://hughtranstudio.com", token: token))
        XCTAssertEqual(try HTTPBridgeTransport(site: "https://hughtranstudio.com", token: token).url.absoluteString, "https://hughtranstudio.com/api/intima/bridge")
        XCTAssertNoThrow(try HTTPBridgeTransport(site: "http://localhost:4321", token: token))
    }
}
