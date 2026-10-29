import AppKit
import Foundation
import GrimoireAppKit
import GrimoireCore
import Observation
import SwiftData

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarPage: String, CaseIterable, Identifiable {
    case today, timeline, inquiries, inbox, search, volumes, decks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .timeline: "Timeline"
        case .inquiries: "Inquiries"
        case .inbox: "Inbox"
        case .search: "Search"
        case .volumes: "Volumes"
        case .decks: "Decks"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.horizon"
        case .timeline: "calendar.day.timeline.left"
        case .inquiries: "questionmark.bubble"
        case .inbox: "tray"
        case .search: "magnifyingglass"
        case .volumes: "books.vertical"
        case .decks: "rectangle.stack"
        }
    }

    /// Command-1 … Command-7.
    var shortcut: Character { Character(String((Self.allCases.firstIndex(of: self) ?? 0) + 1)) }
}

/// What the detail column shows.
enum Selection: Hashable {
    case entry(ULID)
    case inquiry(ULID)
    case inbox(ULID)
    case volume(ULID)
    case deck(String)
}

/// Sheets the window can show.
enum Sheet: Identifiable {
    case newInquiry
    case addOutcome(ULID)
    case newVolume
    case indexPages(ULID?)

    var id: String {
        switch self {
        case .newInquiry: "newInquiry"
        case .addOutcome(let id): "outcome-\(id)"
        case .newVolume: "newVolume"
        case .indexPages: "indexPages"
        }
    }
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    static let shared = AppModel()

    let container: ModelContainer
    let repository: SwiftDataRepository
    let settings = AppSettings()
    /// Decks, spreads and Yi Jing from Application Support.
    var library: DefinitionLibrary
    var definitionsReport: ValidationReport?
    var definitionsError: String?
    /// Everything filed, refreshed after each write.
    var data = GrimoireData()

    var page: SidebarPage? = .today
    var selection: Selection?
    var sheet: Sheet?
    var searchText = ""
    /// A short line shown at the bottom of the window, like "Exported 12 files".
    var notice: String?
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    /// Edits waiting to be written; editors stage them and they land shortly after typing stops.
    @ObservationIgnored private var pendingEntries: [ULID: Entry] = [:]
    @ObservationIgnored private var pendingInquiries: [ULID: Inquiry] = [:]
    @ObservationIgnored private var flushTask: Task<Void, Never>?

    init() {
        container = Store.makeContainer()
        repository = SwiftDataRepository(context: container.mainContext)
        library = DefinitionLibrary(decks: [], spreads: [], yijing: YiJingDefinition.empty)
        loadDefinitions()
        data = repository.data
        repository.didChange = { [weak self] in
            guard let self else { return }
            data = repository.data
        }
    }

    /// Runs once the app has finished launching.
    func didLaunch() {
        guard !SelfTest.requested, ProcessInfo.processInfo.environment["APP_SNAPSHOT"] == nil else { return }
        ReminderScheduler.shared.start()
        QuickLogController.shared.updateHotKey()
        IngestCoordinator.shared.start()
    }

    // MARK: Definitions

    /// Copies the bundled definitions on first launch, then loads and validates them.
    func loadDefinitions() {
        do {
            guard let bundled = Store.bundledDefinitions else {
                throw DefinitionError.missing("Definitions folder inside the app")
            }
            library = try DefinitionsFolder.install(from: bundled, to: Store.definitions)
            definitionsReport = library.validate()
            definitionsError = library.validate().isValid ? nil : library.validate().errors.joined(separator: "\n")
        } catch {
            definitionsError = String(describing: error)
        }
    }

    // MARK: Lookups

    func entry(_ id: ULID) -> Entry? { pendingEntries[id] ?? data.entries.first { $0.id == id } }
    func inquiry(_ id: ULID) -> Inquiry? { pendingInquiries[id] ?? data.inquiries.first { $0.id == id } }
    func volume(_ id: ULID) -> Volume? { data.volumes.first { $0.id == id } }

    var today: String { GrimoireDateFormat.day(.now, in: .current) }
    var tagTree: TagTree { repository.tagTree }

    /// Filed entries newest first, without the divination entries an Inquiry stands for.
    var timelineEntries: [Entry] {
        data.entries.filter { $0.status == .filed && !($0.type == .divination && $0.inquiryId != nil) }
            .sorted { $0.occurredAt.instant > $1.occurredAt.instant }
    }

    func title(for id: ULID) -> String {
        if let e = entry(id) { return e.displayTitle }
        if let i = inquiry(id) { return i.question }
        if let v = volume(id) { return v.name }
        return id.string
    }

    // MARK: Writing

    func now() -> ZonedDate { ZonedDate(.now, timeZone: TimeZone.current.identifier) }

    func timing(at date: ZonedDate) -> TimingContext {
        TimingContext.compute(at: date, location: settings.home)
    }

    @discardableResult
    func newEntry(_ type: EntryType, body: String = "", tags: [TagPath] = [], mode: EntryMode = .reflective, select: Bool = true) -> Entry {
        let at = now()
        let entry = Entry(type: type, occurredAt: at, body: body, tags: tags, timing: timing(at: at), mode: mode)
        repository.save(entry)
        if select {
            if page != .timeline && page != .today { page = .timeline }
            selection = .entry(entry.id)
        }
        return entry
    }

    /// Stages an edit; it is written shortly after typing stops, or on quit.
    func stage(_ entry: Entry) {
        var e = entry
        let stored = data.entries.first { $0.id == entry.id }
        if stored?.occurredAt != e.occurredAt || e.timing == nil { e.timing = timing(at: e.occurredAt) }
        e.updatedAt = .now
        pendingEntries[e.id] = e
        scheduleFlush()
    }

    func stage(_ inquiry: Inquiry) {
        var i = inquiry
        let stored = data.inquiries.first { $0.id == inquiry.id }
        if stored?.askedAt != i.askedAt || i.timing == nil { i.timing = timing(at: i.askedAt) }
        i.updatedAt = .now
        pendingInquiries[i.id] = i
        scheduleFlush()
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            self?.flushEdits()
        }
    }

    /// Writes staged edits now.
    func flushEdits() {
        let entries = pendingEntries, inquiries = pendingInquiries
        pendingEntries = [:]
        pendingInquiries = [:]
        for e in entries.values { repository.save(e) }
        for i in inquiries.values { repository.save(i) }
    }

    func delete(_ id: ULID) {
        flushEdits()
        repository.delete(id)
        if selection == .entry(id) || selection == .inquiry(id) || selection == .volume(id) { selection = nil }
    }

    func show(_ message: String) {
        notice = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.notice == message { self?.notice = nil }
        }
    }
}

extension YiJingDefinition {
    /// Stands in until the real definitions load.
    static var empty: YiJingDefinition {
        try! JSONDecoder().decode(YiJingDefinition.self, from: Data(#"{"id":"yijing","name":"Yi Jing","version":0,"aliases":[],"trigrams":[],"hexagrams":[]}"#.utf8))
    }
}
