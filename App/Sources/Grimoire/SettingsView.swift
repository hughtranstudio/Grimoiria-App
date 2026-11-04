import GrimoireCore
import SwiftUI

/// The Settings window (Command-Comma). One tab per topic.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .export: ExportSettings()
            case .inbox: InboxSettings()
            case .tags: TagSettings()
            case .uranika: UranikaSettingsPane()
            case .appearance: AppearanceSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent(max: 760)
        .frame(width: 560)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, export, inbox, tags, uranika, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .export: "Export"
        case .inbox: "Inbox"
        case .tags: "Tags"
        case .uranika: "Uranika"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .export: "square.and.arrow.up"
        case .inbox: "tray"
        case .tags: "tag"
        case .uranika: "globe"
        case .appearance: "paintpalette"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Section {
            TextField("Place", text: $settings.homeName, prompt: Text("Home"))
            TextField("Latitude", value: $settings.homeLatitude, format: .number.precision(.fractionLength(0...4)), prompt: Text("37.77"))
            TextField("Longitude", value: $settings.homeLongitude, format: .number.precision(.fractionLength(0...4)), prompt: Text("-122.42"))
            Button("Fill Timing on Older Records") { model.fillMissingTiming() }
                .disabled(settings.home == nil)
        } header: {
            Text("Home location")
        } footer: {
            Text("Used for planetary days and hours. Moon and Sun work without it.")
        }
        Section {
            Picker("Outcome reminder", selection: $settings.reminderDefault) {
                Text("At 7, 30 and 90 days").tag(ReminderPreset.ladder)
                Text("None").tag(ReminderPreset.none)
                Text("In 1 week").tag(ReminderPreset.oneWeek)
                Text("In 1 month").tag(ReminderPreset.oneMonth)
                Text("In 3 months").tag(ReminderPreset.threeMonths)
            }
            Button("Add Check-ins to Past Readings") { model.backfillCheckIns() }
        } header: {
            Text("Inquiries")
        } footer: {
            Text("Past readings without an outcome get one check-in, due today, at the latest step already passed.")
        }
        Section {
            Toggle("Notify when something keeps coming back", isOn: $settings.nudgeNotifications)
                .onChange(of: settings.nudgeNotifications) { ReminderScheduler.shared.refresh() }
            if !settings.hiddenNudges.isEmpty {
                Button("Show Hidden Nudges Again") { settings.hiddenNudges = [] }
            }
        } header: {
            Text("Nudges")
        } footer: {
            Text("A card, hexagram or symbol that comes up three times within two weeks shows on Today, with one notification per run.")
        }
        Section {
            Toggle("Quick Log hotkey (Control-Option-G)", isOn: $settings.hotkeyEnabled)
                .onChange(of: settings.hotkeyEnabled) { QuickLogController.shared.updateHotKey() }
        } footer: {
            Text("Opens the Quick Log panel from any app.")
        }
    }
}

struct ExportSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Section {
            LabeledContent("Vault folder") {
                HStack {
                    Text(settings.vaultPath.isEmpty ? "Not set" : (settings.vaultPath as NSString).abbreviatingWithTildeInPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") { if let path = FolderPanel.choose(message: "Choose the folder in your Obsidian vault for Grimoire, for example Vault/Grimoire.") { settings.vaultPath = path } }
                }
            }
            Toggle("Export after each Inbox confirm", isOn: $settings.exportAfterConfirm)
            Toggle("Also write files for local AI models", isOn: $settings.exportML)
            Button("Export Now") { model.exportNow() }
                .disabled(settings.vaultPath.isEmpty)
        } footer: {
            Text("Markdown with YAML frontmatter, a note per card and hexagram, and grimoire.jsonl. Only changed files are written, and notes for deleted records are removed; your own notes are never touched. The ML folder holds one row per draw and passages of your writing, for models you run on this Mac.")
        }
    }
}

struct InboxSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Section {
            ForEach(settings.ingestFolders, id: \.self) { path in
                HStack {
                    Text((path as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Remove", systemImage: "minus.circle") {
                        settings.ingestFolders.removeAll { $0 == path }
                        IngestCoordinator.shared.restart()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }
            Button("Add Folder…") {
                if let path = FolderPanel.choose(message: "Choose an ingest folder. Captures go in its incoming folder.") {
                    settings.ingestFolders.append(path)
                    IngestCoordinator.shared.restart()
                }
            }
        } header: {
            Text("Ingest folders")
        } footer: {
            Text("Each folder holds incoming, processed and failed. The phone Shortcut writes to GrimoireInbox in iCloud Drive.")
        }
        Section {
            Toggle("Share a read-only library with the phone", isOn: $settings.sharePhoneLibrary)
                .onChange(of: settings.sharePhoneLibrary) { _, on in if on { PhoneLibrarySync.shared.publishNow() } }
        } footer: {
            Text("Writes filed records into library/ in each ingest folder outside iCloud Drive, so Grimoire on the Pixel can browse and search them and remind you of check-ins. Syncthing carries it; nothing goes to a cloud.")
        }
        Section {
            Picker("Speech model", selection: $settings.whisperModel) {
                Text("Apple on-device speech").tag("apple")
                Text("Transcript file beside the audio").tag("sidecar")
            }
            if settings.whisperModel == "apple" { SpeechModelRow() }
        } header: {
            Text("Transcription")
        } footer: {
            Text("Runs on this Mac. Nothing is sent anywhere.")
        }
    }
}

enum FolderPanel {
    static func choose(message: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = message
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

/// Apple's on-device speech model: downloaded once, only when the person presses Install.
struct SpeechModelRow: View {
    @State private var installed: Bool?
    @State private var working = false
    @State private var error: String?

    var body: some View {
        LabeledContent("Speech model") {
            if installed == true {
                Text("Installed").foregroundStyle(.secondary)
            } else if working {
                ProgressView().controlSize(.small)
            } else {
                Button("Install") {
                    working = true
                    Task {
                        do { try await AppleSpeechTranscriber.installModel(); error = nil } catch { self.error = error.localizedDescription }
                        installed = await AppleSpeechTranscriber.modelInstalled()
                        working = false
                    }
                }
            }
        }
        .task { installed = await AppleSpeechTranscriber.modelInstalled() }
        if let error { Text(error).foregroundStyle(.red).font(.caption) }
    }
}

/// Uranika on this Mac: the chart of each capture's moment. Edits uranika-settings.json.
struct UranikaSettingsPane: View {
    var body: some View {
        @Bindable var link = UranikaLink.shared
        Section {
            Toggle("Ask Uranika for the chart of each capture", isOn: $link.settings.enabled)
                .onChange(of: link.settings.enabled) { _, on in
                    if on { link.start(); Task { await link.check() } } else { link.stop() }
                }
            TextField("Server", text: $link.settings.baseURL, prompt: Text("http://127.0.0.1:8765"))
            LabeledContent("Status") {
                HStack {
                    Text(link.status ?? "Not checked").foregroundStyle(.secondary).lineLimit(2)
                    Button("Check") { Task { await link.check() } }
                }
            }
            Picker("Your chart", selection: $link.settings.natalChartId) {
                Text("None (the sky only)").tag(Int?.none)
                ForEach(link.charts, id: \.id) { Text($0.name).tag(Int?.some($0.id)) }
                if let id = link.settings.natalChartId, !link.charts.contains(where: { $0.id == id }) {
                    Text("Chart \(id)").tag(Int?.some(id))
                }
            }
        } header: {
            Text("Uranika")
        } footer: {
            Text("Uranika runs on this Mac, so nothing leaves it. With your chart chosen, each entry also gets the transits and solar arcs to it. When Uranika is closed, entries say “chart pending” and fill in once it opens.")
        }
        .task { if link.settings.enabled, link.status == nil { await link.check() } }
        Section {
            Picker("Charts for", selection: $link.settings.scope) {
                Text("Every capture").tag(UranikaSettings.Scope.all)
                Text("Life events only").tag(UranikaSettings.Scope.events)
            }
            Toggle("Use the phone’s position when it sends one", isOn: $link.settings.useCapturedLocation)
            Toggle("Add life events to your chart in Uranika", isOn: $link.settings.recordEventsInUranika)
                .disabled(link.settings.natalChartId == nil)
            Button("Fill Pending Charts Now") { Task { await link.fillPending(report: true) } }
                .disabled(!link.settings.enabled)
        } footer: {
            Text("Charts are cast for the home place in General unless the phone’s position is allowed, rounded to about 1 km. Only your chart’s name and number are stored, never birth data.")
        }
    }
}
