import Foundation
import GrimoireCore
import Observation

/// Uranika on this Mac: the chart of each capture's moment (GrimoireCore/Uranika, docs/uranika.md).
/// Settings live in uranika-settings.json beside the store, the same file the CLI reads with
/// GRIMOIRE_URANIKA, so the app and the CLI ask Uranika the same way. Off until switched on.
@Observable
final class UranikaLink {
    static let shared = UranikaLink()

    static var settingsURL: URL { Store.folder.appending(path: "uranika-settings.json") }

    var settings: UranikaSettings { didSet { if settings != oldValue { save() } } }
    /// The last check, in words: "Open, Swiss Ephemeris 2.10" or why not.
    var status: String?
    /// Charts in Uranika's library, for choosing your own.
    var charts: [UranikaChart] = []
    @ObservationIgnored private var timer: Timer?

    init() {
        settings = (try? UranikaSettings.load(from: Self.settingsURL)) ?? UranikaSettings(enabled: false)
    }

    /// The astrologer the Inbox uses, or nil when switched off. With no Uranika home place set,
    /// charts are cast for the home place in General (the ingestor's fallback).
    var astrologer: UranikaAstrologer? {
        settings.enabled ? UranikaAstrologer(settings: settings) : nil
    }

    private func save() {
        do { try settings.save(to: Self.settingsURL) } catch { AppModel.shared.show("Couldn’t save Uranika settings: \(error.localizedDescription)") }
    }

    /// At launch and when switched on: fill pending charts now, then every 10 minutes.
    func start() {
        stop()
        guard settings.enabled else { return }
        Task { await fillPending() }
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            MainActor.assumeIsolated { Task { await UranikaLink.shared.fillPending() } }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Is Uranika open, and which charts does it hold?
    func check() async {
        let service = UranikaAstrologer(settings: settings).service
        do {
            let version = try await service.health()
            charts = try await service.charts()
            status = "Open, Swiss Ephemeris \(version)"
        } catch {
            charts = []
            status = String(describing: error)
        }
    }

    /// Completes "chart pending" entries and Inbox items once Uranika is open.
    func fillPending(report: Bool = false) async {
        guard let astro = astrologer else { return }
        let model = AppModel.shared
        let entries = await astro.fillPending(model.data.entries.filter { $0.astro?.status == .pending })
        for e in entries { model.repository.save(e) }
        let items = await astro.fillPendingInbox(model.data.inbox)
        for item in items { model.repository.addToInbox(item) }
        guard report else { return }
        let left = model.data.entries.filter { $0.astro?.status == .pending }.count
            + model.data.inbox.filter { $0.entry.astro?.status == .pending }.count
        model.show(entries.isEmpty && items.isEmpty && left > 0
                   ? "Uranika isn’t open; \(left) still pending"
                   : "\(entries.count + items.count) charts filled, \(left) still pending")
    }

    /// After Confirm: adds a filed life event to your chart's case file in Uranika, once, when that setting is on.
    func recordEvent(_ id: ULID) {
        guard let astro = astrologer, settings.recordEventsInUranika,
              let entry = AppModel.shared.entry(id), entry.type == .event else { return }
        Task {
            do {
                if let updated = try await astro.recordEvent(entry) {
                    AppModel.shared.repository.save(updated)
                    AppModel.shared.show("Added to your chart in Uranika")
                }
            } catch {
                AppModel.shared.show("Couldn’t add it to Uranika: \(error)")
            }
        }
    }
}
