import Foundation
import GrimoireCore

/// Keeps `library/` in each phone ingest folder up to date (docs/phone-library.md), a few seconds
/// after the last change, so the Pixel can browse what's filed. iCloud Drive folders are skipped:
/// the library goes only where Syncthing carries it, never to a cloud.
final class PhoneLibrarySync {
    static let shared = PhoneLibrarySync()
    private var pending: Task<Void, Never>?

    /// Folders that get a library: ingest folders outside iCloud Drive.
    static func folders(_ settings: AppSettings) -> [String] {
        guard settings.sharePhoneLibrary else { return [] }
        return settings.ingestFolders.filter { !$0.contains("/Library/Mobile Documents/") }
    }

    func schedule() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            publishNow()
        }
    }

    func publishNow() {
        let model = AppModel.shared
        let folders = Self.folders(model.settings)
        guard !folders.isEmpty, !Store.isOverridden else { return }
        var filed = model.data
        filed.inbox = []
        let writer = PhoneLibrary(library: model.library, vocabulary: model.vocabulary)
        for path in folders {
            do { try writer.write(filed, to: URL(fileURLWithPath: path, isDirectory: true)) }
            catch { model.show("Couldn’t update the phone’s library in \((path as NSString).lastPathComponent): \(error.localizedDescription)") }
        }
    }
}
