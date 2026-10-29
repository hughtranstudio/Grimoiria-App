import AppKit
import CoreText
import GrimoireAppKit
import Observation
import SwiftUI

/// DRAFT: the HT Press house style, in three options for Hugh to compare.
/// The values live in Design/tokens.json (tools/gen-tokens.py makes
/// GrimoireAppKit/HouseTokens.swift). This file turns them into SwiftUI.
/// People pick the style in Settings > Appearance.
///   APP_STYLE=a Grimoire     run with style a, b or c, to compare (also tools/snap.sh)
@Observable
final class HouseStyleStore {
    static let shared = HouseStyleStore()

    /// The style the app ships with: A · Codex, Hugh's pick (10-29-2026).
    static let defaultID = "a"

    var styleID: String {
        didSet { UserDefaults.standard.set(styleID, forKey: "appearance.style") }
    }

    var style: HouseStyleTokens { HouseStyleTokens.style(styleID) }

    private init() {
        HouseFonts.register()
        styleID = ProcessInfo.processInfo.environment["APP_STYLE"]
            ?? UserDefaults.standard.string(forKey: "appearance.style") ?? Self.defaultID
    }
}

/// Registers the bundled Garamonds (Resources/Fonts, copied by build.sh).
/// Without them the house styles fall back to Apple's serif, New York.
enum HouseFonts {
    static func register() {
        guard let folder = Bundle.main.resourceURL?.appending(path: "Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        let fonts = files.filter { $0.pathExtension == "ttf" } as CFArray
        CTFontManagerRegisterFontURLs(fonts, .process, true, nil)
        families = nil
    }

    private static var families: Set<String>?

    static func installed(_ family: String) -> Bool {
        if families == nil { families = Set(NSFontManager.shared.availableFontFamilies) }
        return families?.contains(family) ?? false
    }
}

/// Colour tokens for views. Under the System style each one is Apple's own.
/// Never hard-code a house colour in a view.
enum House {
    private static var style: HouseStyleTokens { HouseStyleStore.shared.style }

    private static func color(_ pick: (HouseMode) -> HouseInk?) -> Color? {
        let light = pick(style.light), dark = pick(style.dark)
        guard let light, let dark else { return nil }
        return Color(nsColor: NSColor(name: nil) { appearance in
            let ink = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(hex: ink.hex).withAlphaComponent(ink.alpha)
        })
    }

    /// The page behind content. nil keeps Apple's window background.
    static var ground: Color? { color(\.ground) }
    /// Cards and grouped rows on the page.
    static var surface: Color? { color(\.surface) }
    /// Text.
    static var ink: AnyShapeStyle { color(\.ink).map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary) }
    /// Secondary text.
    static var muted: AnyShapeStyle { color(\.muted).map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary) }
    /// Hairlines and dividers.
    static var rule: AnyShapeStyle { color(\.rule).map { AnyShapeStyle($0) } ?? AnyShapeStyle(.separator) }
    /// Rubric red for marks, or nil to keep the chosen accent.
    static var rubric: Color? { color(\.rubric) }
    /// Rubric red for small text.
    static var rubricText: Color? { color(\.rubricText) }
    /// Corner radius for drawn cards and tags.
    static func radius(else fallback: CGFloat) -> CGFloat { style.radius.map { CGFloat($0) } ?? fallback }
    /// Pages draw their own ground (style A and C).
    static var drawsGround: Bool { style.light.ground != nil }
}

/// Type tokens. Each matches one of Apple's text styles and scales with it.
/// Under the System style each one is Apple's own.
enum Typo {
    private static var style: HouseStyleTokens { HouseStyleStore.shared.style }

    private typealias S = HouseTokens.Size

    /// Writing: entry text, transcripts, questions.
    static var body: Font { serifFallback(style.textFont, S.body, .body, .body) }
    /// Labels outside your writing: the sidebar, list headings. Apple's under B.
    static var label: Font { serifFallback(style.labelFont, S.body, .body, .body) }
    static var callout: Font { serifFallback(style.labelFont, S.callout, .callout, .callout) }
    static var caption: Font { serifFallback(style.labelFont, S.caption, .caption, .caption) }
    static var caption2: Font { serifFallback(style.labelFont, S.caption - 1, .caption2, .caption2) }
    static var headline: Font { serifFallback(style.textFont, S.headline, .headline, .headline).weight(.semibold) }
    static var title3: Font { serifFallback(style.titleFont, S.title3, .title3, .title3) }
    static var title2: Font { serifFallback(style.titleFont, S.title2, .title2, .title2) }
    static var title: Font { serifFallback(style.titleFont, S.title, .title, .title).weight(.medium) }

    /// Titles in tracked capitals (styles A and C).
    static var titleCaps: Bool { style.titleCaps }
    static func tracking(for size: Double) -> CGFloat { titleCaps ? CGFloat(size * S.titleTracking) : 0 }

    /// The house font when it is installed, else Apple's serif at the same size.
    private static func serifFallback(_ family: String?, _ size: Double, _ apple: Font, _ relative: Font.TextStyle) -> Font {
        guard let family else { return apple }
        if HouseFonts.installed(family) { return .custom(family, size: size, relativeTo: relative) }
        return .system(relative, design: .serif)
    }
}

/// Motion tokens. Red stamps, everything else arrives like ink.
enum Motion {
    private static func animation(_ m: HouseMotion) -> Animation {
        .timingCurve(m.curve.0, m.curve.1, m.curve.2, m.curve.3, duration: m.seconds)
    }

    /// Things arriving: notices, sheets of content. Expo-out under a house style.
    static var arrive: Animation {
        HouseStyleStore.shared.style.accentIsRubric ? animation(HouseTokens.Motion.arrive) : .default
    }

    static var stamp: Animation { animation(HouseTokens.Motion.stamp) }
}

extension View {
    /// A grouped Form or List as a printed page: the house ground, the house
    /// text font and colour. Put it after `.formStyle(.grouped)`.
    func pressPage() -> some View {
        modifier(PressPage())
    }

    /// A title set in the house title face: tracked capitals under A and C.
    func pressTitle(size: Double = HouseTokens.Size.title2) -> some View {
        modifier(PressTitle(size: size))
    }
}

private struct PressPage: ViewModifier {
    private var store = HouseStyleStore.shared

    @ViewBuilder
    func body(content: Content) -> some View {
        if store.style.isSystem {
            content
        } else if let ground = House.ground {
            content
                .font(Typo.body)
                .foregroundStyle(House.ink)
                .scrollContentBackground(.hidden)
                .background(ground)
        } else {
            content.font(Typo.body)
        }
    }
}

private struct PressTitle: ViewModifier {
    let size: Double

    func body(content: Content) -> some View {
        content
            .font(size >= HouseTokens.Size.title ? Typo.title : Typo.title2)
            .textCase(Typo.titleCaps ? Text.Case.uppercase : nil)
            .tracking(Typo.tracking(for: size))
    }
}

/// Applies the house style below a scene's root: the accent (rubric red under
/// a house style), the forced night mode of style C. Used by `.themed()`.
struct HouseStyled: ViewModifier {
    private var store = HouseStyleStore.shared

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(store.style.forceDark ? ColorScheme.dark : nil)
    }
}

/// The head of a record page under a house style: a small red line of type
/// and date, the title in the title face, and a short rubric rule. Draws
/// nothing under the System style, where the window title says it.
/// Woodcut marks (Figma "HT Brand") go to the left of the kicker once exported.
struct PressHeading: View {
    let kicker: String
    let title: String
    private var store = HouseStyleStore.shared

    init(kicker: String, title: String) {
        self.kicker = kicker
        self.title = title
    }

    var body: some View {
        if !store.style.isSystem {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(kicker)
                    .font(Typo.caption)
                    .textCase(.uppercase)
                    .tracking(Typo.tracking(for: HouseTokens.Size.caption))
                    .foregroundStyle(Palette.accentText)
                Text(title)
                    .pressTitle()
                    .foregroundStyle(House.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle()
                    .fill(Palette.accent)
                    .frame(width: 48, height: 2)
            }
            .padding(.bottom, Space.sm)
            .textSelection(.enabled)
            .accessibilityElement(children: .combine)
        }
    }
}
