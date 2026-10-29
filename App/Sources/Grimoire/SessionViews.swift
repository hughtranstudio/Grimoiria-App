import AppKit
import GrimoireAppKit
import GrimoireCore
import SwiftUI

/// The Session window (File > Record Session…, Option-Command-R): set up, run the clock with the
/// microphone on, then write the closing notes and send it to the Inbox.
struct SessionWindow: View {
    @Environment(AppModel.self) private var model
    @State private var controller = SessionController.shared

    var body: some View {
        Group {
            switch controller.stage {
            case .setup: SessionSetupForm(controller: controller)
            case .running: SessionRunningView(controller: controller)
            case .finishing, .saving: SessionFinishForm(controller: controller)
            }
        }
        .frame(width: 480)
        .noInitialFocus()
        .navigationTitle(title)
    }

    private var title: String {
        switch controller.stage {
        case .setup: "New Session"
        case .running: "\(controller.type.title) in Progress"
        case .finishing, .saving: "Close the \(controller.type.title)"
        }
    }
}

struct SessionSetupForm: View {
    @Environment(AppModel.self) private var model
    @Bindable var controller: SessionController
    @State private var starting = false

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $controller.type) {
                    ForEach(EntryType.sessionTypes, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("Intention", text: $controller.intention, prompt: Text("Visit the inner library"), axis: .vertical)
                TextField("Technique", text: $controller.technique, prompt: Text("Inner flame, stillness, pathworking…"))
                TextField("Tags", text: $controller.tagsText, prompt: Text("practice/quareia, place/temple"))
            }
            Section("Going in") {
                ScalePicker(title: "Energy", value: $controller.before.energy)
                ScalePicker(title: "Calm", value: $controller.before.calm)
                ScalePicker(title: "Focus", value: $controller.before.focus)
            }
            Section {
                Toggle("Record audio", isOn: $controller.recordAudio)
                Text("Speak what you see and meet; it is transcribed and split into timed observations when you finish. Press Command-K to drop a marker without opening your eyes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Start", systemImage: "record.circle") {
                        starting = true
                        Task {
                            await controller.start(model: model)
                            starting = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(starting)
                }
            }
        }
        .formStyle(.grouped)
        .fitsContent()
    }
}

struct SessionRunningView: View {
    @Environment(AppModel.self) private var model
    @Bindable var controller: SessionController
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(alignment: .firstTextBaseline) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(SessionText.clock(controller.elapsed(at: context.date)))
                        .font(.largeTitle.monospacedDigit())
                }
                Spacer()
                if controller.audioURL != nil {
                    Label("Recording", systemImage: "record.circle.fill").foregroundStyle(.red)
                } else {
                    Label("No audio", systemImage: "mic.slash").foregroundStyle(.secondary)
                }
            }
            if let problem = controller.micProblem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            }
            Picker("Phase", selection: Binding(get: { controller.recorder?.currentPhase ?? .opening }, set: { controller.setPhase($0) })) {
                ForEach(SessionPhase.live, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack {
                Button("Mark", systemImage: "bookmark") { controller.mark() }
                    .help("Drop a marker here to fill in later (Command-K)")
                Spacer()
                Button("End Session", systemImage: "stop.circle") { controller.end() }
                    .buttonStyle(.borderedProminent)
                    .help("Stop the clock and the microphone (Option-Command-E)")
            }

            ObservationInput(controller: controller, typing: $typing)

            if let session = controller.session, !session.observations.isEmpty {
                Divider()
                ForEach(Array(session.observations.suffix(6).reversed())) { o in
                    ObservationLine(observation: o) { controller.removeObservation(o.id) }
                }
            }
        }
        .padding(Space.margin)
        .gridArea("session")
    }
}

/// Kind, text and tags for one observation; Return adds it.
struct ObservationInput: View {
    @Environment(AppModel.self) private var model
    @Bindable var controller: SessionController
    var typing: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                Picker("Kind", selection: $controller.kind) {
                    ForEach(ObservationKind.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .help("Control-Option-I imagery, E entity, P place, Y symbol, M message, H sound, S sensation, F feeling, T insight, O omen, V event, A action, N note")
                TextField("Observation", text: $controller.text, prompt: Text(controller.stage == .running ? "What you see, meet or feel" : "Something you remember now"))
                    .textFieldStyle(.roundedBorder)
                    .focused(typing)
                    .onSubmit { controller.addObservation(vocabulary: model.vocabulary) }
            }
            TextField("Tags", text: $controller.observationTags, prompt: Text("Tags, or leave empty to suggest them from the words"))
                .textFieldStyle(.roundedBorder)
                .onSubmit { controller.addObservation(vocabulary: model.vocabulary) }
        }
    }
}

/// One observation as a read-only line, with a remove button.
struct ObservationLine: View {
    let observation: Observation
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Text(SessionText.clock(observation.offset)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Image(systemName: observation.kind.symbol).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(observation.text.isEmpty ? "Marker" : observation.text)
                    .foregroundStyle(observation.text.isEmpty ? .secondary : .primary)
                if !observation.tags.isEmpty {
                    Text(TagInput.format(observation.tags)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Remove", systemImage: "minus.circle", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }
}

struct SessionFinishForm: View {
    @Environment(AppModel.self) private var model
    @Bindable var controller: SessionController
    @FocusState private var typing: Bool
    @State private var confirmingDiscard = false

    var body: some View {
        Form {
            if let session = controller.session {
                Section {
                    LabeledContent("Session") { Text(SessionText.summary(session)).foregroundStyle(.secondary) }
                    if controller.audioURL != nil {
                        Text("The recording is transcribed when you send it to the Inbox; what you said becomes observations to check there.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Coming out") {
                ScalePicker(title: "Energy", value: $controller.after.energy)
                ScalePicker(title: "Calm", value: $controller.after.calm)
                ScalePicker(title: "Focus", value: $controller.after.focus)
                TextField("Outcome", text: $controller.outcome, prompt: Text("How it ended, in a sentence"), axis: .vertical)
                Toggle("Stopped early or disturbed", isOn: $controller.interrupted)
            }
            Section("Anything else you remember") {
                ObservationInput(controller: controller, typing: $typing)
                if let session = controller.session {
                    ForEach(session.observations) { o in
                        ObservationLine(observation: o) { controller.removeObservation(o.id) }
                    }
                }
            }
            Section {
                HStack {
                    Button("Discard…", role: .destructive) { confirmingDiscard = true }
                    Spacer()
                    if controller.stage == .saving { ProgressView().controlSize(.small) }
                    Button("Send to Inbox", systemImage: "tray.and.arrow.down") {
                        Task { await controller.save(model: model) }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(controller.stage == .saving)
                }
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .confirmationDialog("Discard this session and its recording?", isPresented: $confirmingDiscard) {
            Button("Discard", role: .destructive) { controller.discard() }
        } message: {
            Text("This can’t be undone.")
        }
    }
}

// MARK: Session log in the editor and the Inbox

/// A session's clock, ratings and every observation, editable. Used on filed entries and on
/// sessions waiting in the Inbox.
struct SessionSection: View {
    @Environment(AppModel.self) private var model
    @Binding var session: PracticeSession
    /// Makes a Contact or Omen entry from an observation (filed entries only).
    var makeEntry: ((Observation, EntryType) -> ULID?)?

    var body: some View {
        Section {
            LabeledContent("Session") { Text(SessionText.summary(session)).foregroundStyle(.secondary) }
            if !session.phases.isEmpty {
                LabeledContent("Phases") {
                    Text(session.phases.map { "\($0.phase.title) \(SessionText.clock($0.offset))" }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
            }
            if let b = session.before, !b.isEmpty { LabeledContent("Going in") { Text(Self.ratings(b)).foregroundStyle(.secondary) } }
            if let a = session.after, !a.isEmpty { LabeledContent("Coming out") { Text(Self.ratings(a)).foregroundStyle(.secondary) } }
            if let outcome = session.outcome { LabeledContent("Outcome") { Text(outcome).foregroundStyle(.secondary) } }
        } header: {
            Text("Session")
        }
        Section {
            ForEach($session.observations) { $o in
                ObservationEditor(observation: $o, makeEntry: entryMaker(for: o)) {
                    session.observations.removeAll { $0.id == o.id }
                }
            }
            HStack {
                Button("Add Observation", systemImage: "plus") {
                    session.add(Observation(offset: session.duration ?? 0, phase: .aftermath, capture: .recalled))
                }
                Spacer()
                if session.unreviewedCount > 0 {
                    Button("All Look Right") {
                        for i in session.observations.indices { session.observations[i].reviewed = true }
                    }
                }
            }
        } header: {
            Text("Observations")
        }
    }

    private func entryMaker(for o: Observation) -> ((EntryType) -> ULID?)? {
        guard let makeEntry else { return nil }
        return { type in makeEntry(o, type) }
    }

    static func ratings(_ s: StateCheck) -> String {
        [("energy", s.energy), ("calm", s.calm), ("focus", s.focus)].compactMap { name, v in v.map { "\(name) \($0)" } }.joined(separator: " · ")
    }
}

/// One observation: time, kind, text, tags, strength, and whether it has been checked.
struct ObservationEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var observation: Observation
    var makeEntry: ((EntryType) -> ULID?)?
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(SessionText.clock(observation.offset)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Picker("Kind", selection: $observation.kind) {
                    ForEach(ObservationKind.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                TextField("Observation", text: $observation.text, prompt: Text("What was it?"), axis: .vertical)
                if !observation.reviewed {
                    Button("Looks Right", systemImage: "checkmark.circle") { observation.reviewed = true }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Mark this observation as checked")
                }
                Menu {
                    if let makeEntry {
                        Button("New Contact Entry from This") { if let id = makeEntry(.contact) { observation.linkedEntryId = id } }
                        Button("New Omen Entry from This") { if let id = makeEntry(.omen) { observation.linkedEntryId = id } }
                        Divider()
                    }
                    Button("Suggest Tags from Text") {
                        observation.tags = Array(Set(observation.tags + model.vocabulary.suggest(in: observation.text))).sorted()
                    }
                    Divider()
                    Button("Remove", role: .destructive, action: remove)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .labelStyle(.iconOnly)
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            TagField(tags: $observation.tags, prompt: "entity/…, place/…, color/…")
            HStack(spacing: Space.md) {
                ScalePicker(title: "Intensity", value: $observation.intensity).fixedSize()
                ScalePicker(title: "Clarity", value: $observation.clarity).fixedSize()
                Spacer()
                Text(observation.capture.title + (observation.reviewed ? "" : " · to check"))
                    .font(.caption)
                    .foregroundStyle(observation.reviewed ? Color.secondary : Color.orange)
            }
            let free = model.vocabulary.classify(observation.tags).free
            if !free.isEmpty {
                Text("Free tags: \(TagInput.format(free))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Space.xs)
    }
}

// MARK: Settings

/// Settings > Tags: the controlled vocabulary and the free tags worth adding to it.
struct TagSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let free = FreeTags.counts(model.data, vocabulary: model.vocabulary)
        Section {
            LabeledContent("Vocabulary") { Text("\(model.vocabulary.terms.count) tags in \(model.vocabulary.facets.count) groups") }
            Text("Tags from the vocabulary are suggested while you record and are kept in their own columns in the ML export, so the same thing is counted the same way every time. Your additions live in tag-vocabulary.json.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Show Vocabulary File") { NSWorkspace.shared.activateFileViewerSelecting([model.ensureVocabularyFile()]) }
                Button("Reload") { model.loadVocabulary() }
            }
        }
        Section("Free tags in use") {
            if free.isEmpty {
                Text("Every tag you use is in the vocabulary.").foregroundStyle(.secondary)
            } else {
                ForEach(Array(free.prefix(12).enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.tag.path)
                        Text("\(item.count)").foregroundStyle(.secondary)
                        Spacer()
                        Button("Add to Vocabulary") { model.promoteTag(item.tag) }
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}
