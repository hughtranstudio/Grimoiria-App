import XCTest
@testable import GrimoireCore

final class ParserTests: XCTestCase {
    let parser = TestSupport.parser

    func cards(_ d: DraftDivination) -> [String?] { d.draws.map(\.cardId.value) }
    func orientations(_ d: DraftDivination) -> [Orientation?] { d.draws.map(\.orientation.value) }

    /// Spec §14 acceptance phrase.
    func testAcceptancePhrase() {
        let r = parser.parse("Deck Rider-Waite, three card: three of cups reversed, the Tower, page of wands")
        XCTAssertEqual(r.divinations.count, 1)
        let d = r.divinations[0]
        XCTAssertEqual(d.deckId.value, "rws-tarot")
        XCTAssertEqual(d.spreadId.value, "three-card")
        XCTAssertEqual(cards(d), ["cups-03", "maj-16", "wands-11"])
        XCTAssertEqual(orientations(d), [.reversed, .upright, .upright])
        XCTAssertEqual(d.draws.map(\.positionKey), ["past", "present", "future"])
        XCTAssertEqual(r.weakest, .high)
        XCTAssertTrue(r.warnings.isEmpty, "\(r.warnings)")
    }

    /// The pattern taught in the Shortcut guide §4, with spoken position numbers.
    func testShortcutGuidePattern() {
        let r = parser.parse("Question: will the move go ahead. Deck Rider-Waite. Three card. One, three of cups reversed. Two, the Tower. Three, page of wands. Yi Jing, coins. Seven eight nine six seven seven.")
        XCTAssertEqual(r.question.value, "will the move go ahead")
        XCTAssertEqual(r.divinations.count, 2)
        XCTAssertEqual(cards(r.divinations[0]), ["cups-03", "maj-16", "wands-11"])
        XCTAssertEqual(r.divinations[1].system, .yijing)
        XCTAssertEqual(r.divinations[1].cast?.lines.value, [7, 8, 9, 6, 7, 7])
        XCTAssertEqual(r.divinations[1].cast?.method, .coins)
        XCTAssertTrue(r.unparsed.isEmpty, "\(r.unparsed)")
    }

    func testNoPunctuationStillParses() {
        let r = parser.parse("deck rider waite three card three of cups reversed the tower page of wands")
        XCTAssertEqual(cards(r.divinations[0]), ["cups-03", "maj-16", "wands-11"])
        XCTAssertEqual(orientations(r.divinations[0]), [.reversed, .upright, .upright])
    }

    func testQuestionKeepsCasingAndQuestionMark() {
        let r = parser.parse("Question: Will Anna take the job? Deck RWS single card. Ace of Swords.")
        XCTAssertEqual(r.question.value, "Will Anna take the job?")
        XCTAssertEqual(r.divinations[0].spreadId.value, "single")
        XCTAssertEqual(cards(r.divinations[0]), ["swords-01"])
    }

    func testSuitSynonymsDigitsAndUpsideDown() {
        let r = parser.parse("Deck Rider Waite. 10 of coins, knight of rods upside down, queen of chalices, the hanged man inverted")
        let d = r.divinations[0]
        XCTAssertEqual(cards(d), ["pentacles-10", "wands-12", "cups-13", "maj-12"])
        XCTAssertEqual(orientations(d), [.upright, .reversed, .upright, .reversed])
        XCTAssertEqual(d.spreadId.value, "freeform")
        XCTAssertEqual(d.draws.map(\.positionKey), ["1", "2", "3", "4"])
    }

    func testFuzzyMatchIsLowConfidence() {
        let r = parser.parse("Deck Rider-Waite. The hight priestess, temperence")
        let d = r.divinations[0]
        XCTAssertEqual(cards(d), ["maj-02", "maj-14"])
        XCTAssertTrue(d.draws.allSatisfy { $0.cardId.confidence < .high })
        XCTAssertLessThan(r.weakest, .high)
    }

    func testUnrecognisedWordsAreSurfaced() {
        let r = parser.parse("Deck Rider-Waite three card. Three of cups. The tour. Page of wands.")
        XCTAssertEqual(cards(r.divinations[0]), ["cups-03", "wands-11"])
        XCTAssertEqual(r.unparsed, ["tour"])
        XCTAssertTrue(r.warnings.contains { $0.contains("3 positions but 2 cards") })
    }

    func testCompoundReadingWithQuareia() {
        let r = parser.parse("Question: the new house. Deck Rider-Waite, single, the Star. Deck Quareia, the weaver. I Ching 789676.")
        XCTAssertEqual(r.divinations.count, 3)
        XCTAssertEqual(r.divinations[0].deckId.value, "rws-tarot")
        XCTAssertEqual(r.divinations[1].deckId.value, "quareia")
        XCTAssertEqual(cards(r.divinations[1]), ["weaver-of-creation"])
        XCTAssertTrue(r.warnings.isEmpty, "\(r.warnings)")
        XCTAssertEqual(r.divinations[2].cast?.lines.value, [7, 8, 9, 6, 7, 6])
    }

    func testQuareiaLayoutAndCards() {
        let r = parser.parse("Deck Quareia, four directions. Mother Earth, Staff of the Gods, the Grindstone, Gate of the Past, Blood Ancestor, Union.")
        let d = r.divinations[0]
        XCTAssertEqual(d.spreadId.value, "quareia-four-directions")
        XCTAssertEqual(cards(d), ["mother-earth", "staff-of-the-gods", "grindstone", "gate-of-the-past", "blood-ancestor", "union"])
        XCTAssertEqual(d.draws.map(\.positionKey), ["centre", "east", "south", "west", "north", "union"])
        XCTAssertTrue(r.unparsed.isEmpty, "\(r.unparsed)")
    }

    func testPlaceholderDeckWarns() {
        let r = parser.parse("Deck Mystagogos, the oracle.")
        XCTAssertEqual(r.divinations[0].deckId.value, "mystagogos")
        XCTAssertTrue(r.divinations[0].draws.isEmpty)
        XCTAssertTrue(r.warnings.contains { $0.contains("mystagogos has no card list") })
    }

    func testOverfullSpreadMarksExtrasLow() {
        let r = parser.parse("Deck RWS single card. The Fool, the Magician")
        let d = r.divinations[0]
        XCTAssertEqual(d.draws.map(\.positionKey), ["card", "extra-1"])
        XCTAssertEqual(d.draws[1].cardId.confidence, .low)
    }

    func testYiJingWrongCountIsLow() {
        let r = parser.parse("Yi Jing yarrow. seven eight nine")
        XCTAssertEqual(r.divinations[0].cast?.method, .yarrow)
        XCTAssertEqual(r.divinations[0].cast?.lines.confidence, .low)
        XCTAssertTrue(r.warnings.contains { $0.contains("need 6") })
    }

    func testPlainSpeechIsNotAReading() {
        let r = parser.parse("Saw a crow land on the gate this morning, felt like a threshold.")
        XCTAssertTrue(r.isEmpty)
    }

    func testQuickDraw() {
        let d = parser.parseQuickDraw("3 cups r, tower, page wands", deckId: "rws-tarot", spreadId: "three-card")
        XCTAssertEqual(cards(d), ["cups-03", "maj-16", "wands-11"])
        XCTAssertEqual(orientations(d), [.reversed, .upright, .upright])
        XCTAssertEqual(d.draws[0].orientation.confidence, .medium) // shorthand "r"
    }

    func testMatcherPrefersExactLongerNames() {
        let m = TestSupport.library.deck("rws-tarot")!.cardMatcher
        XCTAssertEqual(m.match("wheel of fortune")?.id, "maj-10")
        XCTAssertEqual(m.match("the moon")?.id, "maj-18")
        XCTAssertEqual(m.match("judgment")?.id, "maj-20")
        XCTAssertNil(m.match("cat"))
    }
}
