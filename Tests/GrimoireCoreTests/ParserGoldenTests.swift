import XCTest
@testable import GrimoireCore

/// Shared parser cases. The Android capture app's Kotlin port runs the same file
/// (android/core/src/test), so both parsers must give identical drafts.
///
/// To regenerate after an intentional parser change:
/// `GRIMOIRE_REGENERATE_GOLDEN=1 swift test --filter ParserGoldenTests`
final class ParserGoldenTests: XCTestCase {
    struct Case: Codable {
        var mode: String
        var input: String
        var deckId: String?
        var spreadId: String?
        var expected: DraftReading?
    }

    static let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/parser-golden/cases.json")

    func run(_ c: Case) -> DraftReading {
        let parser = TestSupport.parser
        if c.mode == "quick" {
            return DraftReading(divinations: [parser.parseQuickDraw(c.input, deckId: c.deckId!, spreadId: c.spreadId)])
        }
        return parser.parse(c.input)
    }

    func testGoldenCases() throws {
        var cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: Self.path))
        XCTAssertGreaterThan(cases.count, 10)
        if ProcessInfo.processInfo.environment["GRIMOIRE_REGENERATE_GOLDEN"] != nil {
            for i in cases.indices { cases[i].expected = run(cases[i]) }
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try (enc.encode(cases) + Data("\n".utf8)).write(to: Self.path)
            return
        }
        for c in cases {
            XCTAssertEqual(run(c), try XCTUnwrap(c.expected, "no expected value for \(c.input)"), c.input)
        }
    }
}
