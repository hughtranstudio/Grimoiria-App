import XCTest
@testable import GrimoireCore

final class YiJingTests: XCTestCase {
    let yj = TestSupport.library.yijing

    func testChangingCast() throws {
        let c = try YiJingCast(quick: "789677")
        XCTAssertEqual(c.primaryHexagram(in: yj), 37)
        XCTAssertEqual(c.changingLines, [3, 4])
        XCTAssertEqual(c.resultingHexagram(in: yj), 25)
    }

    func testStaticCastHasNoResult() throws {
        let c = try YiJingCast(lines: [7, 7, 7, 7, 7, 7])
        XCTAssertEqual(c.primaryHexagram(in: yj), 1)
        XCTAssertEqual(c.changingLines, [])
        XCTAssertNil(c.resultingHexagram(in: yj))
    }

    func testAllOldLinesFlip() throws {
        XCTAssertEqual(try YiJingCast(quick: "999999").resultingHexagram(in: yj), 2)
        XCTAssertEqual(try YiJingCast(quick: "666666").resultingHexagram(in: yj), 1)
        XCTAssertEqual(try YiJingCast(quick: "8 8 8 8 8 9").primaryHexagram(in: yj), 23)
    }

    func testInvalidCasts() {
        XCTAssertThrowsError(try YiJingCast(quick: "78967")) { XCTAssertEqual($0 as? YiJingError, .wrongLineCount(5)) }
        XCTAssertThrowsError(try YiJingCast(lines: [7, 8, 9, 6, 7, 5])) { XCTAssertEqual($0 as? YiJingError, .invalidLineValue(5)) }
    }

    func testDecodingRejectsBadLines() {
        let bad = Data(#"{"method":"coins","lines":[1,2,3,4,5,6]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(YiJingCast.self, from: bad))
    }
}
