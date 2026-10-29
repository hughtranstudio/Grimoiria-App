import GrimoireAppKit
import GrimoireCore
import SwiftUI

/// The physical notebooks.
struct VolumeList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(model.data.volumes, selection: $model.selection) { v in
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(v.name)
                Text(subtitle(v)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, Space.xs)
            .tag(Selection.volume(v.id))
            .contextMenu { DeleteButton(id: v.id) }
        }
        .overlay {
            if model.data.volumes.isEmpty {
                ContentUnavailableView("No Volumes", systemImage: "books.vertical",
                                       description: Text("Add each physical notebook, then give records a page."))
            }
        }
        .toolbar {
            ToolbarItem {
                Button("New Volume", systemImage: "plus") { model.sheet = .newVolume }.help("Add a physical notebook")
            }
        }
    }

    private func subtitle(_ v: Volume) -> String {
        let n = model.records(in: v.id).count
        let dates = [v.startedOn, v.endedOn].compactMap { $0.map(DisplayDate.day) }.joined(separator: " – ")
        return [dates, "\(n) record\(n == 1 ? "" : "s")"].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// One volume: its details and every record in it by page, with a page-range filter.
struct VolumeDetail: View {
    @Environment(AppModel.self) private var model
    let volumeId: ULID
    @State private var volume: Volume?
    @State private var from = ""
    @State private var to = ""

    private var range: ClosedRange<Int>? {
        guard let lo = Int(from) else { return nil }
        let hi = Int(to) ?? lo
        return min(lo, hi)...max(lo, hi)
    }

    var body: some View {
        Group {
            if let binding = Binding($volume) { form(binding) } else { ProgressView() }
        }
        .onAppear { volume = model.volume(volumeId) }
        .onChange(of: volume) { _, new in if let new, new != model.volume(volumeId) { model.repository.save(new) } }
    }

    private func form(_ volume: Binding<Volume>) -> some View {
        Form {
            Section {
                TextField("Name", text: volume.name)
                TextField("Started", text: volume.startedOn.orEmpty, prompt: Text("yyyy-mm-dd"))
                TextField("Ended", text: volume.endedOn.orEmpty, prompt: Text("yyyy-mm-dd"))
                Picker("Numbering", selection: volume.pagination) {
                    Text("Pages").tag(Volume.Pagination.page)
                    Text("Folios (12r, 12v)").tag(Volume.Pagination.folio)
                }
                TextField("Notes", text: volume.notes.orEmpty, axis: .vertical)
            }
            Section("Records by page") {
                HStack {
                    Text("Pages")
                    TextField("From", text: $from).frame(width: 60)
                    Text("to")
                    TextField("To", text: $to).frame(width: 60)
                    Spacer()
                }
                let records = model.records(in: volumeId, pages: range)
                if records.isEmpty { Text("No records on these pages.").foregroundStyle(.secondary) }
                ForEach(records, id: \.id) { r in
                    Button { model.reveal(r.id) } label: {
                        HStack {
                            Text("p. \(r.page)").monospacedDigit().frame(width: 72, alignment: .leading)
                            Image(systemName: r.symbol).foregroundStyle(.tint)
                            Text(r.title).lineLimit(1)
                            Spacer()
                            Text(r.date).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(volume.wrappedValue.name)
        .toolbar { ToolbarItem { DeleteToolbarButton(id: volumeId) } }
    }
}

struct NewVolumeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var started = ""

    var body: some View {
        Form {
            Section("New Volume") {
                TextField("Name", text: $name, prompt: Text("Volume III"))
                TextField("Started", text: $started, prompt: Text("yyyy-mm-dd"))
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 420)
        .noInitialFocus()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    let v = Volume(name: name, startedOn: started.isEmpty ? nil : started)
                    model.repository.save(v)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

/// A record shown in a volume's page list.
struct PageRecord {
    let id: ULID
    let page: String
    let title: String
    let symbol: String
    let date: String
    let sortKey: Int
}

extension AppModel {
    /// Entries and inquiries in a volume, by page, optionally only those overlapping `pages`.
    func records(in volumeId: ULID, pages: ClosedRange<Int>? = nil) -> [PageRecord] {
        var out: [PageRecord] = []
        for e in data.entries where e.status == .filed {
            guard let ref = e.physicalRef, ref.volumeId == volumeId, pages.map(ref.overlaps) ?? true else { continue }
            out.append(PageRecord(id: e.id, page: ref.page, title: e.displayTitle, symbol: e.type.symbol,
                                  date: DisplayDate.day(e.occurredAt), sortKey: ref.pageRange?.lowerBound ?? .max))
        }
        for i in data.inquiries {
            guard let ref = i.physicalRef, ref.volumeId == volumeId, pages.map(ref.overlaps) ?? true else { continue }
            out.append(PageRecord(id: i.id, page: ref.page, title: i.question, symbol: "questionmark.bubble",
                                  date: DisplayDate.day(i.askedAt), sortKey: ref.pageRange?.lowerBound ?? .max))
        }
        return out.sorted { ($0.sortKey, $0.page) < ($1.sortKey, $1.page) }
    }
}
