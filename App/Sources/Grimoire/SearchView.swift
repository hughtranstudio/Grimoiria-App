import GrimoireAppKit
import GrimoireCore
import SwiftUI

/// Full text, tags (a parent includes its children), type, dates, card names,
/// and “Volume III pp. 40–50”. With nothing typed it browses: tags, cards drawn, hexagrams cast.
struct SearchList: View {
    @Environment(AppModel.self) private var model
    @State private var type: EntryType?
    @State private var useDates = false
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var to = Date.now

    private var browsing: Bool {
        model.searchText.trimmingCharacters(in: .whitespaces).isEmpty && model.searchCard == nil && model.searchHexagram == nil
            && type == nil && !useDates
    }

    var body: some View {
        @Bindable var model = model
        let hits = browsing ? [] : model.search(model.searchText, type: type, from: useDates ? from : nil, to: useDates ? to : nil)
        List(selection: $model.selection) {
            Section {
                Picker("Type", selection: $type) {
                    Text("All Types").tag(EntryType?.none)
                    ForEach(EntryType.allCases, id: \.self) { Text($0.title).tag(EntryType?.some($0)) }
                }
                Toggle("Between dates", isOn: $useDates)
                if useDates {
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("To", selection: $to, displayedComponents: .date)
                }
                if let card = model.searchCard {
                    FilterChip(title: "Card: \(model.cardName(card))") { model.searchCard = nil }
                }
                if let n = model.searchHexagram {
                    FilterChip(title: "Hexagram \(n) \(model.library.yijing.hexagram(n)?.name ?? "")") { model.searchHexagram = nil }
                }
            }
            .selectionDisabled()
            if let m = model.searchMeaning {
                MeaningSections(meaning: m)
            }
            if browsing {
                BrowseSections()
            } else {
                Section("\(hits.count) result\(hits.count == 1 ? "" : "s")") {
                    ForEach(hits, id: \.id) { hit in
                        switch hit {
                        case .entry(let id): if let e = model.entry(id) { EntryRow(entry: e).tag(Selection.entry(id)) }
                        case .inquiry(let id): if let i = model.inquiry(id) { InquiryRow(inquiry: i).tag(Selection.inquiry(id)) }
                        }
                    }
                }
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Text, #tag, Volume III pp. 40–50")
    }
}

/// A filter in use, with a button to clear it.
struct FilterChip: View {
    let title: String
    let clear: () -> Void

    var body: some View {
        HStack {
            Label(title, systemImage: "line.3.horizontal.decrease.circle").foregroundStyle(.tint)
            Spacer()
            Button("Clear", systemImage: "xmark.circle.fill", action: clear)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }
}

/// Browse with nothing typed: tags as a tree, cards drawn, hexagrams cast. Each opens its records.
struct BrowseSections: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = Patterns(data: model.data, library: model.library)
        let tags = Dictionary(uniqueKeysWithValues: p.tagCounts.map { ($0.key, $0.count) })
        Section("Tags") {
            if tags.isEmpty { Text("No tags yet.").foregroundStyle(.secondary) }
            ForEach(model.tagTree.children(of: nil), id: \.self) { root in
                TagBrowseRow(tag: root, counts: tags)
            }
        }
        .selectionDisabled()
        Section("Cards drawn") {
            let cards = p.cardCounts()
            if cards.isEmpty { Text("No card readings yet.").foregroundStyle(.secondary) }
            ForEach(cards.prefix(30), id: \.key) { c in
                let parts = c.key.split(separator: "/", maxSplits: 1).map(String.init)
                CardCountRow(deckId: parts[0], cardId: parts[1], count: c.count)
            }
        }
        .selectionDisabled()
        Section("Hexagrams cast") {
            let hex = p.hexagramCounts(role: nil)
            if hex.isEmpty { Text("No Yi Jing casts yet.").foregroundStyle(.secondary) }
            ForEach(hex.prefix(30), id: \.key) { h in
                Button { model.browse(hexagram: h.key) } label: { LabeledContent(p.hexagramName(h.key), value: "\(h.count)×") }
                    .buttonStyle(.plain)
            }
        }
        .selectionDisabled()
    }
}

/// What the filtered card or hexagram has meant in your readings: the summary, your own notes,
/// and what happened when it came true. Each reading opens on click.
struct MeaningSections: View {
    let meaning: PersonalMeaning

    var body: some View {
        Section("What it has meant for you") {
            Text(meaning.summary)
                .font(Typo.body)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(meaning.bookMeaning.sorted { $0.key < $1.key }, id: \.key) { k, v in
                LabeledContent(k.capitalized, value: v.description)
            }
        }
        .selectionDisabled()
        let words = meaning.appearances.filter { !($0.note ?? "").isEmpty }
        if !words.isEmpty {
            Section("In your words") {
                ForEach(words, id: \.inquiryId) { a in
                    MeaningLine(day: a.day, text: a.note ?? "", detail: a.question).tag(Selection.inquiry(a.inquiryId))
                }
            }
        }
        if !meaning.whenItCameTrue.isEmpty {
            Section("When it came true, or partly") {
                ForEach(meaning.whenItCameTrue, id: \.inquiryId) { a in
                    MeaningLine(day: a.day, text: a.outcome?.body ?? "",
                                detail: "\(a.question) · \(a.outcome?.fulfilled == .yes ? "yes" : "partly"), as \(a.position)")
                        .tag(Selection.inquiry(a.inquiryId))
                }
            }
        }
    }
}

/// One dated line under a meaning: what was written, then the reading it belongs to.
struct MeaningLine: View {
    let day: String
    let text: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(text).font(Typo.body).fixedSize(horizontal: false, vertical: true)
            Text("\(DisplayDate.day(day)) · \(detail)").font(Typo.caption).foregroundStyle(.secondary)
        }
    }
}

/// One tag with its use count; children fold out below it.
struct TagBrowseRow: View {
    @Environment(AppModel.self) private var model
    let tag: TagPath
    let counts: [TagPath: Int]

    var body: some View {
        let children = model.tagTree.children(of: tag)
        let row = Button { model.browse(tag: tag) } label: {
            LabeledContent(tag.components.last ?? tag.path, value: "\(counts[tag] ?? 0)")
        }
        .buttonStyle(.plain)
        .help("Show records tagged \(tag.path) or below")
        if children.isEmpty {
            row
        } else {
            DisclosureGroup {
                ForEach(children, id: \.self) { TagBrowseRow(tag: $0, counts: counts) }
            } label: { row }
        }
    }
}

extension AppModel {
    /// Your meaning of the card or hexagram being browsed, if one is.
    var searchMeaning: PersonalMeaning? {
        let p = Patterns(data: data, library: library)
        if let key = searchCard {
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            return parts.count == 2 ? p.meaning(card: parts[1], deckId: parts[0]) : nil
        }
        return searchHexagram.flatMap(p.meaning(hexagram:))
    }

    /// Turns the search field into a GrimoireCore query: “#tag” words are tags,
    /// a page query like “Volume III pp. 40–50” picks a volume and pages, the rest is text.
    func search(_ text: String, type: EntryType? = nil, from: Date? = nil, to: Date? = nil) -> [SearchHit] {
        var q = SearchQuery()
        if let type { q.types = [type] }
        q.from = from.map { Calendar.current.startOfDay(for: $0) }
        q.to = to.flatMap { Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: $0)) }
        q.card = searchCard
        q.hexagram = searchHexagram
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let pq = PageQuery.parse(trimmed), let v = data.volumes.first(where: { pq.matches(volumeName: $0.name) }) {
            q.volumeId = v.id
            q.pages = pq.pages
        } else {
            let words = trimmed.split(separator: " ")
            q.tags = words.filter { $0.hasPrefix("#") }.map { TagPath(String($0.dropFirst())) }.filter { !$0.isEmpty }
            let rest = words.filter { !$0.hasPrefix("#") }.joined(separator: " ")
            q.text = rest.isEmpty ? nil : rest
        }
        return repository.search(q, library: library)
    }

    /// "rws-tarot/maj-16" → "The Tower (Rider–Waite–Smith Tarot)".
    func cardName(_ key: String) -> String {
        let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let deck = library.deck(parts[0]) else { return key }
        return "\(deck.card(parts[1])?.name ?? parts[1]) (\(deck.name))"
    }
}
