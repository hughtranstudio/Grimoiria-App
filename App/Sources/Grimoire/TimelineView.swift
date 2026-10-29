import GrimoireAppKit
import GrimoireCore
import SwiftUI

/// Every filed record, newest first, grouped by day (Day One style).
struct TimelineList: View {
    @Environment(AppModel.self) private var model
    @State private var filter: EntryType?

    private enum Item: Identifiable {
        case entry(Entry), inquiry(Inquiry)
        var id: String { switch self { case .entry(let e): e.id.string; case .inquiry(let i): i.id.string } }
        var date: ZonedDate { switch self { case .entry(let e): e.occurredAt; case .inquiry(let i): i.askedAt } }
    }

    private var items: [Item] {
        var out: [Item] = []
        if filter == nil || filter == .divination { out += model.data.inquiries.map(Item.inquiry) }
        out += model.timelineEntries.filter { filter == nil || $0.type == filter }.map(Item.entry)
        return out.sorted { $0.date.instant > $1.date.instant }
    }

    private var days: [(String, [Item])] {
        var groups: [(String, [Item])] = []
        for item in items {
            let day = DisplayDate.day(item.date)
            if groups.last?.0 == day { groups[groups.count - 1].1.append(item) } else { groups.append((day, [item])) }
        }
        return groups
    }

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            ForEach(days, id: \.0) { day, items in
                Section(day) {
                    ForEach(items) { item in
                        switch item {
                        case .entry(let e): EntryRow(entry: e).tag(Selection.entry(e.id)).contextMenu { DeleteButton(id: e.id) }
                        case .inquiry(let i): InquiryRow(inquiry: i).tag(Selection.inquiry(i.id)).contextMenu { DeleteButton(id: i.id) }
                        }
                    }
                }
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("No Records", systemImage: "calendar.day.timeline.left",
                                       description: Text("Press Command-N for a journal entry, or Command-Option-L to log something quickly."))
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("Type", selection: $filter) {
                    Text("All Types").tag(EntryType?.none)
                    Divider()
                    ForEach(EntryType.allCases, id: \.self) { t in
                        Label(t.title, systemImage: t.symbol).tag(EntryType?.some(t))
                    }
                }
                .help("Show one type")
            }
            ToolbarItem { NewEntryMenu() }
        }
    }
}

struct NewEntryMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu("New", systemImage: "plus") {
            ForEach(EntryType.creatable, id: \.self) { t in
                Button(t.title, systemImage: t.symbol) { model.newEntry(t) }
            }
            Divider()
            Button("Inquiry", systemImage: "questionmark.bubble") { model.sheet = .newInquiry }
        } primaryAction: {
            model.newEntry(.journal)
        }
        .help("New journal entry (Command-N). Hold for other types.")
    }
}

struct DeleteButton: View {
    @Environment(AppModel.self) private var model
    let id: ULID
    @State private var confirming = false

    var body: some View {
        Button("Delete…", role: .destructive) { confirming = true }
            .confirmationDialog("Delete “\(model.title(for: id))”?", isPresented: $confirming) {
                Button("Delete", role: .destructive) { model.delete(id) }
            } message: {
                Text("This can’t be undone.")
            }
    }
}

/// Today: what needs an outcome, what happened today, and the timing right now.
struct TodayList: View {
    @Environment(AppModel.self) private var model

    private var due: [Reminder] { model.repository.needsOutcome(today: model.today) }
    private var todays: [Entry] { model.timelineEntries.filter { $0.occurredAt.day == model.today } }
    private var todaysInquiries: [Inquiry] { model.data.inquiries.filter { $0.askedAt.day == model.today } }

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section("Now") {
                Text(TimingText.line(model.timing(at: model.now())))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .selectionDisabled()
            }
            Section("Needs outcome") {
                if due.isEmpty {
                    Text("Nothing due.").foregroundStyle(.secondary).selectionDisabled()
                }
                ForEach(due) { r in
                    if let i = model.inquiry(r.targetId) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            InquiryRow(inquiry: i)
                            HStack {
                                Text("Due \(DisplayDate.day(r.dueOn))").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Snooze 3 Days") { model.snooze(r.id) }
                                Button("Add Outcome…") { model.sheet = .addOutcome(i.id) }
                            }
                            .controlSize(.small)
                        }
                        .tag(Selection.inquiry(i.id))
                    }
                }
            }
            Section("Today") {
                if todays.isEmpty && todaysInquiries.isEmpty {
                    Text("Nothing logged yet today.").foregroundStyle(.secondary).selectionDisabled()
                }
                ForEach(todaysInquiries) { i in InquiryRow(inquiry: i).tag(Selection.inquiry(i.id)) }
                ForEach(todays) { e in EntryRow(entry: e).tag(Selection.entry(e.id)) }
            }
        }
        .toolbar { ToolbarItem { NewEntryMenu() } }
    }
}
