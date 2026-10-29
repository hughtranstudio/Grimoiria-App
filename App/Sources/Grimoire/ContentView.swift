import GrimoireAppKit
import GrimoireCore
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            sidebar
        } content: {
            PageList(page: model.page ?? .today)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            DetailView()
        }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .newInquiry: NewInquirySheet()
            case .addOutcome(let id): AddOutcomeSheet(inquiryId: id)
            case .newVolume: NewVolumeSheet()
            case .indexPages(let id): IndexPagesSheet(volumeId: id)
            case .importDocuments: ImportDocumentsSheet()
            }
        }
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                Text(notice)
                    .font(.callout)
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.sm)
                    .glassEffect()
                    .padding(Space.lg)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: model.notice)
        .task {
            AgentRouter.model = model
            AgentSocket.listen { AgentRouter.handle($0) }
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(selection: $model.page) {
            ForEach(SidebarPage.allCases) { page in
                Label(page.title, systemImage: page.symbol)
                    .badge(badge(for: page))
                    .tag(page)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        .onChange(of: model.page) { model.selection = nil }
    }

    private func badge(for page: SidebarPage) -> Int {
        switch page {
        case .inbox: model.data.inbox.count
        case .today: model.repository.needsOutcome(today: model.today).count
        default: 0
        }
    }
}

/// The middle column: the list for the chosen sidebar page.
struct PageList: View {
    let page: SidebarPage

    var body: some View {
        Group {
            switch page {
            case .today: TodayList()
            case .timeline: TimelineList()
            case .inquiries: InquiryList()
            case .inbox: InboxList()
            case .search: SearchList()
            case .volumes: VolumeList()
            case .decks: DeckList()
            case .patterns: PatternList()
            case .calendar: CalendarList()
            case .correspondences: CorrespondenceList()
            }
        }
        .navigationTitle(page.title)
    }
}

/// The right column: whatever is selected.
struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.selection {
        case .entry(let id) where model.entry(id) != nil:
            EntryEditor(entryId: id).id(id)
        case .inquiry(let id) where model.inquiry(id) != nil:
            InquiryView(inquiryId: id).id(id)
        case .inbox(let id) where model.data.inbox.contains { $0.id == id }:
            InboxDetail(itemId: id).id(id)
        case .volume(let id) where model.volume(id) != nil:
            VolumeDetail(volumeId: id).id(id)
        case .deck(let id) where model.library.deck(id) != nil:
            DeckDetail(deckId: id).id(id)
        case .pattern(let section):
            PatternDetail(section: section).id(section)
        case .day(let day):
            CalendarDayDetail(day: day).id(day)
        case .correspondence(let key):
            CorrespondenceDetail(key: key).id(key)
        default:
            ContentUnavailableView("Nothing Selected", systemImage: "sidebar.right",
                                   description: Text("Choose a record, or press Command-N for a new journal entry."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: Rows

extension EntryType {
    var symbol: String {
        switch self {
        case .journal: "book.closed"
        case .ritual: "flame"
        case .meditation: "figure.mind.and.body"
        case .vision: "eye"
        case .contact: "person.wave.2"
        case .omen: "bird"
        case .insight: "lightbulb"
        case .dream: "moon.zzz"
        case .divination: "suit.diamond"
        }
    }

    var title: String { rawValue.capitalized }

    /// Command-Option-1 … for New Journal, New Ritual, …
    static let creatable: [EntryType] = [.journal, .ritual, .meditation, .vision, .contact, .omen, .insight, .dream]
}

struct EntryRow: View {
    let entry: Entry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: entry.type.symbol)
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(entry.displayTitle).lineLimit(1)
                HStack(spacing: Space.sm) {
                    Text(DisplayDate.dayTime(entry.occurredAt))
                    if let ref = entry.physicalRef { PageBadge(ref: ref) }
                    if !entry.tags.isEmpty { Text(TagInput.format(entry.tags)).lineLimit(1) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Space.xs)
    }
}

struct InquiryRow: View {
    @Environment(AppModel.self) private var model
    let inquiry: Inquiry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: "questionmark.bubble")
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(inquiry.question).lineLimit(2)
                HStack(spacing: Space.sm) {
                    Text(DisplayDate.day(inquiry.askedAt))
                    Text(summary)
                    Text(inquiry.status.rawValue.capitalized)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Space.xs)
    }

    private var summary: String {
        inquiry.divinations.map { d in
            switch d.system {
            case .yijing: "Yi Jing"
            default: d.deckId.flatMap { model.library.deck($0)?.name } ?? "Cards"
            }
        }.joined(separator: " + ")
    }
}

struct PageBadge: View {
    @Environment(AppModel.self) private var model
    let ref: PhysicalRef

    var body: some View {
        Label("\(model.volume(ref.volumeId)?.name ?? "Volume") p. \(ref.page)", systemImage: "book.pages")
            .labelStyle(.titleAndIcon)
    }
}
