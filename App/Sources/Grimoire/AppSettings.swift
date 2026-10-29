import Foundation
import GrimoireCore
import Observation

/// Settings kept in UserDefaults. Test and snapshot runs (APP_STORE set) use
/// their own defaults domain, so they never change the real settings.
@Observable
final class AppSettings {
    @ObservationIgnored let defaults: UserDefaults

    init() {
        if Store.isOverridden, let test = UserDefaults(suiteName: "studio.htd.grimoire.test") {
            test.removePersistentDomain(forName: "studio.htd.grimoire.test")
            defaults = test
        } else {
            defaults = .standard
        }
        homeName = defaults.string(forKey: "home.name") ?? ""
        homeLatitude = defaults.object(forKey: "home.latitude") as? Double
        homeLongitude = defaults.object(forKey: "home.longitude") as? Double
        vaultPath = defaults.string(forKey: "vault.path") ?? ""
        exportAfterConfirm = defaults.object(forKey: "vault.afterConfirm") as? Bool ?? true
        ingestFolders = defaults.stringArray(forKey: "ingest.folders")
            ?? [Store.isOverridden ? Store.folder.appending(path: "Inbox").path : Self.defaultIngestFolder]
        whisperModel = defaults.string(forKey: "whisper.model") ?? (Store.isOverridden ? "sidecar" : "apple")
        reminderDefault = ReminderPreset(rawValue: defaults.string(forKey: "reminder.default") ?? "") ?? .ladder
        hotkeyEnabled = defaults.object(forKey: "quick.hotkey") as? Bool ?? true
    }

    /// iCloud Drive/GrimoireInbox, where the phone Shortcut drops captures.
    static var defaultIngestFolder: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/GrimoireInbox").path
    }

    var homeName: String { didSet { defaults.set(homeName, forKey: "home.name") } }
    var homeLatitude: Double? { didSet { defaults.set(homeLatitude, forKey: "home.latitude") } }
    var homeLongitude: Double? { didSet { defaults.set(homeLongitude, forKey: "home.longitude") } }
    /// The Obsidian export folder, for example Vault/Grimoire.
    var vaultPath: String { didSet { defaults.set(vaultPath, forKey: "vault.path") } }
    var exportAfterConfirm: Bool { didSet { defaults.set(exportAfterConfirm, forKey: "vault.afterConfirm") } }
    /// Ingest folders; each has incoming/, processed/ and failed/ inside.
    var ingestFolders: [String] { didSet { defaults.set(ingestFolders, forKey: "ingest.folders") } }
    var whisperModel: String { didSet { defaults.set(whisperModel, forKey: "whisper.model") } }
    /// Reminder offered on the New Inquiry sheet and at Confirm: check-ins at 7, 30 and 90 days unless changed.
    var reminderDefault: ReminderPreset { didSet { defaults.set(reminderDefault.rawValue, forKey: "reminder.default") } }
    var hotkeyEnabled: Bool { didSet { defaults.set(hotkeyEnabled, forKey: "quick.hotkey") } }

    /// The home location for planetary days and hours, when set.
    var home: GeoLocation? {
        guard let lat = homeLatitude, let lon = homeLongitude else { return nil }
        return GeoLocation(latitude: lat, longitude: lon, name: homeName.isEmpty ? nil : homeName)
    }
}
