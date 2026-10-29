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
    #expect(lib.spreads.count == 4)
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

@Test func invalidDeckIsNotSaved() throws {
    let dest = tempFolder()
    defer { try? FileManager.default.removeItem(at: dest.deletingLastPathComponent()) }
    let lib = try DefinitionsFolder.install(from: bundledDefinitions(), to: dest)
    var deck = lib.deck("rws-tarot")!
    deck.cards.removeLast()
    #expect(throws: DeckSaveError.self) { try DefinitionsFolder.save(deck, in: lib, folder: dest) }
    #expect(try DefinitionLibrary.load(from: dest).deck("rws-tarot")?.cards.count == 78)
}

// MARK: House style (DRAFT)

@Test("Every house style reads", arguments: HouseTokens.styles)
func houseStyleContrast(_ style: HouseStyleTokens) {
    for mode in [style.light, style.dark] {
        // A style that keeps Apple's ground keeps Apple's text colours too.
        guard let ground = mode.ground, let ink = mode.ink, let muted = mode.muted else { continue }
        #expect(ink.contrast(on: ground) >= 7, "\(style.id) text")
        #expect(muted.contrast(on: ground) >= 4.5, "\(style.id) secondary text")
        if let surface = mode.surface {
            #expect(ink.contrast(on: surface) >= 7, "\(style.id) text on a card")
            #expect(muted.contrast(on: surface) >= 4.5, "\(style.id) secondary text on a card")
        }
        if let red = mode.rubricText {
            #expect(red.contrast(on: ground) >= 4.5, "\(style.id) red text")
        }
    }
}

@Test func houseStyleRedIsTheOnlyColour() {
    // Rubric red is the only hue: every other colour is a gray or the night ground.
    let reds: Set<UInt32> = [HouseTokens.Palette.rubric, HouseTokens.Palette.rubricSmall, HouseTokens.Palette.rubricOnDark]
    let night: Set<UInt32> = [HouseTokens.Palette.beltane, HouseTokens.Palette.beltaneDeep]
    for style in HouseTokens.styles {
        for mode in [style.light, style.dark] {
            for ink in [mode.ground, mode.surface, mode.ink, mode.muted, mode.rule].compactMap({ $0 }) {
                let c = ink.rgb()
                #expect(night.contains(ink.hex) || (c.r == c.g && c.g == c.b), "\(style.id) \(ink.hex)")
            }
            for ink in [mode.rubric, mode.rubricText].compactMap({ $0 }) { #expect(reds.contains(ink.hex)) }
        }
    }
}

@Test func houseStyleDefaultsToSystem() {
    #expect(HouseStyleTokens.style("missing").isSystem)
    #expect(HouseStyleTokens.style("system").accentIsRubric == false)
    #expect(HouseTokens.styles.map(\.id) == ["system", "a", "b", "c"])
}
