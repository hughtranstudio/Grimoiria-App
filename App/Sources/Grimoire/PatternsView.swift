import Charts
import GrimoireAppKit
import GrimoireCore
import SwiftUI

/// How far back Patterns looks.
enum PatternWindow: String, CaseIterable, Identifiable {
    case all, year, quarter, month
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Time"
        case .year: "Past Year"
        case .quarter: "Past 3 Months"
        case .month: "Past Month"
        }
    }

    var from: Date? {
        let cal = Calendar.current
        switch self {
        case .all: return nil
        case .year: return cal.date(byAdding: .year, value: -1, to: .now)
        case .quarter: return cal.date(byAdding: .month, value: -3, to: .now)
        case .month: return cal.date(byAdding: .month, value: -1, to: .now)
        }
    }
}

extension AppModel {
    /// Counts over everything filed in the chosen window.
    var patterns: Patterns { Patterns(data: data, library: library, from: patternWindow.from) }

    /// Shows the Search page filtered to readings with this card.
    func browse(card deckId: String, _ cardId: String) {
        searchText = ""
        searchHexagram = nil
        searchCard = "\(deckId)/\(cardId)"
        page = .search
    }

    func browse(hexagram n: Int) {
        searchText = ""
        searchCard = nil
        searchHexagram = n
        page = .search
    }

    func browse(tag: TagPath) {
        searchCard = nil
        searchHexagram = nil
        searchText = "#\(tag.path)"
        page = .search
    }
}

/// The middle column: the sections of Patterns.
struct PatternList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let p = model.patterns
        List(selection: $model.selection) {
            Section {
                Label("Overview", systemImage: "chart.bar.xaxis").font(Typo.body).tag(Selection.pattern("overview"))
                ForEach(p.decksUsed, id: \.key) { d in
                    Label(model.library.deck(d.key)?.name ?? d.key, systemImage: "rectangle.stack")
                        .badge(d.count)
                        .font(Typo.body)
                        .tag(Selection.pattern("deck:\(d.key)"))
                }
                if !p.hexagrams.isEmpty {
                    Label("Yi Jing", systemImage: "circle.grid.2x1").badge(p.hexagramCounts().reduce(0) { $0 + $1.count })
                        .font(Typo.body)
                        .tag(Selection.pattern("yijing"))
                }
                Label("Kept Coming Back", systemImage: "arrow.triangle.2.circlepath").badge(p.recurrences().count)
                    .font(Typo.body)
                    .tag(Selection.pattern("recurring"))
                Label("Moon and Planetary Day", systemImage: "moon.stars").font(Typo.body).tag(Selection.pattern("timing"))
                Label("Outcomes", systemImage: "checkmark.seal").badge(p.outcomes().answered)
                    .font(Typo.body)
                    .tag(Selection.pattern("outcomes"))
                Label("Practice and Tags", systemImage: "tag").font(Typo.body).tag(Selection.pattern("tags"))
            } header: {
                Text("\(p.inquiries.count) readings · \(p.entries.count) other entries")
            }
        }
        .overlay {
            if p.inquiries.isEmpty && p.entries.isEmpty {
                ContentUnavailableView("Nothing to Count Yet", systemImage: "chart.bar.xaxis",
                                       description: Text("Patterns appear once you have filed readings and entries."))
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("Period", selection: $model.patternWindow) {
                    ForEach(PatternWindow.allCases) { Text($0.title).tag($0) }
                }
                .help("How far back to count")
            }
        }
        .onAppear { if model.selection == nil { model.selection = .pattern("overview") } }
    }
}

/// The right column: one section's charts and tables.
struct PatternDetail: View {
    @Environment(AppModel.self) private var model
    let section: String

    var body: some View {
        let p = model.patterns
        Form {
            if section == "overview" {
                overview(p)
            } else if section.hasPrefix("deck:") {
                deck(p, String(section.dropFirst(5)))
            } else if section == "yijing" {
                yijing(p)
            } else if section == "recurring" {
                recurring(p)
            } else if section == "timing" {
                timing(p)
            } else if section == "outcomes" {
                outcomes(p)
            } else {
                practice(p)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Patterns · \(model.patternWindow.title)")
    }

    // MARK: Sections

    @ViewBuilder private func overview(_ p: Patterns) -> some View {
        let r = p.report(top: 5)
        Section("Most drawn") {
            if r.decks.isEmpty { Text("No card readings yet.").foregroundStyle(.secondary) }
            ForEach(r.decks, id: \.deckId) { d in
                ForEach(d.topCards.prefix(3), id: \.key) { c in
                    CardCountRow(deckId: d.deckId, cardId: c.key, count: c.count)
                }
            }
        }
        if let top = r.topHexagrams.first {
            Section("Yi Jing") {
                LabeledContent("Most cast", value: "\(top.name), \(top.count)×")
            }
        }
        if let first = r.recurrences.first {
            Section("Kept coming back") {
                LabeledContent(first.name, value: "\(first.readings) readings, \(DisplayDate.day(first.from)) to \(DisplayDate.day(first.to))")
            }
        }
        Section("Outcomes") { OutcomeSummary(stats: p.outcomes()) }
        Section("Activity by month") { TallyChart(rows: p.monthly.map { ($0.key, $0.count) }, vertical: true) }
    }

    @ViewBuilder private func deck(_ p: Patterns, _ deckId: String) -> some View {
        let def = model.library.deck(deckId)
        let counts = p.cardCounts(deckId: deckId)
        Section {
            if let share = p.reversedShare(deckId: deckId) {
                LabeledContent("Reversed", value: "\(Int((share * 100).rounded()))% of draws")
            }
            ForEach(["arcana", "suit", "element"].filter { def?.attributes.contains($0) == true }, id: \.self) { attr in
                let rows = p.attributeCounts(deckId: deckId, attribute: attr).filter { $0.key != "none" }
                if !rows.isEmpty {
                    LabeledContent("By \(attr)") {
                        Text(rows.map { "\($0.key.capitalized) \($0.count)" }.joined(separator: " · ")).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("\(def?.name ?? deckId): \(counts.reduce(0) { $0 + $1.count }) draws")
        }
        Section("Most drawn") {
            TallyChart(rows: counts.prefix(12).map { (def?.card($0.key)?.name ?? $0.key, $0.count) })
        }
        Section("Every card drawn") {
            ForEach(counts, id: \.key) { c in CardCountRow(deckId: deckId, cardId: c.key, count: c.count) }
        }
    }

    @ViewBuilder private func yijing(_ p: Patterns) -> some View {
        let primary = p.hexagramCounts()
        Section("Most cast") {
            TallyChart(rows: primary.prefix(12).map { (p.hexagramName($0.key), $0.count) })
        }
        Section("Changing lines, bottom (1) to top (6)") {
            TallyChart(rows: p.changingLineCounts.map { ("Line \($0.key)", $0.count) }, vertical: true)
        }
        Section("Every hexagram cast") {
            ForEach(primary, id: \.key) { h in
                Button { model.browse(hexagram: h.key) } label: {
                    LabeledContent(p.hexagramName(h.key), value: "\(h.count)×")
                }
                .buttonStyle(.plain)
            }
        }
        let resulting = p.hexagramCounts(role: .resulting)
        if !resulting.isEmpty {
            Section("Changed into") {
                ForEach(resulting, id: \.key) { h in LabeledContent(p.hexagramName(h.key), value: "\(h.count)×") }
            }
        }
    }

    @ViewBuilder private func recurring(_ p: Patterns) -> some View {
        @Bindable var model = model
        let runs = p.recurrences(withinDays: model.recurrenceDays)
        Section {
            Stepper("Within \(model.recurrenceDays) days of each other", value: $model.recurrenceDays, in: 3...365, step: 3)
        } footer: {
            Text("A card or hexagram that came up in two or more separate readings, each within this many days of the last.")
        }
        Section("\(runs.count) found") {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, r in
                Button {
                    switch r.symbol {
                    case .card(let deck, let card): model.browse(card: deck, card)
                    case .hexagram(let n): model.browse(hexagram: n)
                    }
                } label: {
                    LabeledContent(p.name(of: r.symbol)) {
                        Text("\(r.inquiryIds.count) readings, \(DisplayDate.day(r.from)) to \(DisplayDate.day(r.to))")
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func timing(_ p: Patterns) -> some View {
        Section("Moon phase") {
            TallyChart(rows: p.timing(.moonPhase).map { (TimingText.phase(MoonPhase(rawValue: $0.key)!), $0.count) }, vertical: true)
        }
        Section("Planetary day") {
            TallyChart(rows: p.timing(.planetaryDay).map { ($0.key.capitalized, $0.count) }, vertical: true)
        }
        Section("Planetary hour") {
            TallyChart(rows: p.timing(.planetaryHour).map { ($0.key.capitalized, $0.count) }, vertical: true)
        }
        Section {
            TallyChart(rows: p.timing(.moonSign).map { ($0.key.capitalized, $0.count) }, vertical: true)
        } header: {
            Text("Moon sign")
        } footer: {
            Text("Readings by when they were asked, other entries by when they happened. Planetary days and hours need a home location.")
        }
    }

    @ViewBuilder private func outcomes(_ p: Patterns) -> some View {
        Section("All readings") { OutcomeSummary(stats: p.outcomes()) }
        Section("Cards") { OutcomeSummary(stats: p.outcomes(system: .cards)) }
        Section("Yi Jing") { OutcomeSummary(stats: p.outcomes(system: .yijing)) }
        let byConfidence = p.outcomesByConfidence
        if !byConfidence.isEmpty {
            Section {
                ForEach(byConfidence.keys.sorted(), id: \.self) { c in
                    let s = byConfidence[c]!
                    LabeledContent("Confidence \(c)") {
                        Text(s.hitRate.map { "\(Int(($0 * 100).rounded()))% came true, \(s.answered) of \(s.total) answered" }
                             ?? "\(s.answered) of \(s.total) answered")
                    }
                }
            } header: {
                Text("By synthesis confidence")
            } footer: {
                Text("Does feeling sure about a reading match how it turned out?")
            }
        }
    }

    @ViewBuilder private func practice(_ p: Patterns) -> some View {
        Section("Entries by type") {
            TallyChart(rows: p.typeCounts.map { ($0.key.capitalized, $0.count) })
        }
        Section("Tags") {
            let tags = p.tagCounts.sorted { ($1.count, $0.key) < ($0.count, $1.key) }
            if tags.isEmpty { Text("No tags yet.").foregroundStyle(.secondary) }
            ForEach(tags.prefix(40), id: \.key) { t in
                Button { model.browse(tag: t.key) } label: { LabeledContent(t.key.path, value: "\(t.count)") }
                    .buttonStyle(.plain)
            }
        }
    }
}

/// A card with its glyph and count; click shows its readings in Search.
struct CardCountRow: View {
    @Environment(AppModel.self) private var model
    let deckId: String
    let cardId: String
    let count: Int

    var body: some View {
        let card = model.library.deck(deckId)?.card(cardId)
        Button { model.browse(card: deckId, cardId) } label: {
            LabeledContent {
                Text("\(count)×")
            } label: {
                Text([card.flatMap(CardGlyph.symbol), card?.name ?? cardId].compactMap { $0 }.joined(separator: " "))
            }
        }
        .buttonStyle(.plain)
        .help("Show every reading with this card")
    }
}

/// Yes / partly / no / unclear and the share that came true.
struct OutcomeSummary: View {
    let stats: OutcomeStats

    var body: some View {
        if stats.total == 0 {
            Text("No readings.").foregroundStyle(.secondary)
        } else {
            LabeledContent("Answered", value: "\(stats.answered) of \(stats.total)")
            if stats.answered > 0 {
                LabeledContent("Latest outcome") {
                    Text("Yes \(stats.byFulfilled[.yes] ?? 0) · Partly \(stats.byFulfilled[.partly] ?? 0) · No \(stats.byFulfilled[.no] ?? 0) · Unclear \(stats.byFulfilled[.unclear] ?? 0)")
                }
            }
            if let rate = stats.hitRate { LabeledContent("Came true", value: "\(Int((rate * 100).rounded()))%") }
            if let days = stats.medianDaysToFirstOutcome { LabeledContent("First outcome after", value: "\(days) days (median)") }
        }
    }
}

/// A bar chart of labelled counts. Horizontal bars for names, vertical for ordered scales.
struct TallyChart: View {
    let rows: [(String, Int)]
    var vertical = false

    var body: some View {
        if rows.allSatisfy({ $0.1 == 0 }) {
            Text("Nothing to count yet.").foregroundStyle(.secondary)
        } else if vertical {
            Chart(Array(rows.enumerated()), id: \.offset) { _, row in
                BarMark(x: .value("Value", row.0), y: .value("Count", row.1))
                    .foregroundStyle(.tint)
            }
            .frame(height: 160)
        } else {
            Chart(Array(rows.enumerated()), id: \.offset) { _, row in
                BarMark(x: .value("Count", row.1), y: .value("Name", row.0))
                    .foregroundStyle(.tint)
                    .annotation(position: .trailing) { Text("\(row.1)").font(Typo.caption).foregroundStyle(.secondary) }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(max(rows.count, 1)) * 24 + Space.lg)
        }
    }
}
