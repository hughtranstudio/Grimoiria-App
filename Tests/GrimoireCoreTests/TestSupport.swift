import Foundation
import XCTest
@testable import GrimoireCore

enum TestSupport {
    static let library: DefinitionLibrary = try! DefinitionLibrary.bundled()
    static let parser = ReadingParser(library: library)

    static func fixture(_ path: String) -> URL {
        Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent(path)
    }

    static func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("grimoire-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func date(_ iso: String, tz: String = "America/Los_Angeles") -> ZonedDate {
        ZonedDate.parse(iso, timeZone: tz)!
    }
}
