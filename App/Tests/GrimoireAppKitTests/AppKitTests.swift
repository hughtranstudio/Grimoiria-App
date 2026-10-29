import Foundation
import Testing
import GrimoireCore
@testable import GrimoireAppKit

@Test("Tags typed on one line", arguments: [
    ("entity/ally/crow, place/garden", ["entity/ally/crow", "place/garden"]),
    ("#omen #Bird  bird", ["omen", "bird"]),
    ("", []),
])
func tagInput(_ text: String, expected: [String]) {
    #expect(TagInput.parse(text).map(\.path) == expected)
}

@Test func tagCompletion() {
    #expect(TagInput.fragment(of: "omen, ent") == "ent")
    #expect(TagInput.complete("omen, ent", with: "entity/ally") == "omen, entity/ally, ")
}

@Test("Page queries", arguments: [
    ("Volume III pp. 40–50", "III", 40...50),
    ("III 40-50", "III", 40...50),
    ("vol 3 p 12", "3", 12...12),
    ("Volume IV", "IV", nil),
])
func pageQuery(_ text: String, volume: String, pages: ClosedRange<Int>?) {
    #expect(PageQuery.parse(text) == PageQuery(volume: volume, pages: pages))
}

@Test func pageQueryIgnoresPlainText() {
    #expect(PageQuery.parse("tower") == nil)
    #expect(PageQuery.parse("40") == nil)
}

@Test func volumeNamesMatchByNumeral() {
    let q = PageQuery(volume: "III", pages: nil)
    #expect(q.matches(volumeName: "Volume III"))
    #expect(!q.matches(volumeName: "Volume II"))
    #expect(PageQuery(volume: "3", pages: nil).matches(volumeName: "Grimoire III"))
}

@Test func romanNumerals() {
    #expect(PageQuery.number("XIV") == 14)
    #expect(PageQuery.number("ix") == 9)
    #expect(PageQuery.number("crow") == nil)
}

@Test func quickKeys() {
    #expect(QuickKind.forKey("C") == .cardDraw)
    #expect(QuickKind.forKey("y") == .yijing)
    #expect(QuickKind.forKey("x") == nil)
    #expect(Set(QuickKind.allCases.map(\.key)).count == QuickKind.allCases.count)
}

@Test func reminderChoices() {
    #expect(ReminderChoice.preset(.none).dueOn(from: "2026-10-28") == nil)
    #expect(ReminderChoice.preset(.oneWeek).dueOn(from: "2026-10-28") == "2026-11-04")
    #expect(ReminderChoice.customDays(10).dueOn(from: "2026-10-28") == "2026-11-07")
}

@Test func datesReadMonthFirst() {
    let d = ZonedDate(GrimoireDateFormat.parseISO("2026-10-28T08:14:00-07:00")!, timeZone: "America/Los_Angeles")
    #expect(DisplayDate.day(d) == "10-28-2026")
    #expect(DisplayDate.day("2026-11-04") == "11-04-2026")
}

@Test func cardGlyphs() {
    let wands = DeckDefinition.Card(id: "wands-09", name: "Nine of Wands", attributes: ["suit": .string("wands"), "element": .string("fire")])
    let fool = DeckDefinition.Card(id: "maj-00", name: "The Fool", attributes: ["attribution": .string("air")])
    let sun = DeckDefinition.Card(id: "maj-19", name: "The Sun", attributes: ["attribution": .string("sun")])
    #expect(CardGlyph.symbol(for: wands) == "🜂")
    #expect(CardGlyph.symbol(for: fool) == "🜁")
    #expect(CardGlyph.symbol(for: sun) == "☉")
}

func bundledDefinitions() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/GrimoireCore/Resources/Definitions")
}

func tempFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("grimoire-defs-\(UUID().uuidString)/Definitions")
}

@Test func definitionsInstallOnceAndValidate() throws {
    let dest = tempFolder()
    defer { try? FileManager.default.removeItem(at: dest.deletingLastPathComponent()) }
    let lib = try DefinitionsFolder.install(from: bundledDefinitions(), to: dest)
    #expect(lib.validate().isValid)
    #expect(lib.decks.count == 4)
    #expect(lib.spreads.count == 8)
    // A second install keeps edits.
    var deck = lib.deck("custom-template")!
    deck.name = "My deck"
    _ = try DefinitionsFolder.save(deck, in: lib, folder: dest)
    let again = try DefinitionsFolder.install(from: bundledDefinitions(), to: dest)
    #expect(again.deck("custom-template")?.name == "My deck")
}

@Test func installAddsFilesFromANewerApp() throws {
    let dest = tempFolder()
    defer { try? FileManager.default.removeItem(at: dest.deletingLastPathComponent()) }
    _ = try DefinitionsFolder.install(from: bundledDefinitions(), to: dest)
    // An older install had no correspondences table and one spread fewer.
    try FileManager.default.removeItem(at: dest.appendingPathComponent("correspondences.json"))
    try FileManager.default.removeItem(at: dest.appendingPathComponent("spreads/celtic-cross.json"))
    #expect(try DefinitionLibrary.load(from: dest).correspondences == nil)
    let lib = try DefinitionsFolder.install(from: bundledDefinitions(), to: dest)
    #expect(lib.correspondences?.entry("planet:mars") != nil)
    #expect(lib.spread("celtic-cross") != nil)
    // Saving a deck keeps the table.
    #expect(try DefinitionsFolder.save(lib.deck("custom-template")!, in: lib, folder: dest).correspondences != nil)
}

@Test func installReplacesAnEmptyPlaceholderDeck() throws {
    let dest = tempFolder()
    defer { try? FileManager.default.removeItem(at: dest.deletingLastPathComponent()) }
    let lib = try DefinitionsFolder.install(from: bundledDefinitions(), to: dest)
    // An older install still has the empty Quareia placeholder.
    var old = lib.deck("quareia")!
    old.status = .placeholder
    old.cards = []
    _ = try DefinitionsFolder.save(old, in: lib, folder: dest)
    #expect(try DefinitionLibrary.load(from: dest).deck("quareia")?.cards.isEmpty == true)
    let upgraded = try DefinitionsFolder.install(from: bundledDefinitions(), to: dest)
    #expect(upgraded.deck("quareia")?.cards.count == 81)
    // A placeholder the user has started filling in is kept.
    var mine = upgraded.deck("quareia")!
    mine.status = .placeholder
    mine.cards = [DeckDefinition.Card(id: "my-card", name: "My card")]
    _ = try DefinitionsFolder.save(mine, in: upgraded, folder: dest)
    #expect(try DefinitionsFolder.install(from: bundledDefinitions(), to: dest).deck("quareia")?.cards.count == 1)
}

@Test func invalidDeckIsNotSaved() throws {
    let dest = tempFolder()
    defer { try? FileManager.default.removeItem(at: dest.deletingLastPathComponent()) }
    let lib = try DefinitionsFolder.install(from: bundledDefinitions(), to: dest)
    var deck = lib.deck("rws-tarot")!
    deck.cards.removeLast()
    #expect(throws: DeckSaveError.self) { try DefinitionsFolder.save(deck, in: lib, folder: dest) }
    #expect(try DefinitionLibrary.load(from: dest).deck("rws-tarot")?.cards.count == 78)
}
