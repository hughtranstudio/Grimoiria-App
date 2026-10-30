import AppKit
import Foundation
import GrimoireAppKit
import GrimoireCore

/// Self-test for agents: runs the app's real functions on a test store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/Grimoire-self.store ~/Applications/Grimoire.app/Contents/MacOS/Grimoire --selftest
/// (tools/selftest.sh does this, then relaunches with --selftest-reopen for the relaunch checks.)
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") || reopen }
    static var reopen: Bool { CommandLine.arguments.contains("--selftest-reopen") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            if reopen { await relaunchChecks(model) } else { await firstRunChecks(model) }
            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    // MARK: First run

    private static func firstRunChecks(_ model: AppModel) async {
        // M1: definitions
        check("definitions validate at launch", model.definitionsReport?.isValid == true, model.definitionsError ?? "")
        check("4 decks and 8 spreads", model.library.decks.count == 4 && model.library.spreads.count == 8)
        check("Quareia has 81 cards and Mystagogos is a placeholder",
              model.library.deck("quareia")?.cards.count == 81 && model.library.deck("mystagogos")?.status == .placeholder)
        check("definitions copied to the store folder", FileManager.default.fileExists(atPath: Store.definitions.appending(path: "yijing.json").path))

        // M2: one of each non-divination type, with tags, a page and a link
        let vol = Volume(name: "Volume III")
        model.repository.save(vol)
        var ids: [ULID] = []
        for (i, t) in EntryType.creatable.enumerated() {
            var e = model.newEntry(t, body: "Self-test \(t.rawValue)", tags: [TagPath("selftest/\(t.rawValue)")])
            e.physicalRef = PhysicalRef(volumeId: vol.id, page: String(38 + i * 2))
            if let prev = ids.last { e.links = [Link(.related, to: prev)] }
            model.stage(e)
            ids.append(e.id)
        }
        model.flushEdits()
        check("created one record of each of the 8 types", Set(model.timelineEntries.map(\.type)).count == 8)
        check("timing computed at save", model.timelineEntries.allSatisfy { $0.timing != nil })
        check("parent tag finds children", model.search("#selftest").count == 8)
        check("tag autocomplete", model.tagTree.suggestions(for: "selftest/dr").first?.path == "selftest/dream")
        check("backlinks", model.repository.backlinks(to: ids[0]).first?.source == ids[1])

        // M3: compound Inquiry, 1-week reminder, outcome
        let inq = model.newInquiry(question: "Self-test: will the move go ahead?", reminder: .preset(.oneWeek))
        var i = inq
        i.divinations = [
            Divination(system: .cards, deckId: "rws-tarot", spreadId: "three-card", performedAt: inq.askedAt, order: 0,
                       draws: [Draw(cardId: "cups-03", positionKey: "past", orientation: .reversed),
                               Draw(cardId: "maj-16", positionKey: "present"), Draw(cardId: "wands-11", positionKey: "future")]),
            Divination(system: .yijing, performedAt: inq.askedAt, order: 1, cast: try? YiJingCast(quick: "789677")),
        ]
        i.synthesis = Synthesis(body: "Upheaval, then news.", writtenAt: inq.askedAt, confidence: 3)
        model.stage(i)
        model.flushEdits()
        let reminder = model.data.reminders.first { $0.targetId == inq.id }
        check("1-week reminder saved", reminder?.dueOn == ReminderPreset.oneWeek.dueOn(from: inq.askedAt.day))
        let weekLater = ReminderPreset.oneWeek.dueOn(from: model.today)!
        check("Needs outcome lists it when due", model.repository.needsOutcome(today: weekLater).contains { $0.targetId == inq.id })
        check("cast hexagrams 1 → …", model.inquiry(inq.id)?.divinations[1].cast?.primaryHexagram(in: model.library.yijing) != nil)
        check("card names are searchable", model.search("tower").contains(.inquiry(inq.id)))
        model.addOutcome(to: inq.id, Outcome(recordedAt: model.now(), body: "It went ahead.", fulfilled: .yes))
        model.addOutcome(to: inq.id, Outcome(recordedAt: model.now(), body: "Moved in.", fulfilled: .yes))
        check("outcomes stack and status moves to revisited",
              model.inquiry(inq.id)?.outcomes.count == 2 && model.inquiry(inq.id)?.status == .revisited)
        if let r = reminder {
            model.snooze(r.id)
            check("snooze moves the reminder 3 days", model.data.reminders.first { $0.id == r.id }?.status == .snoozed)
        }

        // Check-ins at 7, 30 and 90 days
        let laddered = model.newInquiry(question: "Self-test: check-ins", reminder: .preset(.ladder), select: false)
        let rung = model.data.reminders.first { $0.targetId == laddered.id }
        check("7/30/90 check-in starts at 7 days", rung?.repeat == .ladder && rung?.step == 7, "\(String(describing: rung))")
        model.addOutcome(to: laddered.id, Outcome(recordedAt: ZonedDate(Calendar.current.date(byAdding: .day, value: 8, to: .now)!,
                                                                        timeZone: TimeZone.current.identifier), body: "Early news.", fulfilled: .partly))
        check("an outcome rolls the check-in on to 30 days", model.data.reminders.first { $0.targetId == laddered.id }?.step == 30)

        // M4: quick log
        let started = Date.now
        let omen = model.quickSave(.omen, text: "Crow on the gate", tags: ["entity/ally/crow"])
        check("quick omen with one tag", omen.flatMap(model.entry)?.tags == ["entity/ally/crow"] && omen.flatMap(model.entry)?.mode == .quick)
        check("quick log saves in under 20 s", Date.now.timeIntervalSince(started) < 20)
        let draw = model.quickSave(.cardDraw, text: "3 cups r, tower", tags: [], deckId: "rws-tarot", spreadId: "three-card")
        check("quick draw parses two cards", draw.flatMap(model.inquiry)?.divinations.first?.draws.map(\.cardId) == ["cups-03", "maj-16"])
        let cast = model.quickSave(.yijing, text: "789677", tags: [])
        check("quick cast", cast.flatMap(model.inquiry)?.divinations.first?.cast?.lines == [7, 8, 9, 6, 7, 7])

        // M5: volumes and page ranges
        let inRange = model.search("Volume III pp. 40–50")
        check("Volume III pp. 40–50 finds pages 40 to 50", inRange.count == 6, "found \(inRange.count)")
        check("volume page list", model.records(in: vol.id, pages: 40...50).count == 6)

        // Page photos: a stack of photos becomes physical-only records, pages counted on
        let shots = Store.folder.appending(path: "shots")
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        let photoFiles = (1...2).map { shots.appending(path: "IMG_00\($0).jpg") }
        for (n, f) in photoFiles.enumerated() { try? Data("page \(n)".utf8).write(to: f) }
        let indexed = (try? model.indexPages(volumeId: vol.id, photos: photoFiles, firstPage: "60")) ?? []
        check("page photos index pages 60 and 61", indexed.map { $0.physicalRef?.page } == ["60", "61"])
        check("page photo copied into Attachments",
              indexed.first?.physicalRef?.photo.map { FileManager.default.fileExists(atPath: Store.attachments.appending(path: $0.path).path) } == true)
        check("next page after 61 is 62", model.nextPage(in: vol.id) == "62")
        check("Volume III p. 61 finds the photo record", model.search("Volume III p. 61") == indexed.suffix(1).map { .entry($0.id) })

        // M6: export, byte-stable
        let vault = Store.folder.appending(path: "Vault/Grimoire")
        try? FileManager.default.removeItem(at: vault)
        let first = model.exportNow(to: vault, quiet: true)
        check("export writes files", (first?.written.count ?? 0) > 10)
        let note = (try? FileManager.default.contentsOfDirectory(atPath: vault.appending(path: "Inquiries").path))?.first
        let text = note.flatMap { try? String(contentsOf: vault.appending(path: "Inquiries/\($0)"), encoding: .utf8) } ?? ""
        check("notes start with YAML frontmatter", text.hasPrefix("---\n") && text.dropFirst(4).contains("\n---\n"))
        check("grimoire.jsonl written", FileManager.default.fileExists(atPath: vault.appending(path: "grimoire.jsonl").path))
        let second = model.exportNow(to: vault, quiet: true)
        check("second export writes 0 files", second?.written.isEmpty == true, "\(second?.written ?? [])")
        check("card notes written", FileManager.default.fileExists(atPath: vault.appending(path: "Cards/rws-tarot-maj-16-the-tower.md").path))
        check("ML files written", FileManager.default.fileExists(atPath: vault.appending(path: "ML/draws.jsonl").path))
        let ownNote = vault.appending(path: "My own note.md")
        try? Data("Mine.".utf8).write(to: ownNote)
        let doomed = model.newEntry(.dream, body: "Self-test: deleted later", select: false)
        model.exportNow(to: vault, quiet: true)
        model.delete(doomed.id)
        let pruned = model.exportNow(to: vault, quiet: true)
        check("export removes the note of a deleted record", pruned?.removed.count == 1, "\(pruned?.removed ?? [])")
        check("export keeps your own notes", FileManager.default.fileExists(atPath: ownNote.path))

        // M7: ingest, no duplicates, nothing filed before Confirm
        await ingestChecks(model)

        // Import documents into the Inbox, never filed directly
        let doc = Store.folder.appending(path: "Magical diary.md")
        try? Data("# Magical diary\n\n## 3/4/2025\nLesser banishing at dawn.\n\n## 3/5/2025\nDrew the Tower and three of cups reversed.\n".utf8).write(to: doc)
        let inboxBefore = model.data.inbox.count, filedNow = model.data.entries.count
        model.importDocuments([doc])
        check("import splits a document into 2 Inbox entries", model.data.inbox.count == inboxBefore + 2)
        check("import files nothing", model.data.entries.count == filedNow)
        check("import reads month-first dates", model.data.inbox.contains { $0.entry.occurredAt.day == "2025-03-04" })
        let reimport = model.importDocuments([doc])
        // Patterns, browse, calendar, correspondences
        let p = model.patterns
        check("patterns count the Tower", p.cardCounts(deckId: "rws-tarot").contains { $0.key == "maj-16" })
        model.browse(card: "rws-tarot", "maj-16")
        check("browse by card finds the reading", model.search("").contains(.inquiry(inq.id)))
        let hex = model.inquiry(inq.id)?.divinations[1].cast?.primaryHexagram(in: model.library.yijing) ?? 0
        model.browse(hexagram: hex)
        check("browse by hexagram", model.search("").contains(.inquiry(inq.id)))
        model.searchHexagram = nil
        check("calendar month has every day", model.calendarDays.count >= 28)
        check("calendar shows lunar phases", model.calendarDays.flatMap(\.events).contains { $0.isPhase })
        check("correspondences loaded", model.library.correspondences?.search("iron").first?.id == "planet:mars")
        check("Mars has the Tower", model.library.cards(for: model.library.correspondences!.entry("planet:mars")!).first?.card.id == "maj-16")
        check("importing again makes no duplicates", reimport.allSatisfy { if case .duplicate = $0 { true } else { false } } && model.data.inbox.count == inboxBefore + 2)

        await sessionChecks(model)
    }

    /// Session recording: clock and observations, Inbox first, then filed with its log.
    private static func sessionChecks(_ model: AppModel) async {
        let session = SessionController.shared
        session.type = .vision
        session.intention = "Self-test vision"
        session.recordAudio = false
        await session.start(model: model)
        check("session starts running", session.isRunning)
        session.setPhase(.working)
        session.mark()
        session.kind = .entity
        session.text = "A crow at the gate"
        session.addObservation(vocabulary: model.vocabulary)
        check("typed observation gets vocabulary tags", session.session?.observations.last?.tags.map(\.path) == ["entity/animal/crow", "place/gate"])
        session.end()
        session.outcome = "Came back calm."
        let filedBefore = model.data.entries.count
        let itemId = await session.save(model: model)
        check("session goes to the Inbox, not filed", itemId.map { id in model.data.inbox.contains { $0.id == id } } == true && model.data.entries.count == filedBefore)
        guard let itemId else { return }
        let filed = try? model.confirm(itemId, corrected: nil, entryType: nil)
        let entry = filed.flatMap { model.entry($0) }
        check("confirmed session keeps its observations", entry?.session?.observations.count == 2 && entry?.session?.outcome == "Came back calm.")
        check("observations are searchable", model.search("crow at the gate").contains(.entry(itemId)))
        if let entry, let crow = entry.session?.observations.last {
            let contact = model.makeEntry(from: crow, in: entry, as: .contact)
            check("contact entry from an observation", model.entry(contact)?.fields.being?.path == "entity/animal/crow")
        }
        let export = try? MLExporter(library: model.library).files(for: model.data)
        check("ML export has the observation rows", export?["ML/observations.csv"]?.contains("A crow at the gate") == true)
    }

    private static func ingestChecks(_ model: AppModel) async {
        let folder = URL(fileURLWithPath: model.settings.ingestFolders[0])
        let incoming = folder.appending(path: "incoming")
        try? FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        let id = "20261028-081400-4821"
        // The spoken RWS example from GrimoireCore's capture fixture.
        let spokenRWS = "Question: will the move go ahead? Deck Rider-Waite, three card: three of cups reversed, the Tower, page of wands."
        func drop() {
            let sidecar = #"{"contract_version":1,"id":"\#(id)","captured_at":"2026-10-28T08:14:00-07:00","device":"iPhone","kind_hint":"draw","audio":"\#(id).m4a"}"#
            try? Data(sidecar.utf8).write(to: incoming.appending(path: "\(id).json"))
            try? Data(repeating: 1, count: 2048).write(to: incoming.appending(path: "\(id).m4a"))
            try? Data(spokenRWS.utf8).write(to: incoming.appending(path: "\(id).txt"))
        }
        let filedBefore = model.data.entries.count
        drop()
        var outcomes: [InboxIngestor.Outcome] = []
        for _ in 0..<6 where !outcomes.contains(.ingested(captureId: id)) {
            outcomes = await IngestCoordinator.shared.scanOnce()
            try? await Task.sleep(for: .seconds(1.2))
        }
        check("capture lands in the Inbox", model.data.inbox.contains { $0.entry.captureId == id }, "\(outcomes)")
        let item = model.data.inbox.first { $0.entry.captureId == id }
        check("transcript read", item?.entry.transcript?.contains("three of cups") == true)
        check("spoken RWS example gives 3 draft draws", item?.draft?.divinations.first?.draws.count == 3)
        check("nothing filed before Confirm", model.data.entries.count == filedBefore)
        drop()
        let again = await IngestCoordinator.shared.scanOnce()
        check("dropping it again makes no duplicate",
              again.contains(.duplicate(captureId: id)) && model.data.inbox.filter { $0.entry.captureId == id }.count == 1)
        if let item, var draft = item.draft {
            // A card left empty: Confirm refuses until it is chosen.
            var empty = draft
            empty.divinations[0].draws[1].cardId = .missing
            check("Confirm refuses a missing card", (try? model.confirm(item.id, corrected: empty, entryType: nil)) == nil)
            check("refused capture stays in the Inbox", model.data.inbox.contains { $0.id == item.id })
            // Correct one orientation, as a person would in the Inbox.
            draft.divinations[0].draws[2].orientation = Parsed(.reversed, confidence: .high)
            let filed = try? model.confirm(item.id, corrected: draft, entryType: nil)
            check("Confirm files the Inquiry", filed.flatMap(model.inquiry)?.divinations.first?.draws.count == 3)
            check("Inbox empties after Confirm", !model.data.inbox.contains { $0.id == item.id })
            check("correction logged", model.data.corrections.contains { $0.field == "orientation" })
        }
    }

    // MARK: After relaunch

    private static func relaunchChecks(_ model: AppModel) async {
        check("all 8 types still present after relaunch", Set(model.timelineEntries.map(\.type)).count == 8)
        check("inquiries still present", model.data.inquiries.contains { $0.question.hasPrefix("Self-test") })
        check("volume still present", model.data.volumes.contains { $0.name == "Volume III" })
        check("filed capture still present", model.data.entries.contains { $0.captureId == "20261028-081400-4821" })
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
