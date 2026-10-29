import GrimoireAppKit
import GrimoireCore
import SwiftUI

struct InquiryList: View {
    @Environment(AppModel.self) private var model
    @State private var status: Inquiry.Status?

    private var inquiries: [Inquiry] {
        model.data.inquiries.filter { status == nil || $0.status == status }.sorted { $0.askedAt.instant > $1.askedAt.instant }
    }

    var body: some View {
        @Bindable var model = model
        List(inquiries, selection: $model.selection) { i in
            InquiryRow(inquiry: i)
                .tag(Selection.inquiry(i.id))
                .contextMenu { DeleteButton(id: i.id) }
        }
        .overlay {
            if inquiries.isEmpty {
                ContentUnavailableView("No Inquiries", systemImage: "questionmark.bubble",
                                       description: Text("Press Command-Shift-N to ask a new question."))
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("Status", selection: $status) {
                    Text("All").tag(Inquiry.Status?.none)
                    Text("Open").tag(Inquiry.Status?.some(.open))
                    Text("Resolved").tag(Inquiry.Status?.some(.resolved))
                    Text("Revisited").tag(Inquiry.Status?.some(.revisited))
                }
                .help("Show inquiries by status")
            }
            ToolbarItem {
                Button("New Inquiry", systemImage: "plus") { model.sheet = .newInquiry }
                    .help("Ask a new question (Command-Shift-N)")
            }
        }
    }
}

/// One Inquiry: question, every divination laid out by spread, Yi Jing casts,
/// synthesis, outcomes, reminders, linked entries and backlinks.
struct InquiryView: View {
    @Environment(AppModel.self) private var model
    let inquiryId: ULID
    @State private var inquiry: Inquiry?

    var body: some View {
        Group {
            if let binding = Binding($inquiry) {
                form(binding)
            } else {
                ProgressView()
            }
        }
        .onAppear { inquiry = model.inquiry(inquiryId) }
        .onChange(of: inquiry) { _, new in if let new, new != model.inquiry(inquiryId) { model.stage(new) } }
        // Outcomes and casts can change from menus and sheets: follow the stored value.
        .onChange(of: model.data.inquiries.first { $0.id == inquiryId }?.outcomes) { _, _ in
            if let stored = model.inquiry(inquiryId) { inquiry?.outcomes = stored.outcomes; inquiry?.status = stored.status }
        }
        .onDisappear { model.flushEdits() }
    }

    private func form(_ inquiry: Binding<Inquiry>) -> some View {
        Form {
            Section {
                TextField("Question", text: inquiry.question, axis: .vertical)
                    .font(.title3)
                DatePicker("Asked", selection: inquiry.askedAt.date)
                if let t = inquiry.wrappedValue.timing {
                    LabeledContent("Timing") { Text(TimingText.line(t)).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
                }
                Picker("Status", selection: inquiry.status) {
                    Text("Open").tag(Inquiry.Status.open)
                    Text("Resolved").tag(Inquiry.Status.resolved)
                    Text("Revisited").tag(Inquiry.Status.revisited)
                }
                TextField("Context", text: inquiry.context, axis: .vertical).lineLimit(2...)
                LabeledContent("Category") { TagField(tags: inquiry.category.asList, prompt: "question/…") }
                LabeledContent("Tags") { TagField(tags: inquiry.tags) }
            }

            ForEach(inquiry.divinations) { $d in
                DivinationSection(divination: $d) {
                    inquiry.wrappedValue.divinations.removeAll { $0.id == d.id }
                }
            }
            Section {
                HStack {
                    Button("Add Card Reading", systemImage: "rectangle.stack.badge.plus") { addCards(inquiry) }
                    Button("Add Yi Jing Cast", systemImage: "line.3.horizontal") { addCast(inquiry) }
                }
            }

            Section("Synthesis") {
                TextEditor(text: synthesisBody(inquiry))
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                ScalePicker(title: "Confidence", value: Binding(
                    get: { inquiry.wrappedValue.synthesis?.confidence },
                    set: { ensureSynthesis(inquiry); inquiry.wrappedValue.synthesis?.confidence = $0 }
                ))
            }

            Section("Outcomes") {
                if inquiry.wrappedValue.outcomes.isEmpty {
                    Text("No outcome yet.").foregroundStyle(.secondary)
                }
                ForEach(inquiry.wrappedValue.outcomes) { o in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack {
                            Text(DisplayDate.day(o.recordedAt)).font(.headline)
                            Text("\(inquiry.wrappedValue.daysAfter(o)) days after").foregroundStyle(.secondary)
                            Spacer()
                            Text(o.fulfilled.title).foregroundStyle(.tint)
                        }
                        Text(o.body)
                    }
                    .padding(.vertical, Space.xs)
                }
                Button("Add Outcome…") { model.flushEdits(); model.sheet = .addOutcome(inquiryId) }
            }

            ReminderSection(targetId: inquiryId)
            PhysicalRefSection(ref: inquiry.physicalRef)
            RelatedSection(inquiryId: inquiryId)
        }
        .formStyle(.grouped)
        .navigationTitle(inquiry.wrappedValue.question)
        .toolbar {
            ToolbarItem { DeleteToolbarButton(id: inquiryId) }
        }
    }

    private func ensureSynthesis(_ inquiry: Binding<Inquiry>) {
        if inquiry.wrappedValue.synthesis == nil {
            inquiry.wrappedValue.synthesis = Synthesis(body: "", writtenAt: model.now())
        }
    }

    private func synthesisBody(_ inquiry: Binding<Inquiry>) -> Binding<String> {
        Binding(
            get: { inquiry.wrappedValue.synthesis?.body ?? "" },
            set: {
                ensureSynthesis(inquiry)
                inquiry.wrappedValue.synthesis?.body = $0
                inquiry.wrappedValue.synthesis?.writtenAt = model.now()
            }
        )
    }

    private func addCards(_ inquiry: Binding<Inquiry>) {
        let deck = model.library.deck("rws-tarot") ?? model.library.decks.first
        let order = inquiry.wrappedValue.divinations.count
        inquiry.wrappedValue.divinations.append(
            Divination(system: .cards, deckId: deck?.id, spreadId: "three-card", performedAt: model.now(), order: order))
    }

    private func addCast(_ inquiry: Binding<Inquiry>) {
        let order = inquiry.wrappedValue.divinations.count
        inquiry.wrappedValue.divinations.append(
            Divination(system: .yijing, performedAt: model.now(), method: "coins", order: order, cast: try? YiJingCast(lines: [8, 8, 8, 8, 8, 8])))
    }
}

extension Outcome.Fulfilled {
    var title: String {
        switch self {
        case .yes: "Fulfilled"
        case .partly: "Partly"
        case .no: "Not fulfilled"
        case .unclear: "Unclear"
        }
    }
}

/// One divination inside an Inquiry: cards laid out by spread, or a Yi Jing cast.
struct DivinationSection: View {
    @Environment(AppModel.self) private var model
    @Binding var divination: Divination
    let remove: () -> Void

    var body: some View {
        Section {
            if divination.system == .yijing {
                CastEditor(divination: $divination)
            } else {
                cards
            }
            TextField("Notes", text: $divination.notes.orEmpty, axis: .vertical)
        } header: {
            HStack {
                Text(divination.system == .yijing ? "Yi Jing" : deck?.name ?? "Cards")
                Spacer()
                Button("Remove", systemImage: "trash", role: .destructive, action: remove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Remove this divination")
            }
        }
    }

    private var deck: DeckDefinition? { divination.deckId.flatMap(model.library.deck) }
    private var spread: SpreadDefinition { divination.spreadId.flatMap(model.library.spread) ?? model.library.freeform }

    @ViewBuilder private var cards: some View {
        Picker("Deck", selection: $divination.deckId) {
            ForEach(model.library.decks.filter { $0.status != .template }) { d in
                Text(d.status == .placeholder ? "\(d.name) (placeholder)" : d.name).tag(String?.some(d.id))
            }
        }
        Picker("Spread", selection: $divination.spreadId) {
            ForEach(model.library.spreads.filter { s in divination.deckId.map(s.applies) ?? true }) { s in
                Text(s.name).tag(String?.some(s.id))
            }
        }
        if deck?.status == .placeholder {
            Label("This deck has no cards yet. Its card list comes later from the deck’s repository.", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }
        SpreadLayout(spread: spread, draws: divination.draws, deck: deck)
        ForEach($divination.draws) { $draw in
            DrawRow(draw: $draw, deck: deck, spread: spread) {
                divination.draws.removeAll { $0.id == draw.id }
            }
        }
        Button("Add Card", systemImage: "plus") {
            let key = spread.positionKey(at: divination.draws.count)
            divination.draws.append(Draw(cardId: "", positionKey: key))
        }
        .disabled(deck?.cards.isEmpty ?? true)
    }
}

/// Card picker, orientation and position for one draw.
struct DrawRow: View {
    @Binding var draw: Draw
    let deck: DeckDefinition?
    let spread: SpreadDefinition
    let remove: () -> Void

    var body: some View {
        HStack {
            Text(spread.label(for: draw.positionKey))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            CardPicker(cardId: $draw.cardId, deck: deck)
            if deck?.reversalsAllowed ?? true {
                Toggle("Reversed", isOn: Binding(get: { draw.orientation == .reversed },
                                                 set: { draw.orientation = $0 ? .reversed : .upright }))
                    .toggleStyle(.checkbox)
            }
            Button("Remove", systemImage: "minus.circle", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }
}

/// Every card of a deck, with its suit or element glyph. An empty id shows as “Choose a card”.
struct CardPicker: View {
    @Binding var cardId: String
    let deck: DeckDefinition?

    var body: some View {
        Picker("Card", selection: $cardId) {
            Text("Choose a card").tag("")
            ForEach(deck?.cards ?? []) { c in
                Text(CardName.text(c)).tag(c.id)
            }
        }
        .labelsHidden()
    }
}

enum CardName {
    static func text(_ card: DeckDefinition.Card) -> String {
        if let g = CardGlyph.symbol(for: card) { return "\(g)  \(card.name)" }
        return card.name
    }
}

/// Celtic Cross as the cross and the staff; other spreads as a row.
struct SpreadLayout: View {
    let spread: SpreadDefinition
    let draws: [Draw]
    let deck: DeckDefinition?

    private static let cross: [String: (x: CGFloat, y: CGFloat)] = [
        "crown": (1, 0), "past": (0, 1), "present": (1, 1), "challenge": (1, 1), "near-future": (2, 1), "foundation": (1, 2),
        "outcome": (3.3, -0.25), "hopes-fears": (3.3, 0.6), "environment": (3.3, 1.45), "self": (3.3, 2.3),
    ]

    var body: some View {
        if !draws.isEmpty {
            if spread.id == "celtic-cross" {
                let w: CGFloat = 92, h: CGFloat = 124
                ZStack(alignment: .topLeading) {
                    ForEach(draws) { d in
                        if let p = Self.cross[d.positionKey] {
                            CardTile(draw: d, deck: deck, label: spread.label(for: d.positionKey))
                                .frame(width: w - 8, height: h * 0.8)
                                .rotationEffect(d.positionKey == "challenge" ? .degrees(90) : .zero)
                                .offset(x: p.x * w, y: (p.y + 0.25) * h * 0.9)
                        }
                    }
                }
                .frame(width: 4.4 * w, height: 3.6 * h * 0.9, alignment: .topLeading)
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: Space.md) {
                        ForEach(draws) { d in
                            CardTile(draw: d, deck: deck, label: spread.label(for: d.positionKey))
                                .frame(width: 112, height: 148)
                        }
                    }
                    .padding(.vertical, Space.xs)
                }
            }
        }
    }
}

/// A card shown by name with its glyph; reversed cards say so.
struct CardTile: View {
    let draw: Draw
    let deck: DeckDefinition?
    let label: String

    var body: some View {
        let card = deck?.card(draw.cardId)
        VStack(spacing: Space.xs) {
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            if let card, let g = CardGlyph.symbol(for: card) {
                Text(g).font(.title2).foregroundStyle(.tint)
            }
            Text(card?.name ?? "—")
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if draw.orientation == .reversed {
                Text("Reversed").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.secondary, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
}

/// Six line values (6, 7, 8, 9), the primary and resulting hexagrams.
struct CastEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var divination: Divination
    @State private var digits = ""

    var body: some View {
        Picker("Method", selection: Binding(
            get: { divination.cast?.method ?? .coins },
            set: { m in
                if let lines = divination.cast?.lines { divination.cast = try? YiJingCast(lines: lines, method: m, notes: divination.cast?.notes) }
                divination.method = m.rawValue
            }
        )) {
            Text("Coins").tag(YiJingCast.Method.coins)
            Text("Yarrow").tag(YiJingCast.Method.yarrow)
            Text("Other").tag(YiJingCast.Method.other)
        }
        TextField("Lines, bottom to top", text: $digits, prompt: Text("789677"))
            .onChange(of: digits) { _, new in
                if let cast = try? YiJingCast(quick: new, method: divination.cast?.method ?? .coins) { divination.cast = cast }
            }
            .onAppear { digits = divination.cast?.lines.map(String.init).joined() ?? "" }
        if let cast = divination.cast {
            CastDrawing(cast: cast)
        } else {
            Text("Type six digits, each 6, 7, 8 or 9.").foregroundStyle(.secondary)
        }
    }
}

/// Primary and resulting hexagram, side by side, with changing lines marked.
struct CastDrawing: View {
    @Environment(AppModel.self) private var model
    let cast: YiJingCast

    var body: some View {
        let yj = model.library.yijing
        HStack(alignment: .top, spacing: Space.section) {
            if let n = yj.number(forLines: cast.primaryLines) {
                HexagramFigure(lines: cast.lines.map { $0 }, number: n, name: yj.hexagram(n)?.name ?? "", showChanges: true)
            }
            if let lines = cast.resultingLines, let n = yj.number(forLines: lines) {
                Image(systemName: "arrow.right").foregroundStyle(.secondary).padding(.top, 40)
                HexagramFigure(lines: lines.map { $0 ? 7 : 8 }, number: n, name: yj.hexagram(n)?.name ?? "", showChanges: false)
            }
            Spacer()
        }
        .padding(.vertical, Space.xs)
        if !cast.changingLines.isEmpty {
            Text("Changing lines: \(cast.changingLines.map(String.init).joined(separator: ", "))")
                .foregroundStyle(.secondary)
        }
    }
}

/// Six lines drawn bottom to top. Changing lines (6, 9) carry a mark: ○ on old yang, × on old yin.
struct HexagramFigure: View {
    let lines: [Int]
    let number: Int
    let name: String
    let showChanges: Bool

    var body: some View {
        VStack(spacing: Space.sm) {
            VStack(spacing: 6) {
                ForEach((0..<6).reversed(), id: \.self) { i in
                    line(lines[i])
                }
            }
            .frame(width: 96)
            Text("\(number). \(name)").font(.callout.weight(.medium))
        }
    }

    private func line(_ v: Int) -> some View {
        let yang = YiJingCast.isYang(v)
        return ZStack {
            HStack(spacing: yang ? 0 : 16) {
                Rectangle()
                if !yang { Rectangle() }
            }
            .frame(height: 9)
            .foregroundStyle(.primary)
            if showChanges && YiJingCast.isChanging(v) {
                Text(v == 9 ? "○" : "×")
                    .font(.caption.bold())
                    .foregroundStyle(.tint)
                    .offset(x: 62)
            }
        }
    }
}

/// Reminders for a record, with snooze and done.
struct ReminderSection: View {
    @Environment(AppModel.self) private var model
    let targetId: ULID
    @State private var choice: ReminderChoice = .preset(.oneWeek)

    private var reminders: [Reminder] { model.data.reminders.filter { $0.targetId == targetId } }

    var body: some View {
        Section("Reminders") {
            ForEach(reminders) { r in
                HStack {
                    Label("\(DisplayDate.day(r.dueOn))", systemImage: r.status == .done ? "checkmark.circle" : "bell")
                    Text(r.status.rawValue.capitalized).foregroundStyle(.secondary)
                    Spacer()
                    if r.status != .done {
                        Button("Snooze 3 Days") { model.snooze(r.id) }.controlSize(.small)
                        Button("Done") { model.complete(r.id) }.controlSize(.small)
                    }
                }
            }
            HStack {
                Picker("Remind me", selection: $choice) {
                    ForEach(ReminderChoice.menu.dropFirst(), id: \.self) { Text($0.title).tag($0) }
                }
                .fixedSize()
                Button("Add Reminder") { model.addReminder(for: targetId, choice) }
            }
        }
    }
}

/// Entries that belong to or link to this Inquiry.
struct RelatedSection: View {
    @Environment(AppModel.self) private var model
    let inquiryId: ULID

    var body: some View {
        let related = model.timelineEntries.filter { $0.inquiryId == inquiryId }
        let back = model.repository.backlinks(to: inquiryId)
        if !related.isEmpty || !back.isEmpty {
            Section("Linked entries") {
                ForEach(related) { e in
                    Button { model.reveal(e.id) } label: { EntryRow(entry: e) }.buttonStyle(.plain)
                }
                ForEach(back.indices, id: \.self) { i in
                    LabeledContent(back[i].kind.rawValue) {
                        Button(model.title(for: back[i].source)) { model.reveal(back[i].source) }.buttonStyle(.link)
                    }
                }
            }
        }
    }
}

/// New Inquiry: question, context and an outcome reminder.
struct NewInquirySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var context = ""
    @State private var reminder: ReminderChoice = .preset(.none)
    @State private var customDays = 14
    @State private var custom = false

    var body: some View {
        Form {
            Section("New Inquiry") {
                TextField("Question", text: $question, axis: .vertical)
                TextField("Context", text: $context, axis: .vertical).lineLimit(2...)
            }
            Section {
                Picker("Outcome reminder", selection: Binding(
                    get: { custom ? nil : reminder },
                    set: { if let r = $0 { reminder = r; custom = false } else { custom = true } }
                )) {
                    ForEach(ReminderChoice.menu, id: \.self) { Text($0.title).tag(ReminderChoice?.some($0)) }
                    Text("Custom…").tag(ReminderChoice?.none)
                }
                if custom {
                    Stepper("In \(customDays) days", value: $customDays, in: 1...730)
                }
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 480)
        .noInitialFocus()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    model.newInquiry(question: question, context: context, reminder: custom ? .customDays(customDays) : reminder)
                    dismiss()
                }
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { reminder = .preset(model.settings.reminderDefault) }
    }
}

/// Add an outcome: what happened, when, and whether the reading held.
struct AddOutcomeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let inquiryId: ULID
    @State private var body_ = ""
    @State private var when = Date.now
    @State private var fulfilled: Outcome.Fulfilled = .unclear

    var body: some View {
        Form {
            Section("Outcome") {
                Text(model.inquiry(inquiryId)?.question ?? "").foregroundStyle(.secondary)
                TextField("What happened", text: $body_, axis: .vertical).lineLimit(3...)
                DatePicker("When", selection: $when)
                Picker("The reading", selection: $fulfilled) {
                    ForEach([Outcome.Fulfilled.yes, .partly, .no, .unclear], id: \.self) { Text($0.title).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 480)
        .noInitialFocus()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    model.addOutcome(to: inquiryId, Outcome(recordedAt: ZonedDate(when, timeZone: TimeZone.current.identifier), body: body_, fulfilled: fulfilled))
                    dismiss()
                }
                .disabled(body_.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
