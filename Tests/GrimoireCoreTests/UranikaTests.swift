import XCTest
@testable import GrimoireCore

/// Stands in for Uranika's server. Every moment is the same sky; the natal chart is fixed.
final class FakeUranika: UranikaService, @unchecked Sendable {
    var open = true
    var requests: [UranikaComputeRequest] = []
    var events: [UranikaEvent] = []
    let lock = NSLock()

    static let sky: [String: Double] = [
        "SUN": 216.12, "MOO": 302.48, "MER": 230.0, "VEN": 250.0, "MAR": 170.0, "JUP": 110.0, "SAT": 25.5, "URA": 57.0,
        "NEP": 357.0, "PLU": 301.0, "NOD": 355.0, "CUP": 132.0, "HAD": 190.0, "ZEU": 160.0, "KRO": 101.33,
        "APO": 145.0, "ADM": 85.0, "VUL": 125.0, "POS": 185.0,
    ]
    static let natal: [String: Double] = [
        "SUN": 10, "MOO": 0, "MER": 20.3, "VEN": 33.7, "MAR": 61.1, "JUP": 100, "SAT": 205.2, "URA": 222.9,
        "NEP": 263.4, "PLU": 202.6, "NOD": 152.8, "CUP": 108.2, "HAD": 343.9, "ZEU": 113.1, "KRO": 132.6,
        "APO": 147.4, "ADM": 74.5, "VUL": 112.2, "POS": 166.9,
    ]
    static let chart = UranikaChart(id: 1, name: "Hugh Tran", date: "1990-01-01", time: "12:00", tz: "America/Los_Angeles", lat: 37.77, lon: -122.42)

    func check() throws {
        if !open { throw UranikaError.unreachable("Could not connect to the server.") }
    }

    func health() async throws -> String { try check(); return "2.10" }

    func compute(_ request: UranikaComputeRequest) async throws -> UranikaComputeResult {
        try check()
        lock.withLock { requests.append(request) }
        let isNatal = request.date == Self.chart.date
        func pts(_ m: [String: Double]) -> [String: UranikaComputeResult.Point] { m.mapValues { .init(lon: $0) } }
        let natal = UranikaComputeResult.Natal(points: pts(isNatal ? Self.natal : Self.sky), asc: isNatal ? 270.0 : 128.4, mc: isNatal ? 25.9 : 25.9)
        return UranikaComputeResult(natal: natal, transit: .init(points: pts(Self.sky)), arc: isNatal ? 40 : 0)
    }

    func charts() async throws -> [UranikaChart] { try check(); return [Self.chart] }

    func addEvent(_ event: UranikaEvent) async throws -> Int {
        try check()
        lock.withLock { events.append(event) }
        return 57
    }
}

final class UranikaTests: XCTestCase {
    let moment = TestSupport.date("2026-10-29T00:45:00-07:00")

    func astrologer(_ fake: FakeUranika, natal: Int? = 1) -> UranikaAstrologer {
        UranikaAstrologer(service: fake, settings: UranikaSettings(natalChartId: natal, home: AstroPlace(name: "Home", latitude: 37.7749, longitude: -122.4194)))
    }

    // MARK: Arithmetic (ported from Uranika's astro.js)

    func testHitsOnPointsAndMidpoints() {
        let hits = UranianMath.hits(method: .transit, movers: ["SA": 25.5, "JU": 140], targets: ["MC": 25.9, "SU": 10, "MO": 0, "AS": 280.2],
                                    modulus: 45, orb: 1)
        XCTAssertTrue(hits.contains(AstroHit(method: .transit, mover: "SA", target: ["MC"], angle: 0, orb: 0.39999999999999858)))
        // 2 × 140 − 10 − 0 = 270 ≡ 0 (mod 90): Jupiter exactly on the Sun/Moon midpoint.
        XCTAssertEqual(hits.first?.formula, "T-JU = R-SU/MO")
        XCTAssertEqual(hits.first?.orb, 0)
        // 140 − 280.2 = −140.2 → 135° family, 5.2° off at mod 45 → outside the orb.
        XCTAssertFalse(hits.contains { $0.mover == "JU" && $0.target == ["AS"] })
        XCTAssertEqual(hits.map(\.orb), hits.map(\.orb).sorted())
    }

    func testAngleAndLabels() {
        XCTAssertEqual(UranianMath.angleOf(-89.6, 45), 90)
        XCTAssertEqual(UranianMath.angleOf(200, 45), 180)
        XCTAssertEqual(UranianMath.sdiff(359, 360), -1)
        XCTAssertEqual(AstroHit(method: .solarArc, mover: "SA", target: ["MC"], angle: 90, orb: 0.4).label, "D-SA □ R-MC 0°24′")
        XCTAssertEqual(UranianMath.formatDegrees(0.9999), "1°00′")
    }

    // MARK: Life events

    func testHughsExampleIsALifeEvent() {
        let g = LifeEvent.detect("Hey so I just launched a website", kindHint: nil, vocabulary: ["projects/website", "work", "entity/crow"])
        XCTAssertEqual(g, LifeEvent.Guess(title: "Launched a website", tags: ["projects/website"]))
    }

    func testOtherEventPhrasings() {
        XCTAssertEqual(LifeEvent.detect("Okay, we've just moved house. Boxes everywhere", kindHint: nil)?.title, "Moved house")
        XCTAssertEqual(LifeEvent.detect("I finally signed the lease!", kindHint: nil)?.title, "Signed the lease")
        XCTAssertEqual(LifeEvent.detect("Got the job offer today", kindHint: "event")?.title, "Got the job offer today")
        XCTAssertNil(LifeEvent.detect("Three card spread, the tower reversed", kindHint: nil))
        XCTAssertNil(LifeEvent.detect("Crow on the gate", kindHint: "omen"))
    }

    // MARK: Snapshots

    func testSnapshotWithNatalChart() async throws {
        let fake = FakeUranika()
        var a = astrologer(fake)
        let place = a.place(captured: nil, fallback: nil)
        XCTAssertEqual(place, AstroPlace(name: "Home", latitude: 37.77, longitude: -122.42))
        let capped = await a.snapshot(at: moment, place: place, now: moment.instant)
        XCTAssertEqual(capped.hits.filter { $0.method == .transit }.count, 20)
        XCTAssertEqual(capped.hits.filter { $0.method == .solarArc }.count, 20)
        a.settings.hits.maxHits = 1000
        fake.requests = []
        let snap = await a.snapshot(at: moment, place: place, now: moment.instant)

        XCTAssertEqual(snap.status, .computed)
        XCTAssertEqual(snap.points["SA"], 25.5)
        XCTAssertEqual(snap.points["KR"], 101.33)
        XCTAssertEqual(snap.points.count, 19)
        XCTAssertEqual(snap.asc, 128.4)
        XCTAssertEqual(snap.natal, NatalRef(uranikaChart: 1, name: "Hugh Tran"))
        XCTAssertEqual(snap.solarArc, 40)
        XCTAssertNil(snap.note)
        XCTAssertTrue(snap.hits.contains { $0.formula == "T-SA ☌ R-MC" && $0.orb == 0.4 })
        // Natal Jupiter 100 + arc 40 = 140 on natal Sun/Moon (10, 0).
        XCTAssertTrue(snap.hits.contains { $0.formula == "D-JU = R-SU/MO" && $0.orb == 0 })
        // The moment is sent in UTC; the natal chart is directed to the same instant.
        XCTAssertEqual(fake.requests.first, UranikaComputeRequest(date: "2026-10-29", time: "07:45:00", tz: "UTC", lat: 37.77, lon: -122.42, target: "2026-10-29T07:45:00", rate: "q2"))
        XCTAssertEqual(fake.requests.last?.target, "2026-10-29T07:45:00")
        XCTAssertEqual(fake.requests.last?.tz, "America/Los_Angeles")
    }

    func testSnapshotWithoutNatalOrPlaceSaysWhy() async {
        let snap = await astrologer(FakeUranika(), natal: nil).snapshot(at: moment, place: nil)
        XCTAssertEqual(snap.status, .computed)
        XCTAssertNil(snap.asc)
        XCTAssertTrue(snap.hits.isEmpty)
        XCTAssertEqual(snap.note, "No place set, so the Ascendant and Meridian were left out. No natal chart chosen, so no transits or solar arcs were measured")
    }

    func testClosedUranikaGivesPendingThenFills() async throws {
        let fake = FakeUranika()
        fake.open = false
        let a = astrologer(fake)
        let place = a.place(captured: nil, fallback: nil)
        let snap = await a.snapshot(at: moment, place: place)
        XCTAssertEqual(snap.status, .pending)
        XCTAssertEqual(snap.note, "Chart pending: Uranika was not open")
        XCTAssertEqual(snap.place, place)

        let entry = Entry(type: .event, title: "Launched a website", occurredAt: moment, astro: snap)
        let none = await a.fillPending([entry])
        XCTAssertTrue(none.isEmpty)
        fake.open = true
        let filledList = await a.fillPending([entry])
        let filled = try XCTUnwrap(filledList.first)
        XCTAssertEqual(filled.astro?.status, .computed)
        XCTAssertEqual(filled.astro?.place, place)
    }

    func testPhonePositionOnlyWhenAllowedOrNoHome() {
        var a = astrologer(FakeUranika())
        let phone = GeoLocation(latitude: 40.712776, longitude: -74.005974)
        XCTAssertEqual(a.place(captured: phone, fallback: nil)?.name, "Home")
        a.settings.useCapturedLocation = true
        XCTAssertEqual(a.place(captured: phone, fallback: nil), AstroPlace(latitude: 40.71, longitude: -74.01))
        a.settings.useCapturedLocation = false
        a.settings.home = nil
        XCTAssertEqual(a.place(captured: phone, fallback: nil), AstroPlace(latitude: 40.71, longitude: -74.01))
    }

    func testRecordEventInUranikaOnce() async throws {
        let fake = FakeUranika()
        var a = astrologer(fake)
        let e = Entry(type: .event, title: "Launched a website", occurredAt: moment)
        let off = try await a.recordEvent(e)
        XCTAssertNil(off, "off by default")
        a.settings.recordEventsInUranika = true
        let first = try await a.recordEvent(e)
        let sent = try XCTUnwrap(first)
        XCTAssertEqual(sent.astro?.uranikaEvent, 57)
        XCTAssertEqual(fake.events, [UranikaEvent(chartId: 1, date: "2026-10-29", category: "other", title: "Launched a website", notes: "From Grimoire \(e.id)")])
        let again = try await a.recordEvent(sent)
        XCTAssertNil(again, "never twice")
        let journal = try await a.recordEvent(Entry(type: .journal, occurredAt: moment))
        XCTAssertNil(journal)
    }

    // MARK: Uranika's own JSON

    func testDecodesComputeAnswerAndEventBody() throws {
        let json = #"""
        {"natal": {"points": {"SUN": {"lon": 216.1, "speed": 1.0}, "XYZ": {"lon": 1, "speed": 0}}, "hsys": {}, "asc": 128.4, "mc": 25.9,
                   "armc": 1, "eps": 23.4, "systems": {}, "utc": "2026-10-29 07:45"},
         "transit": {"points": {"SAT": {"lon": 25.5, "speed": 0.0}}, "utc": "2026-10-29 07:45"},
         "progressed": {"points": {}}, "arc": 40.1, "age": 36.8, "rate": "q2", "warning": null}
        """#
        let r = try JSONDecoder().decode(UranikaComputeResult.self, from: Data(json.utf8))
        XCTAssertEqual(UranikaAstrologer.points(r.natal.points), ["SU": 216.1])
        XCTAssertEqual(r.arc, 40.1)
        let body = String(decoding: try JSONEncoder().encode(UranikaEvent(chartId: 1, date: "2026-10-29", category: "career", title: "t", notes: "")), as: UTF8.self)
        XCTAssertTrue(body.contains(#""chart_id":1"#))
    }

    func testSettingsRoundTrip() throws {
        let url = TestSupport.tempDir().appendingPathComponent("uranika-settings.json")
        let s = UranikaSettings(natalChartId: 3, home: AstroPlace(name: "Studio", latitude: 1, longitude: 2), scope: .events)
        try s.save(to: url)
        XCTAssertEqual(try UranikaSettings.load(from: url), s)
    }

    // MARK: Ingest and export

    func testVoiceCaptureBecomesLifeEventWithChart() async throws {
        let root = TestSupport.tempDir()
        let repo = MemoryRepository()
        let ingestor = InboxIngestor(root: root, transcriber: SidecarTextTranscriber(), parser: TestSupport.parser)
        ingestor.defaultTimeZone = "America/Los_Angeles"
        ingestor.location = GeoLocation(latitude: 37.77, longitude: -122.42)
        ingestor.astrologer = astrologer(FakeUranika())
        ingestor.tagVocabulary = ["projects/website"]
        try FileManager.default.createDirectory(at: ingestor.incoming, withIntermediateDirectories: true)
        try Data(#"{"contract_version":1,"id":"20261029-004500-0001","captured_at":"2026-10-29T00:45:00-07:00","text":"Hey so I just launched a website","location":{"lat":37.774929,"lon":-122.419416}}"#.utf8)
            .write(to: ingestor.incoming.appendingPathComponent("20261029-004500-0001.json"))

        let out = await ingestor.scan(isKnown: repo.knowsCapture, deliver: repo.addToInbox)
        XCTAssertEqual(out, [.ingested(captureId: "20261029-004500-0001")])
        let item = try XCTUnwrap(repo.data.inbox.first)
        XCTAssertEqual(item.entry.type, .event)
        XCTAssertEqual(item.entry.title, "Launched a website")
        XCTAssertEqual(item.entry.tags, ["projects/website"])
        XCTAssertEqual(item.entry.astro?.status, .computed)
        XCTAssertEqual(item.entry.astro?.place?.name, "Home")
        XCTAssertNotNil(item.entry.timing)
        XCTAssertEqual(item.notes, ["Filed as a life event because it starts like one; change the type if not"])

        // Confirm keeps the chart; the export writes it into the frontmatter.
        let result = try repo.confirm(item.id, corrected: nil, library: TestSupport.library, now: moment.instant)
        XCTAssertEqual(result.entry.astro, item.entry.astro)
        var exporter = ObsidianExporter(library: TestSupport.library)
        let md = try XCTUnwrap(exporter.files(for: repo.data).first { $0.key.hasPrefix("Entries/2026/10/2026-10-29-event-") }?.value)
        XCTAssertTrue(md.contains("type: event"))
        XCTAssertTrue(md.contains("title: Launched a website"))
        XCTAssertTrue(md.contains("astro:\n  source: uranika\n  status: computed\n  place:\n    name: Home\n    lat: 37.77\n    lon: -122.42"))
        XCTAssertTrue(md.contains("    SA: 25.5\n"))
        XCTAssertTrue(md.contains("  natal:\n    uranika_chart: 1\n    name: Hugh Tran"))
        XCTAssertTrue(md.contains("  hits: [\"T-"))
        exporter.includeCoordinates = false
        let private_ = try XCTUnwrap(exporter.files(for: repo.data).first { $0.key.hasPrefix("Entries/2026/10/2026-10-29-event-") }?.value)
        XCTAssertFalse(private_.contains("lat: 37.77"))
        XCTAssertTrue(private_.contains("    name: Home"))
    }

    func testReadingsAreNotMistakenForEventsAndClosedUranikaIsNoted() async throws {
        let root = TestSupport.tempDir()
        let repo = MemoryRepository()
        let ingestor = InboxIngestor(root: root, transcriber: SidecarTextTranscriber(), parser: TestSupport.parser)
        let fake = FakeUranika()
        fake.open = false
        ingestor.astrologer = astrologer(fake)
        try FileManager.default.createDirectory(at: ingestor.incoming, withIntermediateDirectories: true)
        try Data(#"{"contract_version":1,"id":"c2","captured_at":"2026-10-29T08:00:00Z","kind_hint":"draw","text":"I just pulled the tower and three of cups"}"#.utf8)
            .write(to: ingestor.incoming.appendingPathComponent("c2.json"))
        _ = await ingestor.scan(isKnown: repo.knowsCapture, deliver: repo.addToInbox)
        let item = try XCTUnwrap(repo.data.inbox.first)
        XCTAssertEqual(item.entry.type, .divination)
        XCTAssertEqual(item.entry.astro?.status, .pending)
        XCTAssertEqual(item.notes, ["Chart pending: Uranika was not open"])
    }

    func testEntriesWithoutAstroStillDecode() throws {
        let e = Entry(type: .journal, occurredAt: moment)
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(e)) as! [String: Any]
        obj["astro"] = nil
        let back = try JSONDecoder().decode(Entry.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(back.astro)
    }
}
