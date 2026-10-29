import AVFoundation
import Foundation
import GrimoireAppKit
import GrimoireCore
import Observation

/// The session being recorded: setup, the running clock and microphone, the closing notes, and
/// the hand-off to the Inbox. One at a time; the Session window and the Session menu share it.
@Observable
final class SessionController {
    static let shared = SessionController()

    enum Stage { case setup, running, finishing, saving }

    var stage: Stage = .setup
    // Setup
    var type: EntryType = .meditation
    var intention = ""
    var technique = ""
    var tagsText = ""
    var before = StateCheck()
    var recordAudio = true
    // Running and after
    private(set) var recorder: SessionRecorder?
    var kind: ObservationKind = .imagery
    var text = ""
    var observationTags = ""
    var after = StateCheck()
    var outcome = ""
    var interrupted = false
    /// Why there is no audio, shown in the window.
    var micProblem: String?
    private(set) var audioURL: URL?
    @ObservationIgnored private var audio: AVAudioRecorder?
    @ObservationIgnored private var endedAt: Date?

    var isRunning: Bool { stage == .running }
    var session: PracticeSession? { recorder?.session }

    // MARK: Clock

    func start(model: AppModel) async {
        let at = model.now()
        recorder = SessionRecorder(type: type, startedAt: at, intention: intention, technique: technique,
                                   tags: TagInput.parse(tagsText).map(model.vocabulary.canonical), before: before)
        micProblem = nil
        if recordAudio {
            if await AVCaptureDevice.requestAccess(for: .audio) {
                startAudio(named: "session-\(ULID(date: at.instant))")
            } else {
                micProblem = "Grimoire can’t use the microphone, so this session has no audio. Allow it in System Settings > Privacy & Security > Microphone."
            }
        }
        stage = .running
    }

    private func startAudio(named name: String) {
        let url = Store.attachments.appending(path: "audio/\(name).m4a")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            if r.record() {
                audio = r
                audioURL = url
            } else {
                micProblem = "The microphone didn’t start, so this session has no audio."
            }
        } catch {
            micProblem = "The microphone didn’t start (\(error.localizedDescription)), so this session has no audio."
        }
    }

    func elapsed(at date: Date) -> Double { recorder?.elapsed(at: endedAt ?? date) ?? 0 }

    func setPhase(_ phase: SessionPhase) { recorder?.setPhase(phase, at: .now) }

    /// "Something happened here", to fill in afterwards.
    func mark() {
        guard isRunning else { return }
        recorder?.mark(at: .now)
    }

    /// Adds the typed observation: live while running, recalled once the clock has stopped.
    func addObservation(vocabulary: TagVocabulary) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, recorder != nil else { return }
        recorder?.observe(kind, t, tags: SessionText.tags(typed: observationTags, text: t, vocabulary: vocabulary), at: .now)
        text = ""
        observationTags = ""
    }

    func removeObservation(_ id: ULID) { recorder?.remove(id) }

    /// Stops the clock and the microphone; the closing notes come next.
    func end() {
        guard isRunning else { return }
        audio?.stop()
        endedAt = .now
        recorder?.finish(at: endedAt!)
        stage = .finishing
    }

    // MARK: Saving

    /// Transcribes the audio, turns what was said into draft observations, and puts the session in
    /// the Inbox for checking. Returns the Inbox item's id.
    @discardableResult
    func save(model: AppModel) async -> ULID? {
        guard var r = recorder, let endedAt else { return nil }
        stage = .saving
        r.finish(at: endedAt, after: after, outcome: outcome, interrupted: interrupted)
        var recording: SessionRecording?
        if let url = audioURL {
            let rel = "audio/\(url.lastPathComponent)"
            let transcriber = IngestCoordinator.shared.makeTranscriber(model.settings.whisperModel == "sidecar" ? "apple" : model.settings.whisperModel)
            let segments = (try? await transcriber.timedSegments(url)) ?? []
            recording = SessionRecording(path: rel, offset: 0, duration: r.session.duration, segments: segments)
        }
        let item = r.inboxItem(recording: recording, extractor: ObservationExtractor(vocabulary: model.vocabulary),
                               timing: model.timing(at: r.session.startedAt))
        model.repository.addToInbox(item)
        model.page = .inbox
        model.selection = .inbox(item.id)
        model.show("Session is in the Inbox to check")
        reset()
        return item.id
    }

    /// Throws the session away, audio included.
    func discard() {
        audio?.stop()
        if let url = audioURL { try? FileManager.default.removeItem(at: url) }
        reset()
    }

    private func reset() {
        audio = nil
        audioURL = nil
        endedAt = nil
        recorder = nil
        micProblem = nil
        intention = ""
        technique = ""
        tagsText = ""
        before = StateCheck()
        after = StateCheck()
        outcome = ""
        interrupted = false
        text = ""
        observationTags = ""
        stage = .setup
    }
}

extension AppModel {
    var vocabularyURL: URL { Store.folder.appending(path: "tag-vocabulary.json") }

    func loadVocabulary() {
        vocabulary = TagVocabulary.standard(withUserFile: vocabularyURL)
    }

    /// Adds a free tag to your own vocabulary file, so it counts as controlled from now on.
    func promoteTag(_ tag: TagPath) {
        var mine = (try? TagVocabulary.load(from: vocabularyURL)) ?? TagVocabulary(terms: [])
        mine.add(tag)
        do {
            try mine.json().write(to: vocabularyURL, atomically: true, encoding: .utf8)
            loadVocabulary()
            show("“\(tag.path)” is in the vocabulary")
        } catch {
            show("Couldn’t save the vocabulary: \(error.localizedDescription)")
        }
    }

    /// Writes your vocabulary file if there is none yet, and returns where it is.
    func ensureVocabularyFile() -> URL {
        if !FileManager.default.fileExists(atPath: vocabularyURL.path) {
            try? TagVocabulary(terms: []).json().write(to: vocabularyURL, atomically: true, encoding: .utf8)
        }
        return vocabularyURL
    }

    /// Makes a Contact or Omen entry from a session observation, linked both ways. Returns its id.
    func makeEntry(from observation: Observation, in sessionEntry: Entry, as type: EntryType) -> ULID {
        let at = sessionEntry.session.map { $0.time(of: observation) } ?? sessionEntry.occurredAt
        var e = Entry(type: type, title: observation.text.isEmpty ? nil : observation.text, occurredAt: at,
                      body: observation.text, tags: observation.tags, links: [Link(.related, to: sessionEntry.id)],
                      timing: timing(at: at))
        if type == .contact { e.fields.being = observation.tags.first { $0.isUnder("entity") } }
        if type == .omen { e.fields.observedIn = "other" }
        repository.save(e)
        return e.id
    }

    /// Saves an edited Inbox item (a session's observations checked before Confirm).
    func updateInbox(_ item: InboxItem) {
        repository.addToInbox(item)
    }
}
