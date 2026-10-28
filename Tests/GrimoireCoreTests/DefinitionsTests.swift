import XCTest
@testable import GrimoireCore

final class DefinitionsTests: XCTestCase {
    let lib = TestSupport.library

    func testBundledDefinitionsValidate() {
        let report = lib.validate()
        XCTAssertTrue(report.isValid, report.errors.joined(separator: "\n"))
        // Quareia and Mystagogos are flagged as placeholders until the deck repos are found.
        XCTAssertEqual(report.warnings.count, 2)
        XCTAssertTrue(report.warnings.contains { $0.hasPrefix("quareia") })
        XCTAssertTrue(report.warnings.contains { $0.hasPrefix("mystagogos") })
    }

    func testPreloadedDecksAndSpreads() {
        XCTAssertEqual(Set(lib.decks.map(\.id)), ["rws-tarot", "quareia", "mystagogos", "custom-template"])
        XCTAssertEqual(Set(lib.spreads.map(\.id)), ["single", "three-card", "celtic-cross", "freeform"])
        XCTAssertEqual(lib.spread("celtic-cross")?.positions.count, 10)
        XCTAssertTrue(lib.freeform.openEnded)
    }

    func testRWSStructure() throws {
        let rws = try XCTUnwrap(lib.deck("rws-tarot"))
        XCTAssertEqual(rws.cards.count, 78)
        XCTAssertEqual(Set(rws.cards.map(\.id)).count, 78)
        XCTAssertEqual(rws.cards.filter { $0.attributes["arcana"] == .string("major") }.count, 22)
        for suit in ["wands", "cups", "swords", "pentacles"] {
            XCTAssertEqual(rws.cards.filter { $0.attributes["suit"] == .string(suit) }.count, 14, suit)
        }
        XCTAssertEqual(rws.card("maj-16")?.name, "The Tower")
        XCTAssertEqual(rws.card("cups-03")?.name, "Three of Cups")
        XCTAssertEqual(rws.card("pentacles-14")?.name, "King of Pentacles")
        XCTAssertEqual(rws.card("wands-01")?.attributes["element"], .string("fire"))
        XCTAssertTrue(rws.reversalsAllowed)
    }

    func testDeckRoundTripKeepsFlatAttributes() throws {
        let rws = try XCTUnwrap(lib.deck("rws-tarot"))
        let data = try JSONEncoder().encode(rws)
        let back = try JSONDecoder().decode(DeckDefinition.self, from: data)
        XCTAssertEqual(back, rws)
    }

    func testYiJingKingWenTable() throws {
        let yj = lib.yijing
        XCTAssertEqual(yj.hexagrams.count, 64)
        // Spot checks: upper over lower
        func number(_ upper: String, _ lower: String) -> Int? { yj.hexagrams.first { $0.upper == upper && $0.lower == lower }?.number }
        XCTAssertEqual(number("qian", "qian"), 1)
        XCTAssertEqual(number("kun", "kun"), 2)
        XCTAssertEqual(number("kun", "qian"), 11)  // Peace: Earth over Heaven
        XCTAssertEqual(number("qian", "kun"), 12)  // Standstill
        XCTAssertEqual(number("kan", "li"), 63)    // After Completion
        XCTAssertEqual(number("li", "kan"), 64)
        XCTAssertEqual(number("kan", "zhen"), 3)
        XCTAssertEqual(number("gen", "kan"), 4)
        XCTAssertEqual(number("xun", "dui"), 61)
        XCTAssertEqual(yj.hexagram(1)?.lines, [1, 1, 1, 1, 1, 1])
        XCTAssertEqual(yj.hexagram(24)?.lines, [1, 0, 0, 0, 0, 0]) // Return: one yang at the bottom
        XCTAssertEqual(yj.hexagram(23)?.lines, [0, 0, 0, 0, 0, 1]) // Splitting Apart
    }

    func testLoadFromFolderDetectsErrors() throws {
        let dir = TestSupport.tempDir()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("decks"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("spreads"), withIntermediateDirectories: true)
        let yj = try JSONEncoder().encode(lib.yijing)
        try yj.write(to: dir.appendingPathComponent("yijing.json"))
        try Data(#"{"id":"x","name":"X","version":1,"system":"oracle","status":"complete","reversalsAllowed":false,"aliases":[],"attributes":[],"cards":[{"id":"a","name":"A","colour":"red"},{"id":"a","name":"A2"}]}"#.utf8)
            .write(to: dir.appendingPathComponent("decks/x.json"))
        let loaded = try DefinitionLibrary.load(from: dir)
        let r = loaded.validate()
        XCTAssertTrue(r.errors.contains { $0.contains("duplicate card id a") })
        XCTAssertTrue(r.errors.contains { $0.contains("'colour' not declared") })
        XCTAssertTrue(r.errors.contains { $0.contains("freeform") })
    }
}
