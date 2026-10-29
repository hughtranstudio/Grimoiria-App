import AVFoundation
import CoreServices
import Foundation
import GrimoireCore
import Speech

/// Watches every ingest folder's incoming/ with FSEvents plus a 30 s timer.
/// Scans run one at a time; new captures land in the Inbox, never filed.
final class IngestCoordinator {
    static let shared = IngestCoordinator()

    private var streams: [FSEventStreamRef] = []
    /// One ingestor per folder, kept between scans: it remembers file sizes
    /// to tell when the audio has finished arriving.
    private var ingestors: [String: InboxIngestor] = [:]
    private var timer: Timer?
    private var scanning = false
    private var again = false
    /// The last scan's problems, shown on the Inbox page.
    private(set) var problems: [String] = []

    func start() {
        restart()
    }

    func restart() {
        stop()
        ingestors = [:]
        let folders = AppModel.shared.settings.ingestFolders
        for path in folders {
            let incoming = URL(fileURLWithPath: path).appending(path: "incoming")
            try? FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
            if let stream = makeStream(incoming.path) { streams.append(stream) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { IngestCoordinator.shared.scanAll() }
        }
        scanAll()
    }

    func stop() {
        for s in streams {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
        streams = []
        timer?.invalidate()
        timer = nil
    }

    private func makeStream(_ path: String) -> FSEventStreamRef? {
        let callback: FSEventStreamCallback = { _, _, _, _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { IngestCoordinator.shared.scanAll() } }
        }
        guard let stream = FSEventStreamCreate(nil, callback, nil, [path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer))
        else { return nil }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        return stream
    }

    /// Scans every folder. A scan asked for while one runs happens right after it.
    func scanAll() {
        if scanning { again = true; return }
        scanning = true
        Task {
            await scanOnce()
            scanning = false
            if again { again = false; scanAll() }
        }
    }

    /// One pass over every folder, delivering new Inbox items. Returns what happened.
    @discardableResult
    func scanOnce() async -> [InboxIngestor.Outcome] {
        let model = AppModel.shared
        let parser = ReadingParser(library: model.library)
        let transcriber = makeTranscriber(model.settings.whisperModel)
        var all: [InboxIngestor.Outcome] = []
        for path in model.settings.ingestFolders {
            let ingestor = ingestors[path] ?? InboxIngestor(root: URL(fileURLWithPath: path), transcriber: transcriber, parser: parser)
            ingestors[path] = ingestor
            ingestor.defaultTimeZone = TimeZone.current.identifier
            ingestor.location = model.settings.home
            ingestor.attachmentsFolder = Store.attachments
            let known = KnownCaptures(model.data)
            let box = Delivered()
            let outcomes = await Self.run(ingestor, known: known, box: box)
            for item in box.items { model.repository.addToInbox(item) }
            all += outcomes
        }
        // Audio still arriving: look again once it has had time to settle.
        if all.contains(where: { if case .waiting = $0 { true } else { false } }) {
            Task {
                try? await Task.sleep(for: .seconds(4))
                scanAll()
            }
        }
        problems = all.compactMap {
            if case .failed(let file, let reason) = $0 { return "\((file as NSString).lastPathComponent): \(reason)" }
            return nil
        }
        return all
    }

    /// The scan itself runs off the main thread; it only touches thread-safe values.
    nonisolated private static func run(_ ingestor: InboxIngestor, known: KnownCaptures, box: Delivered) async -> [InboxIngestor.Outcome] {
        await ingestor.scan(isKnown: { known.contains($0) }, deliver: { box.append($0) })
    }

    func makeTranscriber(_ choice: String) -> Transcriber {
        choice == "sidecar" ? SidecarTextTranscriber() : AppleSpeechTranscriber(hints: AppModel.shared.library.speechHints(aliases: false))
    }
}

extension AppModel {
    /// Runs speech to text again on an Inbox item's audio (after installing the speech model, or
    /// when the first pass misheard) and parses the reading again. The item stays in the Inbox.
    func retranscribe(_ itemId: ULID) async -> InboxItem? {
        guard let item = data.inbox.first(where: { $0.id == itemId }),
              let audio = item.entry.attachments.first(where: { $0.kind == .audio }) else { return nil }
        let url = Store.attachments.appending(path: audio.path)
        let transcriber = IngestCoordinator.shared.makeTranscriber(settings.whisperModel == "sidecar" ? "apple" : settings.whisperModel)
        do {
            let text = try await transcriber.transcribe(url)
            guard !text.isEmpty else {
                show("Nothing was heard. Is the speech model installed (Settings > Inbox)?")
                return nil
            }
            let updated = item.retranscribed(text, parser: ReadingParser(library: library))
            repository.addToInbox(updated)
            show("Transcribed again")
            return updated
        } catch {
            show("Couldn’t transcribe: \(error.localizedDescription)")
            return nil
        }
    }
}

/// Capture ids already in the Inbox or filed, for idempotent ingest.
nonisolated private struct KnownCaptures: Sendable {
    let ids: Set<String>
    init(_ data: GrimoireData) {
        ids = Set(data.inbox.compactMap(\.entry.captureId) + data.entries.compactMap(\.captureId))
    }
    func contains(_ id: String) -> Bool { ids.contains(id) }
}

/// Items handed over by a scan, collected off the main thread.
nonisolated private final class Delivered: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [InboxItem] = []
    func append(_ item: InboxItem) { lock.withLock { list.append(item) } }
    var items: [InboxItem] { lock.withLock { list } }
}

/// On-device speech to text with Apple's SpeechAnalyzer. A transcript file
/// beside the audio (<id>.txt) wins when present. `hints` are deck, card, spread and
/// hexagram names, so "Mystagogos" or "Kun" aren't heard as everyday words.
nonisolated struct AppleSpeechTranscriber: Transcriber {
    var hints: [String] = []

    nonisolated func transcribe(_ audio: URL) async throws -> String {
        if let text = try? await SidecarTextTranscriber().transcribe(audio), !text.isEmpty { return text }
        let module = SpeechTranscriber(locale: Locale(identifier: "en-US"), preset: .transcription)
        // Without the model the capture still lands in the Inbox, with its audio and no transcript.
        guard await AssetInventory.status(forModules: [module]) == .installed else { return "" }
        let analyzer = SpeechAnalyzer(modules: [module])
        if !hints.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = hints
            try? await analyzer.setContext(context)
        }
        let file = try AVAudioFile(forReading: audio)
        let collect = Task {
            var text = ""
            for try await result in module.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collect.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Downloads Apple's on-device speech model once, when the person asks.
    static func installModel() async throws {
        let module = SpeechTranscriber(locale: Locale(identifier: "en-US"), preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
    }

    static func modelInstalled() async -> Bool {
        await AssetInventory.status(forModules: [SpeechTranscriber(locale: Locale(identifier: "en-US"), preset: .transcription)]) == .installed
    }
}
