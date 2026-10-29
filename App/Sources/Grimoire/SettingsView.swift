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
            case .appearance: AppearanceSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 560)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, export, inbox, tags, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .export: "Export"
        case .inbox: "Inbox"
        case .tags: "Tags"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .export: "square.and.arrow.up"
        case .inbox: "tray"
        case .tags: "tag"
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
