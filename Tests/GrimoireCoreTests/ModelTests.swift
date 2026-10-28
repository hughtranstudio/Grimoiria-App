import XCTest
@testable import GrimoireCore

final class ModelTests: XCTestCase {
    func testULID() throws {
        let d = Date(timeIntervalSince1970: 1_761_640_440.123)
        let a = ULID(date: d)
        XCTAssertEqual(a.string.count, 26)
        XCTAssertEqual(a.date.timeIntervalSince1970, 1_761_640_440.123, accuracy: 0.001)
        XCTAssertLessThan(ULID(date: d), ULID(date: d.addingTimeInterval(1)))
        XCTAssertNil(ULID("not-a-ulid"))
        XCTAssertNil(ULID("01JBXA0000000000000000OOOO")) // O is not Crockford
        let json = try JSONEncoder().encode([a])
        XCTAssertEqual(try JSONDecoder().decode([ULID].self, from: json), [a])
    }

    func testZonedDate() throws {
        let z = try XCTUnwrap(ZonedDate.parse("2026-10-28T08:14:00-07:00", timeZone: "America/Los_Angeles"))
        XCTAssertEqual(z.iso8601, "2026-10-28T08:14:00-07:00")
        XCTAssertEqual(z.day, "2026-10-28")
        let offsetOnly = try XCTUnwrap(ZonedDate.parse("2026-10-28T23:30:00+10:00"))
        XCTAssertEqual(offsetOnly.day, "2026-10-28")
        XCTAssertEqual(offsetOnly.iso8601, "2026-10-28T23:30:00+10:00")
    }

    func testTags() {
        let t: TagPath = "Entity/Ally/Grey Crow"
        XCTAssertEqual(t.path, "entity/ally/grey-crow")
        XCTAssertTrue(t.isUnder("entity"))
        XCTAssertTrue(t.isUnder("entity/ally"))
        XCTAssertFalse(t.isUnder("entity/al"))
        let tree = TagTree([t, "theme/work", "question/health"])
        XCTAssertEqual(tree.children(of: nil).map(\.path), ["entity", "question", "theme"])
        XCTAssertEqual(tree.children(of: "entity").map(\.path), ["entity/ally"])
        XCTAssertEqual(tree.suggestions(for: "ally").first?.path, "entity/ally")
    }

    func testPhysicalPages() {
        let v = ULID()
        XCTAssertEqual(PhysicalRef(volumeId: v, page: "12v").pageRange, 12...12)
        XCTAssertEqual(PhysicalRef(volumeId: v, page: "43–45").pageRange, 43...45)
        XCTAssertEqual(PhysicalRef(volumeId: v, page: "45-43").pageRange, 43...45)
        XCTAssertTrue(PhysicalRef(volumeId: v, page: "38-41").overlaps(40...50))
        XCTAssertFalse(PhysicalRef(volumeId: v, page: "51").overlaps(40...50))
        XCTAssertNil(PhysicalRef(volumeId: v, page: "flyleaf").pageRange)
    }

    /// Spec §14: find every entry referencing Volume III, page 40–50.
    func testSearchByVolumeAndPages() {
        let repo = MemoryRepository()
        let v3 = Volume(name: "Volume III"), v2 = Volume(name: "Volume II")
        repo.save(v3); repo.save(v2)
        let when = ZonedDate(Date(timeIntervalSince1970: 1_761_640_440), timeZone: "UTC")
        func add(_ body: String, _ vol: Volume?, _ page: String?) -> Entry {
            let e = Entry(type: .journal, occurredAt: when, body: body, physicalRef: vol.map { PhysicalRef(volumeId: $0.id, page: page!) })
            repo.save(e); return e
        }
        let a = add("in range", v3, "42")
        let b = add("spans into range", v3, "38–41")
        _ = add("after range", v3, "51")
        _ = add("other volume", v2, "45")
        _ = add("no ref", nil, nil)
        let hits = repo.search(SearchQuery(volumeId: v3.id, pages: 40...50)).map(\.id)
        XCTAssertEqual(Set(hits), [a.id, b.id])
    }

    func testSearchTextAndHierarchicalTags() {
        let repo = MemoryRepository()
        let when = ZonedDate(Date(timeIntervalSince1970: 1_761_640_440), timeZone: "UTC")
        let crow = Entry(type: .omen, occurredAt: when, body: "Crow on the gate", tags: ["entity/bird/crow"])
        let dream = Entry(type: .dream, occurredAt: when, body: "Gate of horn", tags: ["place/inner/gate"])
        repo.save(crow); repo.save(dream)
        XCTAssertEqual(repo.search(SearchQuery(text: "GATE")).count, 2)
        XCTAssertEqual(repo.search(SearchQuery(tags: ["entity/bird"])).map(\.id), [crow.id])
        XCTAssertEqual(repo.search(SearchQuery(text: "gate", types: [.dream])).map(\.id), [dream.id])
    }

    func testSearchFindsCardNamesInInquiries() {
        let repo = MemoryRepository()
        let when = ZonedDate(Date(timeIntervalSince1970: 1_761_640_440), timeZone: "UTC")
        let inq = Inquiry(question: "Work?", askedAt: when, divinations: [
            Divination(system: .cards, deckId: "rws-tarot", spreadId: "single", performedAt: when, draws: [Draw(cardId: "maj-16", positionKey: "card")])
        ])
        repo.save(inq)
        XCTAssertEqual(repo.search(SearchQuery(text: "tower"), library: TestSupport.library).map(\.id), [inq.id])
    }

    func testRemindersAndNeedsOutcome() {
        XCTAssertEqual(ReminderPreset.oneWeek.dueOn(from: "2026-10-28"), "2026-11-04")
        XCTAssertEqual(ReminderPreset.oneMonth.dueOn(from: "2026-01-31"), "2026-02-28")
        XCTAssertEqual(ReminderPreset.threeMonths.dueOn(from: "2026-10-28"), "2027-01-28")
        XCTAssertNil(ReminderPreset.none.dueOn(from: "2026-10-28"))

        let repo = MemoryRepository()
        let target = ULID()
        var r = Reminder(targetId: target, dueOn: "2026-11-04", repeat: .monthly)
        repo.save(r)
        XCTAssertTrue(repo.needsOutcome(today: "2026-11-03").isEmpty)
        XCTAssertEqual(repo.needsOutcome(today: "2026-11-04").count, 1)
        r.snooze(days: 3)
        XCTAssertEqual(r.dueOn, "2026-11-07")
        XCTAssertEqual(r.status, .snoozed)
        r.complete()
        XCTAssertEqual(r.dueOn, "2026-12-07")
        XCTAssertEqual(r.status, .pending)
        var once = Reminder(targetId: target, dueOn: "2026-11-04")
        once.complete()
        XCTAssertEqual(once.status, .done)
        XCTAssertFalse(once.isDue(today: "2027-01-01"))
    }

    func testOutcomesStackAndStatusMoves() {
        let asked = ZonedDate(Date(timeIntervalSince1970: 1_761_640_440), timeZone: "UTC")
        var inq = Inquiry(question: "Q", askedAt: asked)
        inq.addOutcome(Outcome(recordedAt: ZonedDate(asked.instant.addingTimeInterval(30 * 86_400), timeZone: "UTC"), body: "later", fulfilled: .partly))
        inq.addOutcome(Outcome(recordedAt: ZonedDate(asked.instant.addingTimeInterval(7 * 86_400), timeZone: "UTC"), body: "earlier, backfilled", fulfilled: .yes))
        XCTAssertEqual(inq.outcomes.map(\.body), ["earlier, backfilled", "later"])
        XCTAssertEqual(inq.outcomes.map(inq.daysAfter), [7, 30])
        XCTAssertEqual(inq.status, .revisited)
    }

    func testBacklinksAndTitles() {
        let repo = MemoryRepository()
        let when = ZonedDate(Date(timeIntervalSince1970: 1_761_640_440), timeZone: "UTC")
        let a = Entry(type: .insight, occurredAt: when, body: "# First line here\nmore")
        let b = Entry(type: .insight, occurredAt: when, body: "x", links: [Link(.respondsTo, to: a.id)])
        repo.save(a); repo.save(b)
        XCTAssertEqual(a.displayTitle, "First line here")
        XCTAssertEqual(repo.backlinks(to: a.id).map(\.source), [b.id])
        XCTAssertEqual(Link(.vaultNote, to: "Notes/Crows.md").obsidianURL?.absoluteString, "obsidian://open?file=Notes/Crows.md")
    }

    func testTypeFieldValidation() {
        var f = TypeFields()
        f.depth = 7
        f.nature = "friendly"
        f.being = "place/x"
        XCTAssertEqual(f.problems(for: .contact).count, 3)
    }

    func testJSONStoreRoundTrip() throws {
        let url = TestSupport.tempDir().appendingPathComponent("store.json")
        let repo = try JSONFileRepository(url: url)
        repo.save(Entry(type: .journal, occurredAt: ZonedDate(Date(timeIntervalSince1970: 1_761_640_440), timeZone: "Europe/London"),
                       createdAt: Date(timeIntervalSince1970: 1_761_640_441.25), body: "hello", tags: ["a/b"]))
        try repo.flush()
        let again = try JSONFileRepository(url: url)
        XCTAssertEqual(again.data, repo.data)
    }
}
