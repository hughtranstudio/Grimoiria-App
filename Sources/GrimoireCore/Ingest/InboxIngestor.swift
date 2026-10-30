import Foundation

/// Watches one ingest folder's `incoming/` (spec §12). The Mac app calls `scan()` whenever
/// FSEvents reports a change and on a slow timer; the logic itself is platform-neutral.
///
/// Rules: act only on `.json` sidecars; wait until the referenced audio exists and its size
/// has been stable for `stableSeconds`; ignore iCloud placeholders but request their download;
/// re-ingesting a known capture id is a no-op; failures move to `failed/` with an `.error.txt`.
public final class InboxIngestor: @unchecked Sendable {
    public let root: URL
    public let fs: IngestFileSystem
    public let transcriber: Transcriber
    public let parser: ReadingParser
    public var stableSeconds: TimeInterval = 3
    public var defaultTimeZone: String = TimeZone.current.identifier
    public var location: GeoLocation?
    /// Attachments are copied here; the Entry stores a path relative to it.
    public var attachmentsFolder: URL?
    /// Tags suggested for observations in recorded sessions.
    public var vocabulary: TagVocabulary = .standard
    /// When set, entries get the chart of their moment from Uranika (see `UranikaAstrologer`).
    public var astrologer: UranikaAstrologer?
    /// Existing tags, used to suggest tags for life events.
    public var tagVocabulary: [TagPath] = []

    private var sizeObservations: [String: (size: Int, since: Date)] = [:]
    private let lock = NSLock()

    public var incoming: URL { root.appendingPathComponent("incoming") }
    public var processed: URL { root.appendingPathComponent("processed") }
    public var failed: URL { root.appendingPathComponent("failed") }

    public init(root: URL, fs: IngestFileSystem = LocalFileSystem(), transcriber: Transcriber, parser: ReadingParser) {
        self.root = root
        self.fs = fs
        self.transcriber = transcriber
        self.parser = parser
    }

    public enum Outcome: Equatable, Sendable {
        case ingested(captureId: String)
        case duplicate(captureId: String)
        case waiting(file: String, reason: String)
        case failed(file: String, reason: String)
    }

    /// One pass over `incoming/`. `isKnown` answers whether a capture id is already in the store;
    /// `deliver` receives each new Inbox item (the app saves it in the same call).
    public func scan(now: Date = Date(), isKnown: (String) -> Bool, deliver: (InboxItem) throws -> Void) async -> [Outcome] {
        var outcomes: [Outcome] = []
        do {
            for d in [incoming, processed, failed] where !fs.exists(d) { try fs.makeDirectory(d) }
        } catch {
            return [.failed(file: root.path, reason: "cannot create folders: \(error)")]
        }
        let names: [String]
        do { names = try fs.list(incoming) } catch { return [.failed(file: incoming.path, reason: "\(error)")] }

        for name in names where name.hasSuffix(".json") && !name.hasPrefix(".") {
            let sidecarURL = incoming.appendingPathComponent(name)
            let sidecar: CaptureSidecar
            do { sidecar = try CaptureSidecar.decode(try fs.read(sidecarURL)) }
            catch {
                outcomes.append(fail(name, reason: "\(error)", extra: []))
                continue
            }
            if isKnown(sidecar.id) {
                moveToProcessed([name] + (sidecar.audio.map { [$0] } ?? []))
                outcomes.append(.duplicate(captureId: sidecar.id))
                continue
            }
            var audioURL: URL?
            if let audio = sidecar.audio {
                let url = incoming.appendingPathComponent(audio)
                let placeholder = incoming.appendingPathComponent(".\(audio).icloud")
                if !fs.exists(url) {
                    if fs.exists(placeholder) {
                        fs.requestDownload(url)
                        outcomes.append(.waiting(file: name, reason: "audio is an iCloud placeholder; download requested"))
                    } else {
                        outcomes.append(.waiting(file: name, reason: "audio not arrived yet"))
                    }
                    continue
                }
                guard isStable(url, now: now) else {
                    outcomes.append(.waiting(file: name, reason: "audio still being written"))
                    continue
                }
                audioURL = url
            }
            do {
                let item = try await makeItem(sidecar, audio: audioURL, now: now)
                try deliver(item)
                moveToProcessed([name] + (sidecar.audio.map { [$0] } ?? []) + transcriptFile(for: sidecar))
                forget(audioURL)
                outcomes.append(.ingested(captureId: sidecar.id))
            } catch {
                outcomes.append(fail(name, reason: "\(error)", extra: (sidecar.audio.map { [$0] } ?? []) + transcriptFile(for: sidecar)))
                forget(audioURL)
            }
        }
        return outcomes
    }

    func transcriptFile(for s: CaptureSidecar) -> [String] {
        guard let a = s.audio else { return [] }
        let txt = (a as NSString).deletingPathExtension + ".txt"
        return fs.exists(incoming.appendingPathComponent(txt)) ? [txt] : []
    }

    func makeItem(_ s: CaptureSidecar, audio: URL?, now: Date) async throws -> InboxItem {
        var occurred = ZonedDate.parse(s.capturedAt, timeZone: nil)!
        // The phone only sends an offset. Prefer the Mac's IANA zone when it agrees at that instant.
        if let home = TimeZone(identifier: defaultTimeZone), home.secondsFromGMT(for: occurred.instant) == occurred.zone.secondsFromGMT(for: occurred.instant) {
            occurred.timeZone = home.identifier
        }
        if let ss = s.session { return try await makeSessionItem(s, ss, occurred: occurred, audio: audio, now: now) }
        if s.isOutcome { return try await makeOutcomeItem(s, occurred: occurred, audio: audio, now: now) }
        var transcript: String?
        if let phone = s.transcript, !phone.isEmpty { transcript = phone }
        else if let audio { transcript = try await transcriber.transcribe(audio) }
        let spoken = [s.text, transcript].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")

        var draft: DraftReading?
        // A reading already checked on the phone is kept as is; Confirm still happens here.
        let parsed = s.draft ?? parser.parse(spoken)
        if !parsed.isEmpty || s.expectsReading {
            draft = parsed
            if s.expectsReading && parsed.isEmpty {
                draft?.warnings.append("Capture was marked \(s.kindHint ?? "") but no deck or Yi Jing lines were heard")
            }
        }
        // Draws typed on the phone (rare) go into the draft too.
        if let sd = s.draws, !sd.isEmpty {
            var d = draft ?? DraftReading()
            for (deckId, group) in Dictionary(grouping: sd, by: \.deck).sorted(by: { $0.key < $1.key }) {
                let spread = parser.library.freeform
                d.divinations.append(DraftDivination(system: .cards, deckId: Parsed(deckId, confidence: .high),
                    spreadId: Parsed(spread.id, confidence: .high),
                    draws: group.enumerated().map { i, g in
                        DraftDraw(cardId: Parsed(g.card, confidence: .high), orientation: Parsed(g.orientation ?? .upright, confidence: .high), positionKey: spread.positionKey(at: i))
                    }, heard: "sidecar"))
            }
            draft = d
        }

        var attachments: [Attachment] = []
        if let audio {
            attachments.append(Attachment(kind: .audio, path: try copyAudio(audio), originalName: audio.lastPathComponent))
        }
        let tags: [TagPath] = (s.tags ?? []).map { TagPath($0) }.filter { !$0.isEmpty }
        let sidecarLocation: GeoLocation? = s.location.map { GeoLocation(latitude: $0.lat, longitude: $0.lon) }
        let uranikaHome = astrologer?.settings.home.map { GeoLocation(latitude: $0.latitude, longitude: $0.longitude, name: $0.name) }
        let timing = TimingContext.compute(at: occurred, location: location ?? uranikaHome ?? sidecarLocation)
        var entry = Entry(id: ULID(date: occurred.instant), type: s.entryType, occurredAt: occurred, createdAt: now,
                          body: spoken, tags: tags, attachments: attachments, timing: timing,
                          mode: .quick, status: .inbox, captureId: s.id, transcript: transcript)
        if let iid = s.inquiryId, let u = ULID(iid) { entry.inquiryId = u }
        var notes: [String] = []
        // Only untyped captures (or the phone's Event button) are read as life events; a chosen type wins.
        let hint = s.kindHint?.lowercased()
        if hint == nil || hint == "event", draft?.divinations.isEmpty != false, let event = LifeEvent.detect(spoken, kindHint: s.kindHint, vocabulary: tagVocabulary) {
            entry.type = .event
            entry.title = event.title
            for t in event.tags where !entry.tags.contains(t) { entry.tags.append(t) }
            if s.kindHint?.lowercased() != "event" { notes.append("Filed as a life event because it starts like one; change the type if not") }
        }
        if let astro = astrologer, astro.applies(to: entry.type) {
            let snap = await astro.snapshot(at: occurred, place: astro.place(captured: sidecarLocation, fallback: location), now: now)
            entry.astro = snap
            if snap.status == .pending, let n = snap.note { notes.append(n) }
        }
        return InboxItem(entry: entry, draft: draft, source: "phone:\(s.device ?? "unknown")", notes: notes)
    }

    /// Copies the audio into the attachments folder; returns the path the Entry stores.
    func copyAudio(_ audio: URL) throws -> String {
        guard let folder = attachmentsFolder else { return audio.lastPathComponent }
        let rel = "audio/\(audio.lastPathComponent)"
        let dest = folder.appendingPathComponent(rel)
        try fs.makeDirectory(dest.deletingLastPathComponent())
        try fs.write(try fs.read(audio), to: dest)
        return rel
    }

    /// A recorded session from the phone: phases and markers from the sidecar, observations from
    /// the timed transcript (the phone's, or the Mac's own when it sent none).
    func makeSessionItem(_ s: CaptureSidecar, _ ss: CaptureSidecar.SidecarSession, occurred: ZonedDate, audio: URL?, now: Date) async throws -> InboxItem {
        let zone = occurred.timeZone
        var start = ss.startedAt.flatMap { ZonedDate.parse($0) } ?? occurred
        start.timeZone = zone
        let type = EntryType.sessionTypes.contains(s.entryType) ? s.entryType : .meditation
        var recorder = SessionRecorder(type: type, startedAt: start, intention: ss.intention, technique: ss.technique,
                                       tags: (s.tags ?? []).map { TagPath($0) }.filter { !$0.isEmpty }, before: ss.before, firstPhase: nil)
        for m in (ss.marks ?? []).sorted(by: { $0.offsetS < $1.offsetS }) {
            let at = start.instant.addingTimeInterval(m.offsetS)
            if let p = m.phase { recorder.setPhase(p, at: at) }
            if let k = m.kind ?? (m.text?.isEmpty == false ? .note : nil) {
                recorder.observe(k, m.text ?? "", tags: (m.tags ?? []).map { vocabulary.canonical(TagPath($0)) }.filter { !$0.isEmpty }, at: at)
            } else if m.phase == nil {
                recorder.mark(at: at)
            }
        }
        var segments = ss.segments ?? []
        if segments.isEmpty, let phone = s.transcript, !phone.isEmpty { segments = TimedTranscript.parse(phone) }
        if segments.isEmpty, let audio { segments = try await transcriber.timedSegments(audio) }
        // No end time sent: the session ran at least until its last mark or words.
        let lastOffset = max(ss.marks?.map(\.offsetS).max() ?? 0, segments.map(\.offset).max() ?? 0)
        let end = ss.endedAt.flatMap { ZonedDate.parse($0) }?.instant ?? start.instant.addingTimeInterval(lastOffset)
        recorder.finish(at: end, after: ss.after, outcome: ss.outcome ?? s.text)

        let extractor = ObservationExtractor(vocabulary: vocabulary)
        let source = "phone:\(s.device ?? "unknown")"
        let recording = try audio.map { SessionRecording(path: try copyAudio($0), offset: 0, duration: recorder.session.duration, segments: segments) }
        let item = recorder.inboxItem(recording: recording, extractor: extractor, timing: timing(start, s), source: source, captureId: s.id, now: now)
        // A transcript with no audio (typed or dictated on the phone) still becomes observations.
        if recording == nil, !segments.isEmpty { return SessionAssembler.retranscribed(item, segments: segments, extractor: extractor) }
        return item
    }

    /// An outcome typed or spoken on the phone for a reading it browsed. Waits in the Inbox like
    /// any capture; Confirm stacks it on the reading.
    func makeOutcomeItem(_ s: CaptureSidecar, occurred: ZonedDate, audio: URL?, now: Date) async throws -> InboxItem {
        var transcript: String?
        if let phone = s.transcript, !phone.isEmpty { transcript = phone }
        else if let audio { transcript = try await transcriber.transcribe(audio) }
        let body = [s.text, transcript].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        let attachments = try audio.map { [Attachment(kind: .audio, path: try copyAudio($0), originalName: $0.lastPathComponent)] } ?? []
        var entry = Entry(id: ULID(date: occurred.instant), type: .journal, title: "Outcome", occurredAt: occurred, createdAt: now,
                          body: body, tags: (s.tags ?? []).map { TagPath($0) }.filter { !$0.isEmpty }, attachments: attachments,
                          mode: .quick, status: .inbox, captureId: s.id, transcript: transcript)
        entry.inquiryId = s.inquiryId.flatMap { ULID($0) }
        let fulfilled = s.outcome?.fulfilled ?? .unclear
        let outcome = GrimoireCore.Outcome(id: ULID(date: occurred.instant), recordedAt: occurred, body: body, fulfilled: fulfilled)
        return InboxItem(entry: entry, draft: nil, source: "phone:\(s.device ?? "unknown")",
                         notes: ["Outcome (\(fulfilled.rawValue)) for reading \(s.inquiryId ?? ""). Confirm adds it to that reading."],
                         outcome: outcome)
    }

    func timing(_ at: ZonedDate, _ s: CaptureSidecar) -> TimingContext {
        TimingContext.compute(at: at, location: location ?? s.location.map { GeoLocation(latitude: $0.lat, longitude: $0.lon) })
    }

    func isStable(_ url: URL, now: Date) -> Bool {
        guard let size = fs.size(url) else { return false }
        lock.lock(); defer { lock.unlock() }
        if let prev = sizeObservations[url.path], prev.size == size {
            return now.timeIntervalSince(prev.since) >= stableSeconds
        }
        sizeObservations[url.path] = (size, now)
        return stableSeconds <= 0
    }

    func forget(_ url: URL?) {
        guard let url else { return }
        lock.lock(); sizeObservations[url.path] = nil; lock.unlock()
    }

    func moveToProcessed(_ files: [String]) {
        for f in files {
            let from = incoming.appendingPathComponent(f)
            if fs.exists(from) { try? fs.move(from, to: processed.appendingPathComponent(f)) }
        }
    }

    func fail(_ sidecar: String, reason: String, extra: [String]) -> Outcome {
        for f in [sidecar] + extra {
            let from = incoming.appendingPathComponent(f)
            if fs.exists(from) { try? fs.move(from, to: failed.appendingPathComponent(f)) }
        }
        let errFile = failed.appendingPathComponent((sidecar as NSString).deletingPathExtension + ".error.txt")
        try? fs.write(Data((reason + "\n").utf8), to: errFile)
        return .failed(file: sidecar, reason: reason)
    }
}
