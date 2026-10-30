import XCTest
@testable import GrimoireCore

final class BookTests: XCTestCase {
    let lib = TestSupport.library

    /// A month of practice: rituals, a meditation, a dream, an omen, a tarot reading and a Yi Jing reading.
    func sampleMonth() throws -> GrimoireData {
        let repo = MemoryRepository()
        let vol = Volume(id: ULID("01JBXA0000000000000000VA13")!, name: "Volume III")
        repo.save(vol)
        func at(_ iso: String) -> ZonedDate { TestSupport.date(iso) }
        func entry(_ id: String, _ type: EntryType, _ iso: String, title: String?, body: String, tags: [TagPath] = []) -> Entry {
            let z = at(iso)
            return Entry(id: ULID(id)!, type: type, title: title, occurredAt: z, createdAt: z.instant, body: body, tags: tags,
                         timing: TimingContext.compute(at: z, location: GeoLocation(latitude: 37.77, longitude: -122.42)))
        }

        var ritual = entry("01JBXA0000000000000000E001", .ritual, "2026-10-02T21:10:00-07:00", title: "Lesser banishing at the new altar",
                           body: "Cleared the room first.\nThe east felt bright, the north heavy.\n\nAfterwards the room was quiet for a long time.",
                           tags: ["practice/banishing", "place/altar"])
        ritual.fields.intention = "Consecrate the new altar space"
        ritual.fields.tools = ["dagger", "salt", "water"]
        ritual.fields.durationMin = 25
        ritual.physicalRef = PhysicalRef(volumeId: vol.id, page: "12")
        repo.save(ritual)

        var meditation = entry("01JBXA0000000000000000E002", .meditation, "2026-10-08T06:30:00-07:00", title: "Stillness, inner temple",
                               body: "Walked the corridor to the threshold. Did not go in.", tags: ["practice/inner-temple"])
        meditation.fields.technique = "inner vision"
        meditation.fields.depth = 3
        repo.save(meditation)

        repo.save(entry("01JBXA0000000000000000E003", .dream, "2026-10-15T05:50:00-07:00", title: nil,
                        body: "A river running uphill, and a woman with a lamp asking for my name.", tags: ["entity/lamp-bearer"]))

        var omen = entry("01JBXA0000000000000000E004", .omen, "2026-10-28T08:14:00-07:00", title: "Crow on the gate",
                         body: "A crow waited on the gate until I opened the door.", tags: ["entity/crow"])
        omen.fields.observedIn = "nature"
        repo.save(omen)
        repo.save(entry("01JBXA0000000000000000E005", .journal, "2026-11-02T20:00:00-08:00", title: "Outside the month", body: "Should not print."))

        let asked = at("2026-10-20T19:00:00-07:00")
        var inq = Inquiry(id: ULID("01JBXA0000000000000000Q001")!, question: "Will the move go ahead?", askedAt: asked,
                          context: "Asked after the landlord's letter.", tags: ["question/home"], createdAt: asked.instant)
        inq.divinations = [
            Divination(id: ULID("01JBXA0000000000000000D001")!, system: .cards, deckId: "rws-tarot", spreadId: "three-card", performedAt: asked, order: 0, draws: [
                Draw(id: ULID("01JBXA0000000000000000W001")!, cardId: "cups-03", positionKey: "past", orientation: .reversed),
                Draw(id: ULID("01JBXA0000000000000000W002")!, cardId: "maj-16", positionKey: "present", notes: "sudden"),
                Draw(id: ULID("01JBXA0000000000000000W003")!, cardId: "wands-11", positionKey: "future"),
            ]),
            Divination(id: ULID("01JBXA0000000000000000D002")!, system: .yijing, performedAt: asked, method: "coins", order: 1, cast: try YiJingCast(quick: "789677")),
        ]
        inq.synthesis = Synthesis(body: "Disruption, then news.", writtenAt: asked, confidence: 3)
        inq.addOutcome(Outcome(id: ULID("01JBXA0000000000000000T001")!, recordedAt: at("2026-10-27T10:00:00-07:00"), body: "The offer came.", fulfilled: .yes))
        inq.timing = TimingContext.compute(at: asked, location: nil)
        repo.save(inq)
        // The confirmed capture behind the reading: printed once, as the reading.
        var capture = entry("01JBXA0000000000000000E006", .divination, "2026-10-20T19:00:00-07:00", title: nil, body: "Asked after the landlord's letter.")
        capture.inquiryId = inq.id
        repo.save(capture)
        return repo.data
    }

    var october: BookSpec { BookSpec(title: "October Workings", from: "2026-10-01", to: "2026-10-31") }

    func testSelectsByDateAndPrintsReadingsOnce() throws {
        let book = BookExporter(library: lib).book(try sampleMonth(), spec: october, generatedOn: "2026-10-31")
        let ids = book.chapters.flatMap(\.items).map(\.id)
        XCTAssertEqual(ids, ["01JBXA0000000000000000E001", "01JBXA0000000000000000E002", "01JBXA0000000000000000E003",
                             "01JBXA0000000000000000Q001", "01JBXA0000000000000000E004"])
        XCTAssertEqual(book.counts.entries, 4)
        XCTAssertEqual(book.counts.readings, 1)
        XCTAssertEqual(book.period, "1 October 2026 – 31 October 2026")
        XCTAssertEqual(book.chapters.map(\.title), ["October 2026"])
    }

    func testResolvesNamesForTemplates() throws {
        let book = BookExporter(library: lib).book(try sampleMonth(), spec: october, generatedOn: "2026-10-31")
        let items = book.chapters.flatMap(\.items)
        let ritual = try XCTUnwrap(items.first { $0.type == "ritual" })
        XCTAssertEqual(ritual.dateLabel, "Friday 2 October 2026")
        XCTAssertEqual(ritual.time, "21:10")
        XCTAssertEqual(ritual.physical, "Volume III, p. 12")
        XCTAssertEqual(ritual.fields.map(\.label), ["Intention", "Tools", "Duration"])
        XCTAssertEqual(ritual.fields[1].value, "dagger, salt, water")
        XCTAssertNotNil(ritual.timing?.planetaryDay)

        let reading = try XCTUnwrap(items.first { $0.kind == .reading })
        XCTAssertEqual(reading.typeLabel, "Reading")
        let cards = reading.divinations[0]
        XCTAssertEqual(cards.spread, "Three card")
        XCTAssertEqual(cards.draws.map(\.position), ["Past", "Present", "Future"])
        XCTAssertEqual(cards.draws[0].card, "Three of Cups")
        XCTAssertTrue(cards.draws[0].reversed)
        XCTAssertEqual(cards.draws[1].card, "The Tower")
        let cast = try XCTUnwrap(reading.divinations[1].cast)
        XCTAssertEqual(cast.lines, [7, 8, 9, 6, 7, 7])
        XCTAssertEqual(cast.changing, [3, 4])
        XCTAssertEqual(cast.primary.number, try YiJingCast(quick: "789677").primaryHexagram(in: lib.yijing))
        XCTAssertNotNil(cast.resulting)
        XCTAssertEqual(reading.outcomes.first?.daysAfter, 6)
    }

    func testGroupings() throws {
        let data = try sampleMonth()
        var spec = october
        spec.grouping = .type
        XCTAssertEqual(BookExporter(library: lib).book(data, spec: spec, generatedOn: "x").chapters.map(\.title),
                       ["Rituals", "Meditations", "Omens", "Dreams", "Readings"])
        spec.grouping = .week
        XCTAssertEqual(BookExporter(library: lib).book(data, spec: spec, generatedOn: "x").chapters.map(\.title),
                       ["Week of 28 September 2026", "Week of 5 October 2026", "Week of 12 October 2026", "Week of 19 October 2026", "Week of 26 October 2026"])
        spec.grouping = .tag
        spec.tags = ["entity", "practice"]
        let byTag = BookExporter(library: lib).book(data, spec: spec, generatedOn: "x")
        XCTAssertEqual(byTag.chapters.map(\.title), ["entity", "practice"])
        XCTAssertEqual(byTag.chapters[0].items.map(\.type), ["dream", "omen"])
    }

    func testCardSelectionAndIndexes() throws {
        var spec = BookSpec(title: "The Tower", cards: ["maj-16"], grouping: .card)
        let book = BookExporter(library: lib).book(try sampleMonth(), spec: spec, generatedOn: "x")
        XCTAssertEqual(book.chapters.map(\.title), ["The Tower"])
        XCTAssertEqual(book.counts, .init(entries: 0, readings: 1))
        XCTAssertEqual(book.cardIndex.map(\.label), ["The Tower", "Three of Cups", "Page of Wands"].sorted())
        XCTAssertEqual(book.cardIndex.first?.group, "Rider–Waite–Smith Tarot")
        XCTAssertEqual(book.hexagramIndex.count, 2)
        spec.cards = ["death-not-drawn"]
        XCTAssertTrue(BookExporter(library: lib).book(try sampleMonth(), spec: spec, generatedOn: "x").chapters.isEmpty)
    }

    func testDeterministicJSON() throws {
        let data = try sampleMonth()
        let a = try BookExporter(library: lib).book(data, spec: october, generatedOn: "2026-10-31").json()
        let b = try BookExporter(library: lib).book(data, spec: october, generatedOn: "2026-10-31").json()
        XCTAssertEqual(a, b)
        let round = try JSONDecoder().decode(BookDocument.self, from: a)
        XCTAssertEqual(round.formatVersion, BookDocument.formatVersion)
    }

    func testImagesOnlyWhenTheFileExists() throws {
        var data = try sampleMonth()
        let i = data.entries.firstIndex { $0.id.string == "01JBXA0000000000000000E001" }!
        data.entries[i].physicalRef?.photo = Attachment(kind: .image, path: "2026/vol3-p12.jpg")
        data.entries[i].attachments = [Attachment(kind: .image, path: "missing.png"), Attachment(kind: .audio, path: "a.m4a")]
        let book = BookExporter(library: lib).book(data, spec: october, generatedOn: "x", attachmentExists: { $0 != "missing.png" })
        XCTAssertEqual(book.chapters[0].items[0].images, ["images/2026-vol3-p12.jpg"])
        XCTAssertEqual(book.images, ["images/2026-vol3-p12.jpg": "2026/vol3-p12.jpg"])
    }

    func testBundledDesignsLoad() throws {
        for id in BookDesign.bundledIDs {
            let d = try BookDesign.named(id)
            XCTAssertEqual(d.id, id)
            XCTAssertFalse(d.name.isEmpty)
            // Every key the template reads must be present.
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: d.folder.appendingPathComponent("design.json"))) as! [String: Any]
            for key in ["page", "type", "colour", "ornament", "content"] { XCTAssertNotNil(json[key], "\(id) lacks \(key)") }
        }
        XCTAssertThrowsError(try BookDesign.named("/nonexistent")) { XCTAssertEqual($0 as? BookError, .missingDesign("/nonexistent")) }
    }

    /// Writes the Typst project; compiles it too when `typst` is installed. Set GRIMOIRE_BOOK_OUT to keep the output.
    func testWritesTypstProject() throws {
        let book = BookExporter(library: lib).book(try sampleMonth(), spec: october, generatedOn: "2026-10-31")
        let keep = ProcessInfo.processInfo.environment["GRIMOIRE_BOOK_OUT"].map { URL(fileURLWithPath: $0) }
        for id in BookDesign.bundledIDs {
            let root = (keep ?? TestSupport.tempDir()).appendingPathComponent(id)
            try BookWriter.write(book, design: try BookDesign.named(id), to: root, attachmentsRoot: nil)
            for f in ["main.typ", "grimoire.typ", "book.json", "design.json"] {
                XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(f).path), f)
            }
            #if os(macOS) || os(Linux)
            if let typst = TypstRenderer.locate() {
                let fonts = ProcessInfo.processInfo.environment["GRIMOIRE_FONTS"].map { [URL(fileURLWithPath: $0)] } ?? []
                let pdf = try TypstRenderer(executable: typst, fontPaths: fonts).render(folder: root)
                let bytes = try Data(contentsOf: pdf)
                XCTAssertEqual(String(decoding: bytes.prefix(5), as: UTF8.self), "%PDF-")
            }
            #endif
        }
    }
}
