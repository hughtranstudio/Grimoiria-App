import Foundation
import GrimoireCore

/// Sample data for snapshots: APP_SEED=1 with APP_STORE in /tmp fills an empty
/// store with records a person can make in the app.
enum SeedData {
    static let spoken = "Question: will the move go ahead. Deck Rider-Waite. Three card. One, three of cups reversed. Two, the tour. Three, page of wands. Yi Jing, coins. Seven eight nine six seven seven."

    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        guard model.data.entries.isEmpty, model.data.inquiries.isEmpty else { return }
        let repo = model.repository
        let zone = TimeZone.current.identifier
        func at(_ daysAgo: Double, _ hour: Double = 8) -> ZonedDate {
            ZonedDate(Calendar.current.startOfDay(for: .now).addingTimeInterval(-daysAgo * 86_400 + hour * 3_600), timeZone: zone)
        }
        let vol = Volume(name: "Volume III", startedOn: "2026-03-01")
        repo.save(vol)
        repo.save(Volume(name: "Volume II", startedOn: "2025-06-01", endedOn: "2026-02-28"))

        func entry(_ type: EntryType, _ title: String?, _ body: String, _ ago: Double, tags: [TagPath] = [], page: String? = nil,
                   fields: TypeFields = TypeFields(), mode: EntryMode = .reflective) -> Entry {
            let when = at(ago, 7 + ago.truncatingRemainder(dividingBy: 5))
            let e = Entry(type: type, title: title, occurredAt: when, body: body, tags: tags,
                          physicalRef: page.map { PhysicalRef(volumeId: vol.id, page: $0) },
                          timing: model.timing(at: when), mode: mode, fields: fields)
            repo.save(e)
            return e
        }
        var ritual = TypeFields()
        ritual.intention = "Open the year's work with a clean space"
        ritual.tools = ["wand", "salt", "frankincense"]
        ritual.durationMin = 40
        ritual.result = "The room felt still afterwards; a crow called at the close."
        let r = entry(.ritual, "Lesser banishing, new working space", "Performed at dawn facing east.", 0, tags: ["practice/banishing", "place/study"], page: "41", fields: ritual)
        var omen = TypeFields()
        omen.observedIn = "nature"
        omen.interpretation = "A messenger; pay attention to the next letter."
        _ = entry(.omen, nil, "Three crows on the fence at the corner of the garden", 0, tags: ["entity/ally/crow"], fields: omen, mode: .quick)
        var dream = TypeFields()
        dream.lucid = true
        dream.figures = ["entity/teacher"]
        var e = entry(.dream, "The library under the river", "A long corridor of shelves under water. The teacher handed me a key.", 1, tags: ["dream/water"], page: "43–45", fields: dream)
        e.links = [Link(.continues, to: r.id)]
        repo.save(e)
        var med = TypeFields()
        med.technique = "Inner flame"
        med.depth = 4
        med.durationMin = 25
        _ = entry(.meditation, nil, "Stillness came quickly today. Heat in the hands.", 2, tags: ["practice/stillness"], page: "47", fields: med)
        _ = entry(.journal, "Notes on the Quareia module", "Reading on thresholds and the void.\nThe point about directions keeps returning.", 3, tags: ["study/quareia"])
        var ins = TypeFields()
        ins.domain = "magical"
        _ = entry(.insight, "Thresholds are crossed twice", "Every crossing has a return path that must be walked consciously.", 5, tags: ["study/thresholds"], fields: ins)
        var vis = TypeFields()
        vis.setting = "meditation"
        vis.clarity = 3
        vis.beings = ["entity/ally/crow"]
        _ = entry(.vision, nil, "A grey landscape and a gate with no wall around it.", 8, tags: ["vision/gate"], page: "52", fields: vis)

        // A compound Inquiry: three cards and a Yi Jing cast, synthesis and an outcome.
        let asked = at(9, 21)
        let draws = [Draw(cardId: "cups-03", positionKey: "past", orientation: .reversed),
                     Draw(cardId: "maj-16", positionKey: "present"),
                     Draw(cardId: "wands-11", positionKey: "future")]
        var inq = Inquiry(question: "Will the move go ahead this year?", askedAt: asked, context: "The lease runs out in spring.",
                          category: "question/home", tags: ["life/move"],
                          divinations: [Divination(system: .cards, deckId: "rws-tarot", spreadId: "three-card", performedAt: asked, order: 0, draws: draws),
                                        Divination(system: .yijing, performedAt: asked, method: "coins", order: 1, cast: try? YiJingCast(quick: "789677"))],
                          synthesis: Synthesis(body: "Disruption first, then news. Yes, but not on the first plan.", writtenAt: asked, confidence: 3),
                          physicalRef: PhysicalRef(volumeId: vol.id, page: "40"), timing: model.timing(at: asked))
        inq.addOutcome(Outcome(recordedAt: at(2, 12), body: "The first flat fell through; a second offer came the same week.", fulfilled: .partly))
        repo.save(inq)
        repo.save(Reminder(targetId: inq.id, dueOn: model.today))

        let celtic = Inquiry(question: "What does the new working ask of me?", askedAt: at(4, 20),
                             divinations: [Divination(system: .cards, deckId: "rws-tarot", spreadId: "celtic-cross", performedAt: at(4, 20), draws: [
                                 Draw(cardId: "maj-02", positionKey: "present"), Draw(cardId: "swords-02", positionKey: "challenge"),
                                 Draw(cardId: "pentacles-04", positionKey: "foundation"), Draw(cardId: "cups-06", positionKey: "past"),
                                 Draw(cardId: "maj-17", positionKey: "crown"), Draw(cardId: "wands-03", positionKey: "near-future"),
                                 Draw(cardId: "maj-09", positionKey: "self"), Draw(cardId: "cups-10", positionKey: "environment"),
                                 Draw(cardId: "swords-08", positionKey: "hopes-fears", orientation: .reversed), Draw(cardId: "maj-21", positionKey: "outcome"),
                             ])], timing: model.timing(at: at(4, 20)))
        repo.save(celtic)

        // One capture waiting in the Inbox.
        var spokenEntry = Entry(type: .divination, occurredAt: at(0, 8.25), body: spoken, attachments: [], mode: .quick, status: .inbox,
                                captureId: "20261028-081400-4821", transcript: spoken)
        spokenEntry.timing = model.timing(at: spokenEntry.occurredAt)
        repo.addToInbox(InboxItem(entry: spokenEntry, draft: ReadingParser(library: model.library).parse(spoken), source: "phone:iPhone"))
    }
}
