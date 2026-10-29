import XCTest
@testable import GrimoireCore

final class CorrespondencesTests: XCTestCase {
    let lib = TestSupport.library
    var table: Correspondences { lib.correspondences! }

    func testBundledTableLoadsAndValidates() {
        XCTAssertTrue(lib.validate().isValid, "\(lib.validate().errors)")
        XCTAssertEqual(table.entries.filter { $0.kind == "planet" }.count, 7)
        XCTAssertEqual(table.entries.filter { $0.kind == "sign" }.count, 12)
        XCTAssertEqual(table.entries.filter { $0.kind == "element" }.count, 4)
        XCTAssertEqual(table.entries.filter { $0.kind == "trigram" }.count, 8)
        XCTAssertEqual(Set(table.entries.filter { $0.kind == "trigram" }.map(\.key)), Set(lib.yijing.trigrams.map(\.id)))
    }

    func testClassicalFacts() throws {
        let mars = try XCTUnwrap(table.entry("planet:mars"))
        XCTAssertEqual(mars.values("Day"), ["Tuesday"])
        XCTAssertEqual(mars.values("Metal"), ["Iron"])
        XCTAssertEqual(mars.values("Rules"), ["Aries", "Scorpio"])
        XCTAssertEqual(table.entry("planet:sun")?.values("Exalted in"), ["Aries"])
        XCTAssertEqual(table.entry("sign:pisces")?.values("Ruler"), ["Jupiter"])
        XCTAssertEqual(table.entry("element:air")?.values("Tarot suit"), ["Swords"])
        // Every planet's days match the weekday rulers used for planetary days.
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        for (i, p) in Planet.dayRulers.enumerated() { XCTAssertEqual(table.entry("planet:\(p.rawValue)")?.values("Day"), [days[i]]) }
        // Each sign's element lists it back.
        for s in table.entries where s.kind == "sign" {
            let el = try XCTUnwrap(table.entry("element:\(s.values("Element")[0].lowercased())"))
            XCTAssertTrue(el.values("Signs").contains(s.name), s.name)
        }
    }

    func testSearchAndLinks() throws {
        XCTAssertEqual(table.search("iron").map(\.id), ["planet:mars"])
        XCTAssertEqual(table.search("Mars").first?.id, "planet:mars", "name matches first")
        XCTAssertTrue(table.search("Mars").contains { $0.id == "sign:aries" })
        XCTAssertEqual(Set(table.search("head").map(\.id)), ["sign:aries", "trigram:qian"])
        XCTAssertEqual(table.search("♂").map(\.id), ["planet:mars"])
        let aries = try XCTUnwrap(table.entry("sign:aries"))
        XCTAssertTrue(table.mentions(of: aries).contains { $0.id == "planet:mars" })
        XCTAssertTrue(table.mentions(of: aries).contains { $0.id == "planet:sun" }, "exalted in Aries")
    }

    func testCardsAndHexagrams() throws {
        let tower = lib.cards(for: try XCTUnwrap(table.entry("planet:mars"))).map(\.card.name)
        XCTAssertEqual(tower, ["The Tower"])
        XCTAssertEqual(lib.cards(for: try XCTUnwrap(table.entry("sign:aries"))).map(\.card.name), ["The Emperor"])
        let fire = lib.cards(for: try XCTUnwrap(table.entry("element:fire"))).map(\.card.name)
        XCTAssertTrue(fire.contains("Ace of Wands") && fire.contains("Judgement"), "\(fire)")
        XCTAssertEqual(lib.hexagrams(withTrigram: "qian").count, 15)
    }
}
