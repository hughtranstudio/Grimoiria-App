import XCTest
@testable import GrimoireCore

final class ImportTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    var importer: DocumentImporter {
        var i = DocumentImporter(parser: TestSupport.parser)
        i.timeZone = "America/Los_Angeles"
        i.location = GeoLocation(latitude: 37.77, longitude: -122.42)
        return i
    }

    func doc(_ name: String) throws -> ImportDocument {
        try ImportDocument(name: name, data: Data(contentsOf: TestSupport.fixture("import/\(name)")))
    }

    // MARK: Dates

    func testDateLinesInCommonFormats() throws {
        let cases: [(String, [Int], [Int]?, String)] = [
            ("2026-10-28", [2026, 10, 28], nil, ""),
            ("## 2026-10-28 08:14 omen: crow on the gate", [2026, 10, 28], [8, 14], "omen: crow on the gate"),
            ("**28 October 2026** — Ritual", [2026, 10, 28], nil, "Ritual"),
            ("28th of Oct 2026", [2026, 10, 28], nil, ""),
            ("Tuesday, October 28, 2026 at 9pm - Dream", [2026, 10, 28], [21, 0], "Dream"),
            ("Sept 3 2025, 12:30 am", [2025, 9, 3], [0, 30], ""),
            ("10/28/26", [2026, 10, 28], nil, ""),
            ("28/10/2026 meditation", [2026, 10, 28], nil, "meditation"),
            ("- 3.4.2026 20h15", [2026, 3, 4], [20, 15], ""),
        ]
        for (line, ymd, hm, rest) in cases {
            let d = try XCTUnwrap(DateLine.parse(line), line)
            XCTAssertEqual([d.year, d.month, d.day], ymd, line)
            XCTAssertEqual(d.hour.map { [$0, d.minute!] }, hm, line)
            XCTAssertEqual(d.rest, rest, line)
        }
    }

    func testNotDateLines() {
        for line in ["I saw the date 2026-10-28 in a dream", "October 2026", "31 February 2026", "2026-10-28T08:14", "13/13/2026", "The 3 of cups"] {
            XCTAssertNil(DateLine.parse(line), line)
        }
    }

    func testSlashOrderAndAmbiguity() throws {
        let us = try XCTUnwrap(DateLine.parse("03/04/2026"))
        XCTAssertEqual([us.month, us.day], [3, 4])
        XCTAssertTrue(us.ambiguous)
        let eu = try XCTUnwrap(DateLine.parse("03/04/2026", slashOrder: .dayFirst))
        XCTAssertEqual([eu.month, eu.day], [4, 3])
        XCTAssertFalse(try XCTUnwrap(DateLine.parse("03/14/2026")).ambiguous)
    }

    // MARK: Reading files

    func testInflateStoredFixedAndDynamicBlocks() throws {
        let short = "Three of cups reversed"
        for b64 in ["ARYA6f9UaHJlZSBvZiBjdXBzIHJldmVyc2Vk", "C8koSk1VyE9TSC4tKFYoSi1LLSpOTQEA"] {
            XCTAssertEqual(String(decoding: try Inflate.inflate([UInt8](Data(base64Encoded: b64)!)), as: UTF8.self), short)
        }
        let long = String(repeating: "The Tower, page of wands, three of cups reversed. ", count: 3) + "Hexagram 3, changing lines 3 and 4; resulting hexagram 42. "
        let dynamic = "vYvJDYAwEMRamQIiHsCPBiggDaxgSJBCQLtc5XNItMDTsu0j4eeD6rBIIOYBh+TeHNaofLnbFoNypxr7Av6Ho+UpQWVC5dBFyWHMAWnMNFS4V9TNXduW1kfEr67LAhc="
        XCTAssertEqual(String(decoding: try Inflate.inflate([UInt8](Data(base64Encoded: dynamic)!)), as: UTF8.self), long)
        XCTAssertThrowsError(try Inflate.inflate([0x07]))
    }

    func testDocxStructureBecomesMarkdown() throws {
        let d = try doc("structure.docx")
        XCTAssertEqual(d.format, .docx)
        XCTAssertEqual(d.text, """
            # Tools & tables
            Line one
            line two\ttabbed
            - Salt
            - Water
            Card | Position
            The Tower | Outcome

            Évocation <done> “quoted”

            """)
        XCTAssertEqual(d.fallbackDate.map { GrimoireDateFormat.iso($0, in: TimeZone(identifier: "UTC")!) }, "2025-01-15T10:00:00Z")
    }

    func testNotAZipOrUnsupported() {
        XCTAssertThrowsError(try ImportDocument(name: "x.docx", data: Data("hello".utf8)))
        XCTAssertThrowsError(try ImportDocument(name: "x.pdf", data: Data())) { XCTAssertEqual($0 as? ImportError, .unsupported("x.pdf")) }
    }

    func testConnectorMarkdownFrontmatter() throws {
        let d = try doc("magical-diary-autumn-2025.md")
        XCTAssertEqual(d.title, "Magical diary autumn 2025")
        XCTAssertEqual(d.googleDocId, "1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789")
        XCTAssertEqual(d.sourceLabel, "import:gdoc:1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789")
        XCTAssertEqual(d.tags, ["source/google-docs"])
        XCTAssertTrue(d.text.hasPrefix("# Magical diary autumn 2025\n"))
    }

    // MARK: Splitting into Inbox items

    func testGoogleDocSplitsIntoTypedDatedItems() throws {
        let items = importer.items(for: try doc("magical-diary-autumn-2025.md"), now: now)
        XCTAssertEqual(items.map(\.entry.type), [.ritual, .divination, .dream, .divination])
        XCTAssertEqual(items.map(\.entry.title), ["Ritual: opening the directions", "Reading", "Dream", "Yi Jing on the house"])
        XCTAssertEqual(items.map(\.entry.occurredAt.iso8601),
                       ["2025-10-03T12:00:00-07:00", "2025-10-04T21:40:00-07:00", "2025-10-05T08:15:00-07:00", "2025-10-06T12:00:00-07:00"])
        XCTAssertTrue(items.allSatisfy { $0.entry.status == .inbox && $0.source.hasPrefix("import:gdoc:") })

        let ritual = items[0]
        XCTAssertEqual(ritual.entry.tags, ["source/google-docs", "theme/threshold"])
        XCTAssertNil(ritual.draft)
        XCTAssertNil(ritual.entry.timing?.planetaryHour, "no time given, so no planetary hour")
        XCTAssertNotNil(ritual.entry.timing?.planetaryDay)
        XCTAssertEqual(ritual.notes, ["No time given; noon used, so the planetary hour is left blank"])
        XCTAssertEqual(ritual.entry.extraNotes, "Imported from \"Magical diary autumn 2025\", part 1 of 4 (https://docs.google.com/document/d/1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789/edit)")

        let reading = try XCTUnwrap(items[1].draft)
        XCTAssertEqual(reading.question.value, "should I start the new course this winter?")
        XCTAssertEqual(reading.divinations.first?.draws.map(\.cardId.value), ["cups-03", "maj-16", "wands-11"])
        XCTAssertEqual(reading.divinations.first?.draws.first?.orientation.value, .reversed)
        XCTAssertNotNil(items[1].entry.timing?.planetaryHour)

        // Dated headings split the document, so a date inside a paragraph stays in its entry.
        XCTAssertTrue(items[2].entry.body.hasSuffix("2025-10-20: the course was confirmed, so the reading held."))

        // The heading names Yi Jing but only the body's line values count.
        let cast = try XCTUnwrap(items[3].draft)
        XCTAssertEqual(cast.divinations.count, 1)
        XCTAssertEqual(cast.divinations.first?.cast?.lines.value, [7, 8, 9, 6, 7, 7])
    }

    func testBothRoutesProduceTheSameItems() throws {
        let viaConnector = importer.items(for: try doc("magical-diary-autumn-2025.md"), now: now)
        let viaDownload = importer.items(for: try doc("Magical diary autumn 2025.docx"), now: now)
        XCTAssertEqual(viaDownload.map(\.entry.captureId), viaConnector.map(\.entry.captureId))
        XCTAssertEqual(viaDownload.map(\.entry.occurredAt), viaConnector.map(\.entry.occurredAt))
        XCTAssertEqual(viaDownload.map(\.entry.type), viaConnector.map(\.entry.type))
        XCTAssertEqual(viaDownload.map(\.entry.title), viaConnector.map(\.entry.title))
        XCTAssertEqual(viaDownload.map(\.entry.body), viaConnector.map(\.entry.body))
        XCTAssertEqual(viaDownload.map(\.draft), viaConnector.map(\.draft))
        XCTAssertEqual(viaDownload.first?.source, "import:Magical diary autumn 2025.docx")
    }

    func testPlainTextWithNumericDates() throws {
        let items = importer.items(for: try doc("notebook.txt"), now: now)
        XCTAssertEqual(items.count, 2, "the one-line title before the first date is dropped")
        XCTAssertEqual(items.map(\.entry.occurredAt.day), ["2025-10-28", "2025-11-02"])
        XCTAssertEqual(items.map(\.entry.type), [.journal, .meditation])
        XCTAssertEqual(items[0].entry.tags, ["entity/crow"])
        XCTAssertEqual(items[0].entry.title, nil)
        XCTAssertEqual(items[0].entry.displayTitle, "Three crows on the fence at the crossroads. #entity/crow")
        XCTAssertTrue(items[0].notes?.contains("Type not stated; set to journal") == true)
        XCTAssertTrue(items[1].notes?.contains { $0.contains("could be read either way; read as 2025-11-02") } == true)

        var eu = importer
        eu.slashOrder = .dayFirst
        XCTAssertEqual(eu.items(for: try doc("notebook.txt"), now: now).map(\.entry.occurredAt.day), ["2025-10-28", "2025-02-11"])
    }

    func testUndatedNoteUsesFrontmatterTypeAndFallbackDate() throws {
        let md = """
            ---
            type: contact
            tags:
              - entity/ally/crow
            modified: 2025-06-01T18:30:00Z
            ---
            # The crow at the gate

            It spoke of keys. #theme/threshold
            """
        let items = importer.items(for: try ImportDocument(name: "crow.md", data: Data(md.utf8)), now: now)
        XCTAssertEqual(items.count, 1)
        let e = items[0].entry
        XCTAssertEqual(e.type, .contact)
        XCTAssertEqual(e.title, "The crow at the gate")
        XCTAssertEqual(e.occurredAt.iso8601, "2025-06-01T11:30:00-07:00")
        XCTAssertEqual(e.tags, ["entity/ally/crow", "theme/threshold"])
        XCTAssertEqual(items[0].notes, ["No date in the text; used the document modified date 2025-06-01"])
        XCTAssertEqual(e.extraNotes, "Imported from \"crow\"")
    }

    func testDateLinesSplitWhenThereAreNoDatedHeadings() {
        let text = "Intro paragraph that is long enough to matter as an entry of its own, really.\nMore intro.\n2025-01-01\nfirst\n2025-01-02 Omen\nsecond"
        let s = importer.sections(of: text)
        XCTAssertEqual(s.map(\.date?.day), [nil, 1, 2])
        XCTAssertEqual(s.map(\.lines.first), ["Intro paragraph that is long enough to matter as an entry of its own, really.", "first", "second"])
    }

    // MARK: Folder import, de-duplication, confirm and export

    func testRunImportsOnceAttachesOriginalAndExportsMarkdown() throws {
        let dir = TestSupport.tempDir()
        let drop = dir.appendingPathComponent("Imports/Takeout")
        try FileManager.default.createDirectory(at: drop, withIntermediateDirectories: true)
        for name in ["magical-diary-autumn-2025.md", "notebook.txt"] {
            try FileManager.default.copyItem(at: TestSupport.fixture("import/\(name)"), to: drop.appendingPathComponent(name))
        }
        try Data().write(to: drop.appendingPathComponent("scan.pdf"))
        let repo = MemoryRepository()
        let run = ImportRun(importer: importer, attachmentsFolder: dir.appendingPathComponent("attachments"))

        let first = run.run([dir.appendingPathComponent("Imports")], now: now, isKnown: repo.knowsCapture, deliver: repo.addToInbox)
        XCTAssertEqual(first.filter { if case .imported = $0 { return true } else { return false } }.count, 6)
        XCTAssertEqual(repo.data.inbox.count, 6)
        let attachment = try XCTUnwrap(repo.data.inbox.first { $0.source == "import:notebook.txt" }?.entry.attachments.first)
        XCTAssertEqual(attachment.kind, .document)
        XCTAssertTrue(attachment.path.hasPrefix("imports/") && attachment.path.hasSuffix("-notebook.txt"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("attachments/\(attachment.path)").path))

        // Importing again, or the same Doc downloaded as .docx, adds nothing.
        try FileManager.default.copyItem(at: TestSupport.fixture("import/Magical diary autumn 2025.docx"), to: drop.appendingPathComponent("Magical diary autumn 2025.docx"))
        let second = run.run([dir.appendingPathComponent("Imports")], now: now, isKnown: repo.knowsCapture, deliver: repo.addToInbox)
        XCTAssertEqual(second.count, 10)
        XCTAssertTrue(second.allSatisfy { if case .duplicate = $0 { return true } else { return false } })
        XCTAssertEqual(repo.data.inbox.count, 6)

        // An unsupported file named directly fails with a reason instead of being skipped silently.
        XCTAssertEqual(run.run([drop.appendingPathComponent("scan.pdf")], isKnown: { _ in false }, deliver: { _ in }),
                       [.failed(file: "scan.pdf", reason: ImportError.unsupported("scan.pdf").description)])

        // Nothing is filed until confirm; confirming the reading makes an Inquiry.
        XCTAssertTrue(repo.data.entries.isEmpty)
        for item in repo.data.inbox { try repo.confirm(item.id, corrected: item.draft, library: TestSupport.library, now: now) }
        XCTAssertEqual(repo.data.entries.count, 6)
        XCTAssertEqual(repo.data.inquiries.count, 2)
        XCTAssertTrue(repo.data.inquiries.contains { $0.question == "should I start the new course this winter?" })

        let files = ObsidianExporter(library: TestSupport.library).files(for: repo.data)
        let ritual = try XCTUnwrap(files.first { $0.key.hasPrefix("Entries/2025/10/2025-10-03-ritual-") }?.value)
        XCTAssertTrue(ritual.contains("type: ritual\n"))
        XCTAssertTrue(ritual.contains("title: \"Ritual: opening the directions\"\n"))
        XCTAssertTrue(ritual.contains("tags: [source/google-docs, theme/threshold]\n"))
        XCTAssertTrue(ritual.contains("attachments: [_attachments/imports/"))
        XCTAssertTrue(ritual.contains("## Extra notes\n\nImported from \"Magical diary autumn 2025\", part 1 of 4"))
    }

    func testInboxItemsWithoutNotesStillDecode() throws {
        let item = InboxItem(entry: Entry(type: .journal, occurredAt: TestSupport.date("2026-10-28T08:14:00-07:00"), status: .inbox), draft: nil, source: "phone:x")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as! [String: Any]
        XCTAssertNil(json["notes"])
        json["notes"] = nil
        XCTAssertNoThrow(try JSONDecoder().decode(InboxItem.self, from: JSONSerialization.data(withJSONObject: json)))
    }
}
