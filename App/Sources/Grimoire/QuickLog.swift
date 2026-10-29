import AppKit
import Carbon.HIToolbox
import GrimoireAppKit
import GrimoireCore
import SwiftUI

/// The floating Quick Log panel and its global hotkey (Control-Option-G).
final class QuickLogController {
    static let shared = QuickLogController()

    private var panel: NSPanel?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func toggle() {
        if let panel, panel.isVisible { close() } else { show() }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: QuickLogView(close: { [weak self] in self?.close() })
            .environment(AppModel.shared)
            .themed())
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 520, height: 260))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    var window: NSWindow? { panel }

    private func makePanel() -> NSPanel {
        let panel = QuickPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 260),
                               styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
                               backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        return panel
    }

    /// Registers or removes the global hotkey to match Settings.
    func updateHotKey() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        guard AppModel.shared.settings.hotkeyEnabled, !Store.isOverridden else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { QuickLogController.shared.toggle() } }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x4752_4D51), id: 1) // "GRMQ"
        RegisterEventHotKey(UInt32(kVK_ANSI_G), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }
}

/// A panel that takes typing without bringing the whole app forward.
final class QuickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

/// One keystroke picks the type, then one line of text. Return saves.
struct QuickLogView: View {
    @Environment(AppModel.self) private var model
    let close: () -> Void
    @State private var kind: QuickKind?
    @State private var text = ""
    @State private var tags = ""
    @State private var deckId = "rws-tarot"
    @State private var spreadId = "single"
    @FocusState private var focus: Field?

    enum Field { case keys, text, tags }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if let kind {
                HStack {
                    Label(kind.title, systemImage: symbol(kind)).font(.headline)
                    Spacer()
                    Button("Change Type") { self.kind = nil; text = ""; focus = .keys }
                        .controlSize(.small)
                }
                if kind == .cardDraw {
                    HStack {
                        Picker("Deck", selection: $deckId) {
                            ForEach(model.library.decks.filter { $0.status == .complete }) { Text($0.name).tag($0.id) }
                        }
                        Picker("Spread", selection: $spreadId) {
                            ForEach(model.library.spreads) { Text($0.name).tag($0.id) }
                        }
                    }
                }
                TextField(prompt(kind), text: $text, axis: kind.entryType == nil ? .horizontal : .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($focus, equals: .text)
                    .onSubmit(save)
                if kind.entryType != nil {
                    TextField("Tags", text: $tags, prompt: Text("Tags: omen/bird, place/garden"))
                        .textFieldStyle(.roundedBorder)
                        .focused($focus, equals: .tags)
                        .onSubmit(save)
                }
                preview(kind)
                HStack {
                    Text("Return saves · Esc closes").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save", action: save)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave(kind))
                }
            } else {
                Text("Quick Log").font(.headline)
                Text("Press a key to choose:").foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: Space.lg, verticalSpacing: Space.sm) {
                    ForEach(Array(QuickKind.allCases.chunked(4).enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(row, id: \.self) { k in
                                Button { choose(k) } label: {
                                    HStack(spacing: Space.xs) {
                                        Text(String(k.key).uppercased()).font(.body.monospaced().bold()).foregroundStyle(.tint)
                                        Text(k.title)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(Space.xl)
        .frame(width: 520)
        .focusable(kind == nil)
        .focused($focus, equals: .keys)
        .focusEffectDisabled()
        .onKeyPress { press in
            guard kind == nil, let c = press.characters.first, let k = QuickKind.forKey(c) else { return .ignored }
            choose(k)
            return .handled
        }
        .onAppear { focus = .keys }
    }

    private func choose(_ k: QuickKind) {
        kind = k
        text = ""
        tags = ""
        DispatchQueue.main.async { focus = .text }
    }

    private func symbol(_ k: QuickKind) -> String {
        switch k {
        case .cardDraw: "rectangle.stack"
        case .yijing: "line.3.horizontal"
        default: k.entryType?.symbol ?? "circle"
        }
    }

    private func prompt(_ k: QuickKind) -> String {
        switch k {
        case .cardDraw: "3 cups r, tower, page of wands"
        case .yijing: "Six digits, bottom to top: 789677"
        default: "What happened?"
        }
    }

    @ViewBuilder private func preview(_ k: QuickKind) -> some View {
        switch k {
        case .cardDraw:
            let draft = ReadingParser(library: model.library).parseQuickDraw(text, deckId: deckId, spreadId: spreadId)
            let deck = model.library.deck(deckId)
            if !draft.draws.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(Array(draft.draws.enumerated()), id: \.offset) { _, d in
                        HStack {
                            if let id = d.cardId.value, let card = deck?.card(id) {
                                Text(CardName.text(card))
                                if d.orientation.value == .reversed { Text("reversed").foregroundStyle(.secondary) }
                            } else {
                                Text("“\(d.cardId.heard ?? "?")” not found").foregroundStyle(.red)
                            }
                            if d.cardId.confidence < .high, d.cardId.value != nil {
                                Image(systemName: "questionmark.circle").foregroundStyle(.tint).help("Not sure about this card")
                            }
                        }
                    }
                }
                .font(.callout)
            }
        case .yijing:
            if let cast = try? YiJingCast(quick: text) { CastDrawing(cast: cast) }
        default:
            EmptyView()
        }
    }

    private func canSave(_ k: QuickKind) -> Bool {
        switch k {
        case .cardDraw:
            let d = ReadingParser(library: model.library).parseQuickDraw(text, deckId: deckId, spreadId: spreadId)
            return !d.draws.isEmpty && d.draws.allSatisfy { $0.cardId.value != nil }
        case .yijing: return (try? YiJingCast(quick: text)) != nil
        default: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func save() {
        guard let kind, canSave(kind) else { return }
        model.quickSave(kind, text: text, tags: TagInput.parse(tags), deckId: deckId, spreadId: spreadId)
        model.show("Saved \(kind.title.lowercased())")
        self.kind = nil
        text = ""
        tags = ""
        close()
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

extension AppModel {
    /// Saves a quick-log record with mode quick. Card draws and casts become a one-divination Inquiry.
    @discardableResult
    func quickSave(_ kind: QuickKind, text: String, tags: [TagPath], deckId: String = "rws-tarot", spreadId: String = "single") -> ULID? {
        if let type = kind.entryType {
            return newEntry(type, body: text.trimmingCharacters(in: .whitespacesAndNewlines), tags: tags, mode: .quick, select: false).id
        }
        let at = now()
        let divination: Divination
        if kind == .yijing {
            guard let cast = try? YiJingCast(quick: text) else { return nil }
            divination = Divination(system: .yijing, performedAt: at, method: cast.method.rawValue, cast: cast)
        } else {
            let draft = ReadingParser(library: library).parseQuickDraw(text, deckId: deckId, spreadId: spreadId)
            let draws = draft.draws.compactMap { d in
                d.cardId.value.map { Draw(cardId: $0, positionKey: d.positionKey, orientation: d.orientation.value ?? .upright) }
            }
            divination = Divination(system: .cards, deckId: deckId, spreadId: spreadId, performedAt: at, draws: draws)
        }
        let question = kind == .yijing ? "Quick Yi Jing cast" : "Quick card draw"
        let inquiry = newInquiry(question: question, divinations: [divination], select: false)
        let entry = Entry(type: .divination, title: question, occurredAt: at, inquiryId: inquiry.id, timing: inquiry.timing, mode: .quick)
        repository.save(entry)
        return inquiry.id
    }
}
