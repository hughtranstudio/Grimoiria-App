import GrimoireAppKit
import GrimoireCore
import SwiftUI

/// Full text, tags (a parent includes its children), type, dates, card names,
/// and “Volume III pp. 40–50”.
struct SearchList: View {
    @Environment(AppModel.self) private var model
    @State private var type: EntryType?
    @State private var useDates = false
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var to = Date.now

    var body: some View {
        @Bindable var model = model
        let hits = model.search(model.searchText, type: type, from: useDates ? from : nil, to: useDates ? to : nil)
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
            }
            .selectionDisabled()
            Section("\(hits.count) result\(hits.count == 1 ? "" : "s")") {
                ForEach(hits, id: \.id) { hit in
                    switch hit {
                    case .entry(let id): if let e = model.entry(id) { EntryRow(entry: e).tag(Selection.entry(id)) }
                    case .inquiry(let id): if let i = model.inquiry(id) { InquiryRow(inquiry: i).tag(Selection.inquiry(id)) }
                    }
                }
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Text, #tag, Volume III pp. 40–50")
    }
}

extension AppModel {
    /// Turns the search field into a GrimoireCore query: “#tag” words are tags,
    /// a page query like “Volume III pp. 40–50” picks a volume and pages, the rest is text.
    func search(_ text: String, type: EntryType? = nil, from: Date? = nil, to: Date? = nil) -> [SearchHit] {
        var q = SearchQuery()
        if let type { q.types = [type] }
        q.from = from.map { Calendar.current.startOfDay(for: $0) }
        q.to = to.flatMap { Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: $0)) }
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
}
