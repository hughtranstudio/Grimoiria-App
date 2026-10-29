import AVFoundation
import GrimoireAppKit
import GrimoireCore
import SwiftUI

/// Captures waiting to be checked. Nothing here is filed until Confirm.
struct InboxList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            let problems = IngestCoordinator.shared.problems + model.importProblems
            if !problems.isEmpty {
                Section("Problems") {
                    ForEach(problems, id: \.self) {
                        Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
                .selectionDisabled()
            }
            ForEach(model.data.inbox.sorted { $0.entry.occurredAt.instant > $1.entry.occurredAt.instant }) { item in
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Image(systemName: item.draft == nil ? item.entry.type.symbol : "suit.diamond").foregroundStyle(.tint).frame(width: 20)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(item.draft?.question.value ?? item.entry.displayTitle).lineLimit(2)
                        HStack(spacing: Space.sm) {
                            Text(DisplayDate.dayTime(item.entry.occurredAt))
                            if let d = item.draft, d.weakest < .high { Text("Check \(d.weakest.rawValue) fields") }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, Space.xs)
                .tag(Selection.inbox(item.id))
            }
        }
        .overlay {
            if model.data.inbox.isEmpty && IngestCoordinator.shared.problems.isEmpty && model.importProblems.isEmpty {
                ContentUnavailableView("Inbox Is Empty", systemImage: "tray",
                                       description: Text("Phone captures and imported documents appear here to check before they are filed."))
            }
        }
        // Drop downloaded Google Docs, Markdown or text files here to import them.
        .dropDestination(for: URL.self) { urls, _ in
            let docs = urls.filter { $0.hasDirectoryPath || ImportDocument.supportedExtensions[$0.pathExtension.lowercased()] != nil }
            guard !docs.isEmpty else { return false }
            model.importDocuments(docs, tags: [TagPath("source/import")])
            return true
        }
        .toolbar {
            ToolbarItem {
                Button("Import Documents…", systemImage: "doc.badge.plus") { model.sheet = .importDocuments }
                    .help("Import downloaded Google Docs, Markdown or text files (Command-Shift-I)")
            }
            ToolbarItem {
                Button("Check Folders", systemImage: "arrow.clockwise") { IngestCoordinator.shared.scanAll() }
                    .help("Look for new captures now (Command-Shift-R)")
            }
        }
    }
}

/// Left: transcript and audio. Right: the parsed draft, every field correctable.
struct InboxDetail: View {
    @Environment(AppModel.self) private var model
    let itemId: ULID
    @State private var item: InboxItem?
    @State private var draft = DraftReading()
    @State private var entryType: EntryType = .journal
    @State private var error: String?
    @State private var transcribing = false

    var body: some View {
        Group {
            if let item {
                HSplitView {
                    transcript(item).frame(minWidth: 260, idealWidth: 320)
                    form(item).frame(minWidth: 380)
                }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            item = model.data.inbox.first { $0.id == itemId }
            draft = item?.draft ?? DraftReading()
            entryType = item?.entry.type ?? .journal
        }
        .onDisappear { saveSession() }
        .navigationTitle(item?.entry.session == nil ? "Check Capture" : "Check Session")
        .toolbar {
            ToolbarItem {
                Button("Confirm", systemImage: "checkmark.circle") { confirm() }
                    .buttonStyle(.borderedProminent)
                    .disabled(missing)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("File this capture (Command-Return)")
            }
        }
    }

    /// Confirm waits until every card and every Yi Jing cast is filled in.
    private var missing: Bool {
        draft.divinations.contains { d in
            d.system == .yijing ? (d.cast?.lines.value?.count != 6) : (d.deckId.value == nil || d.draws.contains { $0.cardId.value == nil })
        }
    }

    private func transcript(_ item: InboxItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                if let audio = item.entry.attachments.first(where: { $0.kind == .audio }) {
                    AudioPlayerRow(url: Store.attachments.appending(path: audio.path))
                    Button(transcribing ? "Transcribing…" : "Transcribe Again", systemImage: "waveform.badge.magnifyingglass") {
                        transcribing = true
                        Task {
                            if let updated = await model.retranscribe(itemId) {
                                self.item = updated
                                draft = updated.draft ?? DraftReading()
                            }
                            transcribing = false
                        }
                    }
                    .disabled(transcribing)
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .help("Run speech to text on this recording again and re-read the cards (Command-Shift-T)")
                }
                if item.entry.session != nil {
                    if let t = item.entry.transcript, !t.isEmpty {
                        Text(t).textSelection(.enabled)
                    } else {
                        Label("No transcript yet. Listen to the audio, or Transcribe Again once the speech model is installed.", systemImage: "waveform.slash")
                            .foregroundStyle(.secondary)
                    }
                } else if item.entry.body.isEmpty {
                    Label("No transcript. Listen to the audio and fill in the fields.", systemImage: "waveform.slash")
                        .foregroundStyle(.secondary)
                } else {
                    Text(item.entry.body).textSelection(.enabled)
                }
                if !draft.unparsed.isEmpty {
                    Text("Words not placed").font(.caption).foregroundStyle(.secondary)
                    FlowChips(words: draft.unparsed)
                }
                Text("From \(item.source) · \(DisplayDate.dayTime(item.entry.occurredAt))").font(.caption).foregroundStyle(.secondary)
            }
            .padding(Space.margin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func form(_ item: InboxItem) -> some View {
        Form {
            if !draft.warnings.isEmpty || !(item.notes ?? []).isEmpty {
                Section {
                    ForEach(draft.warnings + (item.notes ?? []), id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
            }
            if let error {
                Section { Label(error, systemImage: "xmark.octagon").foregroundStyle(.red) }
            }
            if draft.divinations.isEmpty {
                Section("File as") {
                    Picker("Type", selection: $entryType) {
                        ForEach(EntryType.creatable, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                }
            } else {
                Section("Question") {
                    TextField("Question", text: Binding(get: { draft.question.value ?? "" },
                                                        set: { draft.question.value = $0.isEmpty ? nil : $0 }), axis: .vertical)
                        .flagged(draft.question.confidence < .high && draft.question.value != nil)
                }
            }
            if item.entry.session != nil {
                SessionSection(session: Binding(get: { self.item?.entry.session ?? item.entry.session! },
                                                set: { self.item?.entry.session = $0 }))
            }
            ForEach(draft.divinations.indices, id: \.self) { i in
                DraftDivinationSection(divination: $draft.divinations[i], number: i + 1) { draft.divinations.remove(at: i) }
            }
            Section {
                HStack {
                    Button("Add Card Reading") {
                        draft.divinations.append(DraftDivination(system: .cards, deckId: Parsed("rws-tarot", confidence: .high),
                                                                 spreadId: Parsed("three-card", confidence: .high)))
                    }
                    Button("Add Yi Jing Cast") {
                        draft.divinations.append(DraftDivination(system: .yijing, cast: DraftCast(lines: .missing, method: .coins)))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Keeps the session's checked observations, so leaving and coming back loses nothing.
    private func saveSession() {
        guard let item, item.entry.session != nil,
              let stored = model.data.inbox.first(where: { $0.id == itemId }), stored != item else { return }
        model.updateInbox(item)
    }

    private func confirm() {
        saveSession()
        do {
            let id = try model.confirm(itemId, corrected: draft.divinations.isEmpty ? nil : draft, entryType: draft.divinations.isEmpty ? entryType : nil)
            error = nil
            model.reveal(id)
        } catch {
            self.error = String(describing: error)
        }
    }
}

/// One parsed divination: deck, spread and each card, or the six lines.
struct DraftDivinationSection: View {
    @Environment(AppModel.self) private var model
    @Binding var divination: DraftDivination
    let number: Int
    let remove: () -> Void
    @State private var digits = ""

    var body: some View {
        Section {
            if divination.system == .yijing {
                TextField("Lines, bottom to top", text: $digits, prompt: Text("789677"))
                    .flagged(divination.cast?.lines.confidence ?? .missing < .high)
                    .onAppear { digits = divination.cast?.lines.value?.map(String.init).joined() ?? "" }
                    .onChange(of: digits) { _, new in
                        let lines = new.compactMap(\.wholeNumberValue)
                        let ok = lines.count == 6 && lines.allSatisfy { (6...9).contains($0) }
                        divination.cast = DraftCast(lines: Parsed(ok ? lines : nil, heard: divination.cast?.lines.heard, confidence: ok ? .high : .missing),
                                                    method: divination.cast?.method ?? .coins)
                    }
                if let lines = divination.cast?.lines.value, let cast = try? YiJingCast(lines: lines) { CastDrawing(cast: cast) }
            } else {
                Picker("Deck", selection: Binding(get: { divination.deckId.value }, set: { divination.deckId = Parsed($0, heard: divination.deckId.heard, confidence: .high) })) {
                    Text("Choose a deck").tag(String?.none)
                    ForEach(model.library.decks.filter { $0.status != .template }) { Text($0.name).tag(String?.some($0.id)) }
                }
                .flagged(divination.deckId.confidence < .high)
                Picker("Spread", selection: Binding(get: { divination.spreadId.value }, set: { divination.spreadId = Parsed($0, heard: divination.spreadId.heard, confidence: .high) })) {
                    Text("Freeform").tag(String?.none)
                    ForEach(model.library.spreads) { Text($0.name).tag(String?.some($0.id)) }
                }
                .flagged(divination.spreadId.confidence < .high)
                let deck = divination.deckId.value.flatMap(model.library.deck)
                let spread = divination.spreadId.value.flatMap(model.library.spread) ?? model.library.freeform
                ForEach(divination.draws.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: Space.sm) {
                        HStack {
                            Picker("Position", selection: $divination.draws[i].positionKey) {
                                ForEach(positions(spread, count: divination.draws.count), id: \.self) { Text(spread.label(for: $0)).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                            CardPicker(cardId: Binding(get: { divination.draws[i].cardId.value ?? "" },
                                                       set: { divination.draws[i].cardId = Parsed($0.isEmpty ? nil : $0, heard: divination.draws[i].cardId.heard,
                                                                                                   confidence: $0.isEmpty ? .missing : .high) }),
                                       deck: deck)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .flagged(divination.draws[i].cardId.confidence < .high)
                        }
                        HStack {
                            Toggle("Reversed", isOn: Binding(get: { divination.draws[i].orientation.value == .reversed },
                                                             set: { divination.draws[i].orientation = Parsed($0 ? .reversed : .upright, confidence: .high) }))
                                .toggleStyle(.checkbox)
                                .flagged(divination.draws[i].orientation.confidence < .high)
                            if let heard = divination.draws[i].cardId.heard {
                                Text("Heard “\(heard)”").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button("Remove", systemImage: "minus.circle") { divination.draws.remove(at: i) }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, Space.xs)
                }
                Button("Add Card", systemImage: "plus") {
                    divination.draws.append(DraftDraw(cardId: .missing, orientation: Parsed(.upright, confidence: .high),
                                                      positionKey: spread.positionKey(at: divination.draws.count)))
                }
            }
        } header: {
            HStack {
                Text(divination.system == .yijing ? "\(number). Yi Jing" : "\(number). Cards")
                Spacer()
                Button("Remove", systemImage: "trash", role: .destructive, action: remove).labelStyle(.iconOnly).buttonStyle(.borderless)
            }
        }
    }

    private func positions(_ spread: SpreadDefinition, count: Int) -> [String] {
        let keys = spread.positions.map(\.key)
        let used = divination.draws.map(\.positionKey)
        var all = keys
        for k in used where !all.contains(k) { all.append(k) }
        if keys.isEmpty { for i in 0..<max(count, 1) where !all.contains(spread.positionKey(at: i)) { all.append(spread.positionKey(at: i)) } }
        return all
    }
}

extension View {
    /// An accent outline on fields the parser was not sure about.
    func flagged(_ on: Bool) -> some View {
        padding(on ? 2 : 0)
            .overlay {
                if on { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2).allowsHitTesting(false) }
            }
    }
}

struct FlowChips: View {
    let words: [String]

    var body: some View {
        FlowLayout(spacing: Space.xs) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, w in
                Text(w)
                    .font(.callout)
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: .capsule)
            }
        }
    }
}

/// Wraps its children onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
        }
        return CGSize(width: width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += line + spacing; line = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

struct AudioPlayerRow: View {
    let url: URL
    @State private var player: AVAudioPlayer?
    @State private var playing = false

    var body: some View {
        HStack {
            Button(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill") {
                if player == nil { player = try? AVAudioPlayer(contentsOf: url) }
                if playing { player?.pause() } else { player?.play() }
                playing.toggle()
            }
            .disabled(!FileManager.default.fileExists(atPath: url.path))
            Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .onDisappear { player?.stop() }
    }
}

extension AppModel {
    /// The only path from the Inbox to filed records. Returns the filed record to show.
    @discardableResult
    func confirm(_ itemId: ULID, corrected: DraftReading?, entryType: EntryType?) throws -> ULID {
        let result = try repository.confirm(itemId, corrected: corrected, entryType: entryType, library: library,
                                            reminder: settings.reminderDefault)
        ReminderScheduler.shared.refresh()
        if settings.exportAfterConfirm, !settings.vaultPath.isEmpty { exportNow(quiet: true) }
        show("Filed")
        return result.inquiry?.id ?? result.entry.id
    }
}
