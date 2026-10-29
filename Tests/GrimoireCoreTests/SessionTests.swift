import XCTest
@testable import GrimoireCore

final class SessionTests: XCTestCase {
    let vocab = TagVocabulary.standard
    let start = TestSupport.date("2026-10-29T21:30:00-07:00")

    // MARK: Vocabulary

    func testVocabularySuggestsWholeWordsAndPlurals() {
        XCTAssertEqual(vocab.suggest(in: "I see a red door in the desert, and two crows."),
                       ["color/red", "symbol/door", "place/desert", "entity/animal/crow"])
        // Multi-word phrases and aliases.
        XCTAssertEqual(vocab.suggest(in: "The inner library, a hooded figure"), ["place/inner-library", "entity/being/figure"])
        XCTAssertEqual(vocab.suggest(in: "angelic presence"), ["entity/being/angel", "entity/being/figure"])
        // "redder" and "doorstep" are not red or door; "well" is never suggested.
        XCTAssertEqual(vocab.suggest(in: "doorstep redder, well then"), [])
    }

    func testVocabularyCanonicalAndClassify() {
        XCTAssertEqual(vocab.canonical("crow"), "entity/animal/crow")
        XCTAssertEqual(vocab.canonical("Inner Library"), "place/inner-library")
        XCTAssertEqual(vocab.canonical("entity/animal/crow"), "entity/animal/crow")
        // "sun" names a planet and a symbol: left alone.
        XCTAssertEqual(vocab.canonical("sun"), "sun")
        XCTAssertEqual(vocab.canonical("my/own-tag"), "my/own-tag")

        let split = vocab.classify(["crow", "entity/animal", "my/own-tag", "color/red"])
        XCTAssertEqual(split.controlled, ["color/red", "entity/animal", "entity/animal/crow"])
        XCTAssertEqual(split.free, ["my/own-tag"])
        XCTAssertEqual(vocab.byFacet(["crow", "color/red", "my/own"])["entity"], ["entity/animal/crow"])
        XCTAssertTrue(vocab.facets.contains("sense"))
    }

    func testVocabularyRoundTripsAndMerges() throws {
        var user = TagVocabulary(terms: [.init(path: "entity/being/watcher", aliases: ["watchers"]), .init(path: "entity/animal/crow", aliases: ["corvid"])])
        user.add("place/library-of-stars")
        let merged = vocab.merging(user)
        XCTAssertTrue(merged.isControlled("entity/being/watcher"))
        XCTAssertEqual(merged.suggest(in: "the watchers and a corvid"), ["entity/being/watcher", "entity/animal/crow"])
        XCTAssertEqual(merged.canonical("library-of-stars"), "place/library-of-stars")

        let url = TestSupport.tempDir().appendingPathComponent("tag-vocabulary.json")
        try merged.json().write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try TagVocabulary.load(from: url), merged)
        XCTAssertTrue(TagVocabulary.standard(withUserFile: url).isControlled("entity/being/watcher"))
        XCTAssertEqual(TagVocabulary.standard(withUserFile: url.appendingPathExtension("missing")), vocab)
    }

    // MARK: Transcript and extraction

    func testTimedTranscriptParsesStamps() {
        let segs = TimedTranscript.parse("""
        [00:05] Phase opening.
        [05:12] I see a red door
        in the desert.
        [1:02:03.5] Closing now.
        """)
        XCTAssertEqual(segs, [
            TranscriptSegment(offset: 5, text: "Phase opening."),
            TranscriptSegment(offset: 312, text: "I see a red door in the desert."),
            TranscriptSegment(offset: 3723.5, text: "Closing now."),
        ])
        XCTAssertEqual(TimedTranscript.parse("No times here."), [TranscriptSegment(offset: 0, text: "No times here.")])
        XCTAssertEqual(TimedTranscript.format(segs).split(separator: "\n").last, "[1:02:03] Closing now.")
    }

    func testExtractorMakesObservationsAndPhases() {
        let segs = [
            TranscriptSegment(offset: 5, text: "Phase working."),
            TranscriptSegment(offset: 60, text: "I see a red door in the desert. A robed figure stands at the gate."),
            TranscriptSegment(offset: 90, text: "He says the key is in the well."),
            TranscriptSegment(offset: 120, text: "I feel heat in my hands. Mark."),
            TranscriptSegment(offset: 150, text: "I feel afraid. I hear a bell. I realise this is about patience."),
            TranscriptSegment(offset: 200, text: "Ok."),
            TranscriptSegment(offset: 300, text: "Closing now."),
        ]
        let r = ObservationExtractor().extract(segs, recordingOffset: 10)
        XCTAssertEqual(r.phases, [PhaseMark(.working, at: 15), PhaseMark(.closing, at: 310)])
        XCTAssertEqual(r.observations.map(\.kind), [.imagery, .entity, .message, .sensation, .note, .emotion, .sound, .insight])
        XCTAssertTrue(r.observations.allSatisfy { !$0.reviewed })
        XCTAssertEqual(r.observations[0].offset, 70)
        XCTAssertEqual(r.observations[0].tags, ["color/red", "symbol/door", "place/desert"])
        XCTAssertEqual(r.observations[1].tags, ["entity/being/figure", "place/gate"])
        // The second sentence of a segment is placed after the first, at speaking pace.
        XCTAssertEqual(r.observations[1].offset, 70 + 8 / 2.5, accuracy: 0.001)
        XCTAssertEqual(r.observations[4].capture, .marker)
        XCTAssertEqual(r.observations[3].tags, ["sense/heat"])
    }

    // MARK: Recorder

    func testRecorderClockPhasesAndRecall() throws {
        var rec = SessionRecorder(type: .vision, startedAt: start, intention: "Visit the inner library", technique: "inner flame",
                                  tags: ["practice/quareia"], before: StateCheck(energy: 3, calm: 2, focus: 3))
        let t0 = start.instant
        rec.setPhase(.working, at: t0 + 120)
        rec.setPhase(.working, at: t0 + 130)  // already there: ignored
        let m = rec.mark(at: t0 + 300)
        rec.observe(.entity, "Robed figure at the door", tags: ["entity/being/guardian"], intensity: 4, at: t0 + 640)
        rec.setPhase(.closing, at: t0 + 1800)
        rec.finish(at: t0 + 2140, after: StateCheck(energy: 4, calm: 4, focus: 4), outcome: "Came back calm.")
        let late = rec.observe(.insight, "The door was the same as last week's", at: t0 + 4000)

        let s = rec.session
        XCTAssertEqual(s.phases.map(\.phase), [.opening, .working, .closing])
        XCTAssertEqual(s.duration, 2140)
        XCTAssertEqual(s.phaseDurations[.working], 1680)
        XCTAssertEqual(s.phaseDurations[.closing], 340)
        XCTAssertEqual(s.observations.map(\.phase), [.working, .working, .aftermath])
        XCTAssertEqual(s.observations.first?.id, m.id)
        XCTAssertEqual(late.capture, .recalled)
        XCTAssertEqual(late.offset, 2140)
        XCTAssertEqual(s.time(of: s.observations[1]).iso8601, "2026-10-29T21:40:40-07:00")
        XCTAssertTrue(s.problems.isEmpty)
    }

    func testSessionInboxItemAndConfirm() throws {
        var rec = SessionRecorder(type: .vision, startedAt: start, intention: "Visit the inner library")
        rec.observe(.entity, "Guardian at the door", tags: ["entity/being/guardian"], at: start.instant + 640)
        rec.finish(at: start.instant + 1800, outcome: "Came back calm.")
        let recording = SessionRecording(path: "audio/session.m4a", duration: 1800, segments: [
            TranscriptSegment(offset: 300, text: "I see a red door in the desert."),
        ])
        let item = rec.inboxItem(recording: recording, extractor: ObservationExtractor(), timing: TimingContext.compute(at: start, location: nil))
        XCTAssertEqual(item.entry.status, .inbox)
        XCTAssertEqual(item.entry.type, .vision)
        XCTAssertEqual(item.entry.displayTitle, "Vision: Visit the inner library")
        XCTAssertEqual(item.entry.fields.durationMin, 30)
        XCTAssertEqual(item.entry.attachments.map(\.path), ["audio/session.m4a"])
        XCTAssertEqual(item.entry.transcript, "[05:00] I see a red door in the desert.")
        XCTAssertEqual(item.entry.session?.observations.map(\.capture), [.spoken, .live])
        XCTAssertEqual(item.notes?.first, "1 observation was made from speech: check kinds, text and tags")

        let repo = MemoryRepository()
        repo.addToInbox(item)
        let result = try repo.confirm(item.id, corrected: nil, library: TestSupport.library)
        XCTAssertNil(result.inquiry)
        XCTAssertEqual(result.entry.status, .filed)
        XCTAssertEqual(result.entry.session?.unreviewedCount, 0)
        XCTAssertTrue(repo.data.inbox.isEmpty)

        // Observation text and tags are searchable.
        XCTAssertEqual(repo.search(SearchQuery(text: "red door")), [.entry(item.id)])
        XCTAssertEqual(repo.search(SearchQuery(tags: ["entity/being"])), [.entry(item.id)])
        XCTAssertTrue(repo.tagTree.all.contains("color/red"))
    }

    func testRetranscribeKeepsTypedObservations() {
        var rec = SessionRecorder(type: .meditation, startedAt: start)
        rec.observe(.sensation, "Pressure at the brow", at: start.instant + 60)
        rec.finish(at: start.instant + 600)
        let first = rec.inboxItem(recording: SessionRecording(path: "audio/a.m4a"), extractor: ObservationExtractor(), timing: nil)
        XCTAssertEqual(first.notes, ["No transcript yet: use Transcribe Again once the speech model is installed"])
        let again = SessionAssembler.retranscribed(first, segments: [TranscriptSegment(offset: 100, text: "I see a white owl. Now closing.")],
                                                   extractor: ObservationExtractor())
        XCTAssertEqual(again.entry.session?.observations.map(\.kind), [.sensation, .entity])
        XCTAssertEqual(again.entry.session?.phases.map(\.phase), [.opening, .closing])
        XCTAssertEqual(again.notes, ["1 observation was made from speech: check kinds, text and tags"])
        // Doing it twice replaces, not duplicates.
        let twice = SessionAssembler.retranscribed(again, segments: [TranscriptSegment(offset: 100, text: "I see a white owl. Now closing.")],
                                                   extractor: ObservationExtractor())
        XCTAssertEqual(twice.entry.session?.observations.count, 2)
        XCTAssertEqual(twice.entry.session?.phases.count, 2)
    }

    func testOldEntriesDecodeWithoutSession() throws {
        let json = #"{"id":"01JBXA0000000000000000E001","type":"omen","occurredAt":{"instant":0,"timeZone":"UTC"},"createdAt":0,"updatedAt":0,"body":"","tags":[],"links":[],"attachments":[],"mode":"quick","status":"filed","fields":{}}"#
        let e = try JSONDecoder().decode(Entry.self, from: Data(json.utf8))
        XCTAssertNil(e.session)
        let back = String(decoding: try JSONEncoder().encode(e), as: UTF8.self)
        XCTAssertFalse(back.contains("session"))
    }

    // MARK: Phone sidecar

    func testPhoneSessionSidecarIngests() async throws {
        let root = TestSupport.tempDir()
        let incoming = root.appendingPathComponent("incoming")
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        let sidecar = """
        {"contract_version":1,"id":"20261029-213000-4821","captured_at":"2026-10-29T21:30:00-07:00","device":"Pixel","kind_hint":"vision",
         "audio":"20261029-213000-4821.wav","tags":["practice/quareia"],
         "session":{"type":"vision","started_at":"2026-10-29T21:30:00-07:00","ended_at":"2026-10-29T22:05:40-07:00","intention":"Visit the inner library",
           "marks":[{"offset_s":0,"phase":"opening"},{"offset_s":312.5},{"offset_s":640,"kind":"entity","text":"Robed figure at the door","tags":["guardian"]},{"offset_s":1800,"phase":"closing"}],
           "segments":[{"offset":305,"text":"I see a red door in the desert"}],
           "before":{"energy":3,"calm":2,"focus":3},"after":{"energy":4,"calm":4,"focus":4}}}
        """
        try Data("RIFF".utf8).write(to: incoming.appendingPathComponent("20261029-213000-4821.wav"))
        try Data(sidecar.utf8).write(to: incoming.appendingPathComponent("20261029-213000-4821.json"))
        let ingestor = InboxIngestor(root: root, transcriber: SidecarTextTranscriber(), parser: TestSupport.parser)
        ingestor.stableSeconds = 0
        ingestor.defaultTimeZone = "America/Los_Angeles"
        ingestor.attachmentsFolder = root.appendingPathComponent("attachments")
        var items: [InboxItem] = []
        let outcomes = await ingestor.scan(isKnown: { _ in false }, deliver: { items.append($0) })
        XCTAssertEqual(outcomes, [.ingested(captureId: "20261029-213000-4821")])
        let item = try XCTUnwrap(items.first)
        XCTAssertNil(item.draft)
        XCTAssertEqual(item.entry.type, .vision)
        XCTAssertEqual(item.entry.occurredAt.timeZone, "America/Los_Angeles")
        let s = try XCTUnwrap(item.entry.session)
        XCTAssertEqual(s.duration, 2140)
        XCTAssertEqual(s.phases.map(\.phase), [.opening, .closing])
        XCTAssertEqual(s.observations.map(\.kind), [.imagery, .note, .entity])
        XCTAssertEqual(s.observations.map(\.capture), [.spoken, .marker, .live])
        XCTAssertEqual(s.observations[2].tags, ["entity/being/guardian"])
        XCTAssertEqual(s.before?.calm, 2)
        XCTAssertEqual(s.recordings.first?.path, "audio/20261029-213000-4821.wav")
        XCTAssertEqual(item.source, "phone:Pixel")
    }

    func testSidecarRejectsBadSessionType() {
        let bad = #"{"contract_version":1,"id":"x","captured_at":"2026-10-29T21:30:00-07:00","session":{"type":"omen"}}"#
        XCTAssertThrowsError(try CaptureSidecar.decode(Data(bad.utf8)))
    }

    // MARK: Export

    func sampleData() throws -> GrimoireData {
        var rec = SessionRecorder(type: .vision, startedAt: start, intention: "Visit the inner library", tags: ["practice/quareia"],
                                  before: StateCheck(energy: 3, calm: 2, focus: 3))
        rec.setPhase(.working, at: start.instant + 120)
        rec.observe(.imagery, "A red door, \"half open\"", tags: ["color/red", "symbol/door", "my/free-tag"], intensity: 4, at: start.instant + 300)
        rec.observe(.entity, "Guardian", tags: ["entity/being/guardian"], at: start.instant + 640)
        rec.finish(at: start.instant + 1800, after: StateCheck(energy: 4, calm: 4, focus: 4), outcome: "Came back calm.")
        var item = rec.inboxItem(recording: nil, extractor: ObservationExtractor(), timing: TimingContext.compute(at: start, location: GeoLocation(latitude: 37.77, longitude: -122.42)))
        item.entry.id = ULID("01JBXA0000000000000000S001")!
        let ids = ["01JBXA00000000000000000B01", "01JBXA00000000000000000B02"]
        for i in item.entry.session!.observations.indices { item.entry.session!.observations[i].id = ULID(ids[i])! }
        let repo = MemoryRepository()
        repo.addToInbox(item)
        try repo.confirm(item.id, corrected: nil, library: TestSupport.library)
        return repo.data
    }

    func testObservationTables() throws {
        let files = try SessionExporter().files(for: try sampleData())
        let jsonl = try XCTUnwrap(files["ML/observations.jsonl"]).split(separator: "\n")
        XCTAssertEqual(jsonl.count, 2)
        let row = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(jsonl[0].utf8)) as? [String: Any])
        XCTAssertEqual(row["observation_id"] as? String, "01JBXA00000000000000000B01")
        XCTAssertEqual(row["session_id"] as? String, "01JBXA0000000000000000S001")
        XCTAssertEqual(row["observed_at"] as? String, "2026-10-29T21:35:00-07:00")
        XCTAssertEqual(row["minute"] as? Int, 5)
        XCTAssertEqual(row["phase"] as? String, "working")
        XCTAssertEqual(row["kind"] as? String, "imagery")
        XCTAssertEqual(row["reviewed"] as? Bool, true)
        XCTAssertEqual(row["tags_free"] as? [String], ["my/free-tag"])
        XCTAssertEqual(row["color"] as? [String], ["color/red"])
        XCTAssertEqual(row["entity"] as? [String], [])
        XCTAssertNotNil(row["moon_phase"] as? String)
        XCTAssertTrue(row.keys.contains("linked_entry_id"))
        XCTAssertEqual(Set(row.keys), Set(SessionExporter.observationColumns))

        let csv = try XCTUnwrap(files["ML/observations.csv"]).components(separatedBy: "\r\n")
        XCTAssertEqual(csv[0], SessionExporter.observationColumns.joined(separator: ","))
        XCTAssertTrue(csv[1].contains(",\"A red door, \"\"half open\"\"\","), csv[1])
        XCTAssertTrue(csv[1].contains(",color/red;my/free-tag;symbol/door,"), csv[1])
        XCTAssertEqual(csv.count, 4) // header, 2 rows, trailing empty

        let session = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(files["ML/sessions.jsonl"]).utf8)) as? [String: Any])
        XCTAssertEqual(session["duration_s"] as? Double, 1800)
        XCTAssertEqual(session["opening_s"] as? Double, 120)
        XCTAssertEqual(session["working_s"] as? Double, 1680)
        XCTAssertEqual(session["n_imagery"] as? Int, 1)
        XCTAssertEqual(session["before_calm"] as? Int, 2)
        XCTAssertEqual(session["weekday"] as? String, "thursday")
        XCTAssertEqual(session["local_hour"] as? Int, 21)
        XCTAssertEqual(session["observed_tags_free"] as? [String], ["my/free-tag"])
        XCTAssertEqual(Set(session.keys), Set(SessionExporter.sessionColumns))
        XCTAssertTrue(try XCTUnwrap(files["ML/tag-vocabulary.json"]).contains("\"entity/animal/crow\""))
    }

    func testMLManifestAndObsidianSessionLog() throws {
        let data = try sampleData()
        let ml = try MLExporter(library: TestSupport.library).files(for: data)
        XCTAssertNotNil(ml["ML/observations.csv"])
        XCTAssertTrue(try XCTUnwrap(ml["ML/manifest.json"]).contains("\"path\" : \"ML/observations.jsonl\",\n      \"rows\" : 2"))
        // Re-exporting unchanged data is byte-stable.
        XCTAssertEqual(ml, try MLExporter(library: TestSupport.library).files(for: data))

        let md = try XCTUnwrap(ObsidianExporter(library: TestSupport.library).files(for: data)["Entries/2026/10/2026-10-29-vision-01JBXA0000000000000000S001.md"])
        XCTAssertTrue(md.contains("session:\n  started_at: \"2026-10-29T21:30:00-07:00\"\n"), md)
        XCTAssertTrue(md.contains("  duration_min: 30\n"))
        XCTAssertTrue(md.contains("  observations: 2\n"))
        XCTAssertTrue(md.contains("## Session log\n\n| Time | Phase | Kind | Observation | Tags |\n|---|---|---|---|---|\n"))
        XCTAssertTrue(md.contains("| 05:00 | working | imagery | A red door, \"half open\" · intensity 4 | #color/red #symbol/door #my/free-tag |"), md)
    }
}
