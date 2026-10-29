import GrimoireAppKit
import GrimoireCore
import SwiftUI

/// The middle column: planets, signs, elements and trigrams, filtered by what you type
/// (“iron”, “tuesday”, “head”, “♂”).
struct CorrespondenceList: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""

    private static let titles = ["planet": "Planets", "sign": "Signs", "element": "Elements", "trigram": "Trigrams"]

    var body: some View {
        @Bindable var model = model
        let table = model.library.correspondences
        let hits = table?.search(text) ?? []
        List(selection: $model.selection) {
            ForEach(Correspondences.kinds, id: \.self) { kind in
                let rows = hits.filter { $0.kind == kind }
                if !rows.isEmpty {
                    Section(Self.titles[kind] ?? kind.capitalized) {
                        ForEach(rows) { e in
                            Label {
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    Text(e.name)
                                    Text(summary(e)).font(Typo.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            } icon: {
                                Text(e.glyph ?? "•").foregroundStyle(.tint)
                            }
                            .padding(.vertical, Space.xs)
                            .tag(Selection.correspondence(e.id))
                        }
                    }
                }
            }
        }
        .searchable(text: $text, placement: .toolbar, prompt: "Iron, Tuesday, head, ♂")
        .overlay {
            if table == nil {
                ContentUnavailableView("No Correspondences", systemImage: "tablecells",
                                       description: Text("correspondences.json is missing from the Definitions folder."))
            } else if hits.isEmpty {
                ContentUnavailableView.search(text: text)
            }
        }
        .footer(table?.source)
    }

    private func summary(_ e: Correspondences.Entry) -> String {
        e.fields.prefix(3).map { $0.values.joined(separator: ", ") }.joined(separator: " · ")
    }
}

private extension View {
    /// The table's sources under the list.
    func footer(_ source: String?) -> some View {
        safeAreaInset(edge: .bottom) {
            if let source {
                Text(source)
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
                    .padding(Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
        }
    }
}

/// One planet, sign, element or trigram: its table, the cards and hexagrams that carry it,
/// what points to it, and for a planet its next hours.
struct CorrespondenceDetail: View {
    @Environment(AppModel.self) private var model
    let key: String

    var body: some View {
        if let table = model.library.correspondences, let e = table.entry(key) {
            Form {
                Section {
                    ForEach(e.fields, id: \.label) { f in
                        LabeledContent(f.label) {
                            Text(f.values.joined(separator: ", ")).multilineTextAlignment(.trailing).textSelection(.enabled)
                        }
                    }
                } header: {
                    Text("\(e.glyph.map { "\($0) " } ?? "")\(e.name)")
                }
                let cards = model.library.cards(for: e)
                if !cards.isEmpty {
                    Section("Cards") {
                        ForEach(cards, id: \.card.id) { pair in
                            CardCountRow(deckId: pair.deck.id, cardId: pair.card.id,
                                         count: model.patterns.cardCounts(deckId: pair.deck.id).first { $0.key == pair.card.id }?.count ?? 0)
                        }
                    }
                }
                if e.kind == "trigram" {
                    Section("Hexagrams with \(e.name) below or above") {
                        ForEach(model.library.hexagrams(withTrigram: e.key), id: \.number) { h in
                            Button { model.browse(hexagram: h.number) } label: {
                                LabeledContent("\(h.number) \(h.name)", value: h.lower == e.key && h.upper == e.key ? "doubled" : h.lower == e.key ? "below" : "above")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                let links = (e.related.compactMap(table.entry) + table.mentions(of: e)).reduce(into: [Correspondences.Entry]()) { list, x in
                    if !list.contains(x) { list.append(x) }
                }
                if !links.isEmpty {
                    Section("See also") {
                        ForEach(links) { r in
                            Button { model.selection = .correspondence(r.id) } label: {
                                LabeledContent("\(r.glyph.map { "\($0) " } ?? "")\(r.name)", value: r.kind.capitalized)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if e.kind == "planet", let planet = Planet(rawValue: e.key) {
                    PlanetHoursSection(planet: planet)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(e.name)
        } else {
            ContentUnavailableView("Nothing Selected", systemImage: "tablecells")
        }
    }
}

/// The next hours of a planet at home, and those on its own day. Right-click to plan a ritual.
struct PlanetHoursSection: View {
    @Environment(AppModel.self) private var model
    let planet: Planet
    @State private var onItsDay = false

    var body: some View {
        Section {
            if let home = model.settings.home {
                Toggle("Only on its own day", isOn: $onItsDay)
                let hours = RitualCalendar.nextHours(of: planet, after: .now, location: home, zone: .current, onItsDay: onItsDay, limit: 6)
                ForEach(hours, id: \.start) { h in
                    LabeledContent(h.start.formatted(.dateTime.weekday(.wide).month().day()),
                                   value: "\(h.start.formatted(date: .omitted, time: .shortened)) – \(h.end.formatted(date: .omitted, time: .shortened))")
                        .contextMenu {
                            Button("New Ritual in This Hour") { model.newRitual(at: h.start, intention: "Hour of \(planet.rawValue.capitalized)") }
                        }
                }
            } else {
                Text("Set a home location in Settings > General to see planetary hours.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Next hours of \(planet.rawValue.capitalized)")
        } footer: {
            Text("Right-click an hour to plan a ritual in it.")
        }
    }
}
