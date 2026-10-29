import GrimoireAppKit
import GrimoireCore
import SwiftUI

/// The reflective editor for one entry: common fields, the fields of its
/// type, tags, the physical page, links and backlinks.
struct EntryEditor: View {
    @Environment(AppModel.self) private var model
    let entryId: ULID
    @State private var entry: Entry?

    var body: some View {
        Group {
            if let binding = Binding($entry) {
                form(binding)
            } else {
                ProgressView()
            }
        }
        .onAppear { entry = model.entry(entryId) }
        .onChange(of: entry) { _, new in if let new, new != model.entry(entryId) { model.stage(new) } }
        .onDisappear { model.flushEdits() }
    }

    private func form(_ entry: Binding<Entry>) -> some View {
        Form {
            Section {
                Picker("Type", selection: entry.type) {
                    ForEach(EntryType.creatable, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    if entry.wrappedValue.type == .divination { Text("Divination").tag(EntryType.divination) }
                }
                TextField("Title", text: entry.title.orEmpty, prompt: Text(entry.wrappedValue.displayTitle))
                DatePicker("When", selection: entry.occurredAt.date)
                if let t = entry.wrappedValue.timing {
                    LabeledContent("Timing") { Text(TimingText.line(t)).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
                }
                LabeledContent("Logged") {
                    Text(entry.wrappedValue.mode == .quick ? "Quick" : "Reflective").foregroundStyle(.secondary)
                }
            }
            Section("Text") {
                TextEditor(text: entry.body)
                    .font(.body)
                    .frame(minHeight: 180)
                    .scrollContentBackground(.hidden)
            }
            TypeFieldsSection(type: entry.wrappedValue.type, fields: entry.fields)
            Section("Tags") {
                TagField(tags: entry.tags)
            }
            PhysicalRefSection(ref: entry.physicalRef)
            if let session = Binding(entry.session) {
                SessionSection(session: session) { observation, type in
                    model.makeEntry(from: observation, in: entry.wrappedValue, as: type)
                }
            }
            LinksSection(ownerId: entryId, links: entry.links)
            if let transcript = entry.wrappedValue.transcript, !transcript.isEmpty {
                Section("Transcript") { Text(transcript).textSelection(.enabled).foregroundStyle(.secondary) }
            }
            AttachmentsSection(attachments: entry.attachments)
            Section("Extra notes") {
                TextField("Anything the fields above miss", text: entry.extraNotes.orEmpty, axis: .vertical)
                    .lineLimit(2...)
            }
            let problems = entry.wrappedValue.fields.problems(for: entry.wrappedValue.type)
            if !problems.isEmpty {
                Section { ForEach(problems, id: \.self) { Label($0, systemImage: "exclamationmark.triangle") } }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(entry.wrappedValue.displayTitle)
        .toolbar {
            ToolbarItem { DeleteToolbarButton(id: entryId) }
        }
    }
}

struct DeleteToolbarButton: View {
    @Environment(AppModel.self) private var model
    let id: ULID
    @State private var confirming = false

    var body: some View {
        Button("Delete", systemImage: "trash") { confirming = true }
            .help("Delete this record")
            .confirmationDialog("Delete “\(model.title(for: id))”?", isPresented: $confirming) {
                Button("Delete", role: .destructive) { model.delete(id) }
            } message: {
                Text("This can’t be undone.")
            }
    }
}

/// The fields that belong to one entry type (spec §3.2).
struct TypeFieldsSection: View {
    let type: EntryType
    @Binding var fields: TypeFields

    var body: some View {
        switch type {
        case .ritual:
            Section("Ritual") {
                TextField("Intention", text: $fields.intention.orEmpty, axis: .vertical)
                LabeledContent("Tools") { ListField(items: $fields.tools, prompt: "wand, chalice, incense") }
                TextField("Location", text: $fields.location.orEmpty)
                Stepper("Duration: \(fields.durationMin.map { "\($0) min" } ?? "–")", value: $fields.durationMin.orZero, in: 0...600, step: 5)
                TextField("Steps", text: $fields.steps.orEmpty, axis: .vertical).lineLimit(3...)
                TextField("Result", text: $fields.result.orEmpty, axis: .vertical)
            }
        case .meditation:
            Section("Meditation") {
                TextField("Technique", text: $fields.technique.orEmpty)
                Stepper("Duration: \(fields.durationMin.map { "\($0) min" } ?? "–")", value: $fields.durationMin.orZero, in: 0...600, step: 5)
                ScalePicker(title: "Depth", value: $fields.depth)
                TextField("Observations", text: $fields.observations.orEmpty, axis: .vertical).lineLimit(3...)
            }
        case .vision:
            Section("Vision") {
                ChoicePicker(title: "Setting", value: $fields.setting, choices: ["meditation", "ritual", "spontaneous", "liminal"])
                LabeledContent("Beings") { TagField(tags: $fields.beings.orEmpty, prompt: "entity/…") }
                LabeledContent("Places") { TagField(tags: $fields.places.orEmpty, prompt: "place/…") }
                ScalePicker(title: "Clarity", value: $fields.clarity)
            }
        case .contact:
            Section("Contact") {
                LabeledContent("Being") { TagField(tags: $fields.being.asList, prompt: "entity/…") }
                ChoicePicker(title: "Nature", value: $fields.nature, choices: ["ally", "neutral", "hostile", "unknown"])
                TextField("Communication", text: $fields.communication.orEmpty, axis: .vertical).lineLimit(3...)
            }
        case .omen:
            Section("Omen") {
                ChoicePicker(title: "Observed in", value: $fields.observedIn, choices: ["nature", "people", "media", "body", "other"])
                TextField("Interpretation", text: $fields.interpretation.orEmpty, axis: .vertical)
                Toggle("Resolved", isOn: $fields.resolved.orFalse)
            }
        case .insight:
            Section("Insight") {
                ChoicePicker(title: "Domain", value: $fields.domain, choices: ["magical", "mundane"])
            }
        case .dream:
            Section("Dream") {
                Toggle("Lucid", isOn: $fields.lucid.orFalse)
                Toggle("Recurring", isOn: $fields.recurring.orFalse)
                LabeledContent("Figures") { TagField(tags: $fields.figures.orEmpty, prompt: "entity/…") }
            }
        case .journal, .divination:
            EmptyView()
        }
    }
}

/// A 1–5 scale that can be left blank.
struct ScalePicker: View {
    let title: String
    @Binding var value: Int?

    var body: some View {
        Picker(title, selection: $value) {
            Text("–").tag(Int?.none)
            ForEach(1...5, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
        }
        .pickerStyle(.segmented)
    }
}

/// One of a fixed set of words, or blank.
struct ChoicePicker: View {
    let title: String
    @Binding var value: String?
    let choices: [String]

    var body: some View {
        Picker(title, selection: $value) {
            Text("–").tag(String?.none)
            ForEach(choices, id: \.self) { Text($0.capitalized).tag(String?.some($0)) }
        }
    }
}

/// Hierarchical tags typed on one line, with suggestions from tags already used.
struct TagField: View {
    @Environment(AppModel.self) private var model
    @Binding var tags: [TagPath]
    var prompt = "entity/ally/crow, place/garden"
    @State private var text = ""
    @FocusState private var focused: Bool

    private var suggestions: [TagPath] {
        let fragment = TagInput.fragment(of: text)
        guard focused, !fragment.isEmpty else { return [] }
        return model.tagTree.suggestions(for: fragment, limit: 6).filter { !tags.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            TextField("Tags", text: $text, prompt: Text(prompt))
                .labelsHidden()
                .focused($focused)
                .onSubmit { tags = TagInput.parse(text) }
                .onChange(of: focused) { _, isFocused in if !isFocused { tags = TagInput.parse(text) } }
            if !suggestions.isEmpty {
                HStack(spacing: Space.xs) {
                    ForEach(suggestions, id: \.self) { tag in
                        Button(tag.path) {
                            text = TagInput.complete(text, with: tag)
                            tags = TagInput.parse(text)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .onAppear { text = TagInput.format(tags) }
        .onChange(of: tags) { _, new in if TagInput.parse(text) != new { text = TagInput.format(new) } }
    }
}

/// Where the record sits in a physical notebook.
struct PhysicalRefSection: View {
    @Environment(AppModel.self) private var model
    @Binding var ref: PhysicalRef?

    var body: some View {
        Section("Physical notebook") {
            Picker("Volume", selection: volumeBinding) {
                Text("None").tag(ULID?.none)
                ForEach(model.data.volumes) { v in Text(v.name).tag(ULID?.some(v.id)) }
            }
            if ref != nil {
                TextField("Page", text: Binding(get: { ref?.page ?? "" }, set: { ref?.page = $0 }), prompt: Text("12v, 43–45"))
                PagePhotoRow(photo: Binding(get: { ref?.photo }, set: { ref?.photo = $0 }))
                Toggle("Physical only (photo-first index)", isOn: Binding(get: { ref?.physicalOnly ?? false }, set: { ref?.physicalOnly = $0 }))
            } else if model.data.volumes.isEmpty {
                Button("New Volume…") { model.sheet = .newVolume }
            }
        }
    }

    private var volumeBinding: Binding<ULID?> {
        Binding(
            get: { ref?.volumeId },
            set: { id in
                guard let id else { ref = nil; return }
                if ref == nil { ref = PhysicalRef(volumeId: id, page: "") } else { ref?.volumeId = id }
            }
        )
    }
}

/// Typed links to other records or vault notes, and the records that link here.
struct LinksSection: View {
    @Environment(AppModel.self) private var model
    let ownerId: ULID
    @Binding var links: [Link]
    @State private var vaultPath = ""

    private var targets: [(ULID, String)] {
        let entries = model.timelineEntries.filter { $0.id != ownerId }.map { ($0.id, "\(DisplayDate.day($0.occurredAt))  \($0.displayTitle)") }
        let inquiries = model.data.inquiries.filter { $0.id != ownerId }.map { ($0.id, "\(DisplayDate.day($0.askedAt))  \($0.question)") }
        return (inquiries + entries).sorted { $0.0 > $1.0 }
    }

    var body: some View {
        Section("Links") {
            ForEach(links.indices, id: \.self) { i in
                HStack {
                    Picker("Kind", selection: $links[i].kind) {
                        ForEach(Link.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    if links[i].kind == .vaultNote {
                        TextField("Vault note", text: $links[i].target).labelsHidden()
                        if let url = links[i].obsidianURL {
                            Button("Open in Obsidian", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(url) }
                                .labelStyle(.iconOnly)
                        }
                    } else {
                        Button(ULID(links[i].target).map(model.title(for:)) ?? links[i].target) {
                            if let id = ULID(links[i].target) { model.reveal(id) }
                        }
                        .buttonStyle(.link)
                        .lineLimit(1)
                        Spacer()
                    }
                    Button("Remove", systemImage: "minus.circle") { links.remove(at: i) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
            }
            Menu("Add Link") {
                Menu("To a Record") {
                    ForEach(targets, id: \.0) { id, title in
                        Button(title) { links.append(Link(.related, to: id)) }
                    }
                }
                .disabled(targets.isEmpty)
                Button("To an Obsidian Note") { links.append(Link(.vaultNote, to: "")) }
            }
            .fixedSize()
            let back = model.repository.backlinks(to: ownerId)
            if !back.isEmpty {
                ForEach(back.indices, id: \.self) { i in
                    LabeledContent(back[i].kind.rawValue) {
                        Button(model.title(for: back[i].source)) { model.reveal(back[i].source) }.buttonStyle(.link)
                    }
                }
            }
        }
    }
}

/// A comma-separated list typed on one line, saved when you press Return or leave the field.
struct ListField: View {
    @Binding var items: [String]?
    var prompt = ""
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("List", text: $text, prompt: Text(prompt))
            .labelsHidden()
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onAppear { text = (items ?? []).joined(separator: ", ") }
    }

    private func commit() {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        items = parts.isEmpty ? nil : parts
    }
}

struct AttachmentRow: View {
    let attachment: Attachment

    var body: some View {
        HStack {
            Label(attachment.originalName ?? attachment.path,
                  systemImage: attachment.kind == .audio ? "waveform" : attachment.kind == .image ? "photo" : "doc")
            Spacer()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([Store.attachments.appending(path: attachment.path)])
            }
            .controlSize(.small)
        }
    }
}

// MARK: Bindings for optional fields

extension Binding where Value == String? {
    var orEmpty: Binding<String> {
        Binding<String>(get: { wrappedValue ?? "" }, set: { wrappedValue = $0.isEmpty ? nil : $0 })
    }
}

extension Binding where Value == Int? {
    var orZero: Binding<Int> {
        Binding<Int>(get: { wrappedValue ?? 0 }, set: { wrappedValue = $0 == 0 ? nil : $0 })
    }
}

extension Binding where Value == Bool? {
    var orFalse: Binding<Bool> {
        Binding<Bool>(get: { wrappedValue ?? false }, set: { wrappedValue = $0 })
    }
}

extension Binding where Value == [TagPath]? {
    var orEmpty: Binding<[TagPath]> {
        Binding<[TagPath]>(get: { wrappedValue ?? [] }, set: { wrappedValue = $0.isEmpty ? nil : $0 })
    }
}

extension Binding where Value == TagPath? {
    var asList: Binding<[TagPath]> {
        Binding<[TagPath]>(get: { wrappedValue.map { [$0] } ?? [] }, set: { wrappedValue = $0.first })
    }
}

extension Binding where Value == ZonedDate {
    /// Edits the instant; the time zone becomes the Mac's current zone.
    var date: Binding<Date> {
        Binding<Date>(get: { wrappedValue.instant }, set: { wrappedValue = ZonedDate($0, timeZone: TimeZone.current.identifier) })
    }
}
