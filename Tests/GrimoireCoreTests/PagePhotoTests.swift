import XCTest
@testable import GrimoireCore

final class PagePhotoTests: XCTestCase {
    func testPageLabels() {
        XCTAssertEqual(PageNumbering.labels(from: "40", count: 3, pagination: .page), ["40", "41", "42"])
        XCTAssertEqual(PageNumbering.labels(from: "40", count: 2, pagination: .page, pagesPerPhoto: 2), ["40–41", "42–43"])
        XCTAssertEqual(PageNumbering.labels(from: "12v", count: 3, pagination: .folio), ["12v", "13r", "13v"])
        XCTAssertEqual(PageNumbering.labels(from: "12", count: 2, pagination: .folio, pagesPerPhoto: 2), ["12r–12v", "13r–13v"])
        XCTAssertNil(PageNumbering.labels(from: "frontispiece", count: 1, pagination: .page))
        XCTAssertNil(PageNumbering.labels(from: "12v", count: 1, pagination: .page))
        XCTAssertEqual(PageNumbering.labels(from: "x", count: 0, pagination: .page), [])
    }

    func testStoreCopiesOnceByContent() throws {
        let dir = TestSupport.tempDir()
        let src = dir.appendingPathComponent("IMG_0042.HEIC")
        try Data("page".utf8).write(to: src)
        let store = dir.appendingPathComponent("Attachments")
        let a = try AttachmentFiles.store(src, in: store)
        let b = try AttachmentFiles.store(src, in: store)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.kind, .image)
        XCTAssertTrue(a.path.hasPrefix("photos/") && a.path.hasSuffix("-IMG_0042.HEIC"))
        XCTAssertEqual(try Data(contentsOf: store.appendingPathComponent(a.path)), Data("page".utf8))
        XCTAssertEqual(AttachmentFiles.kind(for: URL(fileURLWithPath: "/x/a.m4a")), .audio)
        XCTAssertEqual(AttachmentFiles.kind(for: URL(fileURLWithPath: "/x/a.pdf")), .document)
    }

    func testIndexerMakesPhysicalOnlyEntries() throws {
        let vol = Volume(name: "Volume III")
        let photos = (1...3).map { Attachment(kind: .image, path: "photos/p\($0).jpg") }
        let written = TestSupport.date("2025-03-02T12:00:00-08:00")
        let entries = try PageIndexer(volume: vol, firstPage: "40", writtenOn: written, tags: ["practice/notebook"],
                                      location: GeoLocation(latitude: 37.77, longitude: -122.42)).entries(for: photos)
        XCTAssertEqual(entries.map(\.physicalRef?.page), ["40", "41", "42"])
        XCTAssertEqual(entries.map(\.title), ["Volume III p. 40", "Volume III p. 41", "Volume III p. 42"])
        XCTAssertTrue(entries.allSatisfy { $0.physicalRef?.physicalOnly == true && $0.status == .filed && $0.mode == .quick })
        XCTAssertEqual(entries[1].physicalRef?.photo, photos[1])
        XCTAssertEqual(entries[0].occurredAt.day, "2025-03-02")
        XCTAssertNotNil(entries[0].timing?.planetaryDay)
        XCTAssertNil(entries[0].timing?.planetaryHour, "the hour is unknown for a day-only date")
        XCTAssertThrowsError(try PageIndexer(volume: vol, firstPage: "cover").entries(for: photos))

        let repo = MemoryRepository()
        repo.save(vol)
        for e in entries.reversed() { repo.save(e) }
        XCTAssertEqual(repo.pagesToTranscribe(in: vol.id).map(\.physicalRef?.page), ["40", "41", "42"])
        let hits = repo.search(SearchQuery(volumeId: vol.id, pages: 41...41))
        XCTAssertEqual(hits, [.entry(entries[1].id)])
    }

    func testExportEmbedsPagePhoto() throws {
        let vol = Volume(name: "Volume III")
        let photo = Attachment(kind: .image, path: "photos/abcd1234-IMG_1.jpg")
        let e = try PageIndexer(volume: vol, firstPage: "7", writtenOn: TestSupport.date("2025-03-02T12:00:00-08:00"))
            .entries(for: [photo])[0]
        let repo = MemoryRepository()
        repo.save(vol); repo.save(e)
        let md = try XCTUnwrap(ObsidianExporter(library: TestSupport.library).files(for: repo.data).first { $0.key.hasPrefix("Entries/") }?.value)
        XCTAssertTrue(md.contains("  photo: _attachments/photos/abcd1234-IMG_1.jpg\n  physical_only: true\n"), md)
        XCTAssertTrue(md.contains("![[_attachments/photos/abcd1234-IMG_1.jpg]]"))
    }
}
