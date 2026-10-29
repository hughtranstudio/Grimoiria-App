import Foundation
import GrimoireAppKit
import GrimoireCore

/// Everything an agent can do in Grimoire: the commands of the `grimoire`
/// CLI in GrimoireCore, pointed at the running app's store. Each `run` uses
/// the same model code as the window, so the window updates live.
enum AgentCommands {
    static let pages = SidebarPage.allCases.map(\.rawValue).joined(separator: ", ")
    static let types = EntryType.allCases.map(\.rawValue).joined(separator: ", ")

    static let all: [AgentCommand] = [
        AgentCommand(name: "status", summary: "Show the open page and record counts.",
                     example: "grimoire status --json", readOnly: true) { _, model in
            ["running": true, "page": model.page?.rawValue ?? "none", "entries": model.timelineEntries.count,
             "inquiries": model.data.inquiries.count, "inbox": model.data.inbox.count, "volumes": model.data.volumes.count,
             "needsOutcome": model.repository.needsOutcome(today: model.today).count]
        },
        AgentCommand(name: "open", summary: "Show a sidebar page, or a record by id, in the window.",
                     params: [.init(name: "target", required: true, positional: true, help: "a page (\(pages)) or a record id")],
                     example: "grimoire open inbox") { args, model in
            let target = try args.required("target")
            if let page = SidebarPage(rawValue: target) { model.page = page; return ["page": page.rawValue] }
            let id = try find(target, in: model)
            model.reveal(id)
            return ["shown": id.string]
        },
        AgentCommand(name: "validate", summary: "Check decks, spreads and Yi Jing in the Definitions folder.",
                     example: "grimoire validate --json", readOnly: true) { _, model in
            let r = model.library.validate()
            return ["valid": r.isValid, "errors": r.errors, "warnings": r.warnings,
                    "decks": model.library.decks.map { ["id": $0.id, "name": $0.name, "status": $0.status.rawValue, "cards": $0.cards.count] }]
        },
        AgentCommand(name: "parse", summary: "Parse a spoken or typed reading into a draft, without saving.",
                     params: [.init(name: "text", required: true, positional: true, help: "the transcript")],
                     example: "grimoire parse \"Deck Rider-Waite. Three card. Three of cups reversed, the Tower, page of wands.\" --json",
                     readOnly: true) { args, model in
            try encoded(ReadingParser(library: model.library).parse(try args.required("text")))
        },
        AgentCommand(name: "cast", summary: "Show the hexagrams of six line values, without saving.",
                     params: [.init(name: "lines", required: true, positional: true, help: "six digits 6–9, bottom to top")],
                     example: "grimoire cast 789677 --json", readOnly: true) { args, model in
            let cast = try castOf(try args.required("lines"))
            return castJSON(cast, model)
        },
        AgentCommand(name: "timing", summary: "Moon, Sun, planetary day and hour for a moment (now by default).",
                     params: [.init(name: "at", positional: true, help: "ISO 8601 time like 2026-10-28T08:14:00-07:00")],
                     example: "grimoire timing 2026-10-28T08:14:00-07:00 --json", readOnly: true) { args, model in
            let at = try args.string("at").map { s -> ZonedDate in
                guard let d = ZonedDate.parse(s) else { throw AgentError.usage("--at must be ISO 8601, like 2026-10-28T08:14:00-07:00") }
                return d
            } ?? model.now()
            let t = model.timing(at: at)
            return ["at": at.iso8601, "summary": TimingText.line(t), "timing": try encoded(t)]
        },
        AgentCommand(name: "entries add", summary: "Add a practice record and show it in the window.",
                     params: [.init(name: "type", required: true, help: types),
                              .init(name: "text", required: true, help: "the body"),
                              .init(name: "title", help: "a title"),
                              .init(name: "tags", help: "comma-separated tags, like entity/ally/crow, place/garden"),
                              .init(name: "volume", help: "volume name or id for the physical page"),
                              .init(name: "page", help: "page in that volume, like 41 or 43–45")],
                     example: "grimoire entries add --type omen --text \"Three crows on the fence\" --tags entity/ally/crow --json") { args, model in
            guard let type = EntryType(rawValue: try args.required("type")), type != .divination else {
                throw AgentError.usage("--type must be one of \(EntryType.creatable.map(\.rawValue).joined(separator: ", ")). Divinations go through `inquiries add`")
            }
            var e = model.newEntry(type, body: try args.required("text"), tags: TagInput.parse(args.string("tags") ?? ""))
            e.title = args.string("title")
            if let v = args.string("volume") {
                let volume = try findVolume(v, in: model)
                e.physicalRef = PhysicalRef(volumeId: volume.id, page: args.string("page") ?? "")
            }
            model.stage(e)
            model.flushEdits()
            return entryJSON(model.entry(e.id) ?? e, model)
        },
        AgentCommand(name: "entries list", summary: "List filed records, newest first.",
                     params: [.init(name: "type", help: types),
                              .init(name: "limit", kind: .integer, help: "at most this many (default 50)"),
                              .init(name: "offset", kind: .integer, help: "skip this many, for the next page")],
                     example: "grimoire entries list --type dream --limit 10 --json", readOnly: true) { args, model in
            var entries = model.timelineEntries
            if let t = args.string("type") {
                guard let type = EntryType(rawValue: t) else { throw AgentError.usage("--type must be one of \(types)") }
                entries = entries.filter { $0.type == type }
            }
            return try paged(entries.map { entryJSON($0, model) }, args, key: "entries")
        },
        AgentCommand(name: "show", summary: "Show one record (entry, inquiry or volume) in full.",
                     params: [.init(name: "id", required: true, positional: true, help: "the record id, or a unique part of it")],
                     example: "grimoire show 01JBX4 --json", readOnly: true) { args, model in
            let id = try find(try args.required("id"), in: model)
            if let e = model.entry(id) { return ["entry": try encoded(e), "backlinks": backlinks(id, model)] }
            if let i = model.inquiry(id) { return inquiryJSON(i, model, full: true) }
            if let v = model.volume(id) { return ["volume": try encoded(v), "records": model.records(in: id).map { ["id": $0.id.string, "page": $0.page, "title": $0.title] }] }
            throw AgentError.notFound("no record \(id.string)")
        },
        AgentCommand(name: "search", summary: "Search text, #tags, card names, or “Volume III pp. 40–50”.",
                     params: [.init(name: "query", required: true, positional: true, help: "what to find"),
                              .init(name: "type", help: types),
                              .init(name: "limit", kind: .integer, help: "at most this many (default 50)"),
                              .init(name: "offset", kind: .integer, help: "skip this many")],
                     example: "grimoire search \"Volume III pp. 40–50\" --json", readOnly: true) { args, model in
            let type = try args.string("type").map { t -> EntryType in
                guard let type = EntryType(rawValue: t) else { throw AgentError.usage("--type must be one of \(types)") }
                return type
            }
            let hits = model.search(try args.required("query"), type: type).map { hit -> JSONObject in
                switch hit {
                case .entry(let id): model.entry(id).map { entryJSON($0, model) } ?? ["id": id.string]
                case .inquiry(let id): model.inquiry(id).map { inquiryJSON($0, model, full: false) } ?? ["id": id.string]
                }
            }
            return try paged(hits, args, key: "results")
        },
        AgentCommand(name: "inquiries list", summary: "List inquiries, newest first.",
                     params: [.init(name: "status", help: "open, resolved or revisited"),
                              .init(name: "limit", kind: .integer, help: "at most this many (default 50)"),
                              .init(name: "offset", kind: .integer, help: "skip this many")],
                     example: "grimoire inquiries list --status open --json", readOnly: true) { args, model in
            var list = model.data.inquiries.sorted { $0.askedAt.instant > $1.askedAt.instant }
            if let s = args.string("status") {
                guard let status = Inquiry.Status(rawValue: s) else { throw AgentError.usage("--status must be open, resolved or revisited") }
                list = list.filter { $0.status == status }
            }
            return try paged(list.map { inquiryJSON($0, model, full: false) }, args, key: "inquiries")
        },
        AgentCommand(name: "inquiries add", summary: "Ask a question, optionally with a quick draw and a Yi Jing cast.",
                     params: [.init(name: "question", required: true, help: "the question"),
                              .init(name: "context", help: "background"),
                              .init(name: "draw", help: "cards typed quickly, like \"3 cups r, tower, page of wands\""),
                              .init(name: "deck", help: "deck id for --draw (default rws-tarot)"),
                              .init(name: "spread", help: "spread id for --draw (default: three-card for 3 cards, else freeform)"),
                              .init(name: "cast", help: "six Yi Jing line values, like 789677"),
                              .init(name: "remind", help: "none, 1w, 1m, 3m, or a number of days")],
                     example: "grimoire inquiries add --question \"Will the move go ahead?\" --draw \"3 cups r, tower, page of wands\" --cast 789677 --remind 1w --json") { args, model in
            var divinations: [Divination] = []
            let at = model.now()
            if let draw = args.string("draw") {
                let deckId = args.string("deck") ?? "rws-tarot"
                guard model.library.deck(deckId) != nil else { throw AgentError.notFound("no deck \(deckId). Run `grimoire validate`") }
                let parser = ReadingParser(library: model.library)
                var spreadId = args.string("spread")
                if spreadId == nil { spreadId = parser.parseQuickDraw(draw, deckId: deckId).draws.count == 3 ? "three-card" : "freeform" }
                let d = parser.parseQuickDraw(draw, deckId: deckId, spreadId: spreadId)
                if let bad = d.draws.first(where: { $0.cardId.value == nil }) {
                    throw AgentError.invalid("could not place the card \"\(bad.cardId.heard ?? "?")\". Check the name with `grimoire parse`")
                }
                divinations.append(Divination(system: .cards, deckId: deckId, spreadId: spreadId, performedAt: at, order: 0,
                                              draws: d.draws.map { Draw(cardId: $0.cardId.value!, positionKey: $0.positionKey, orientation: $0.orientation.value ?? .upright) }))
            }
            if let lines = args.string("cast") {
                let cast = try castOf(lines)
                divinations.append(Divination(system: .yijing, performedAt: at, method: cast.method.rawValue, order: divinations.count, cast: cast))
            }
            let i = model.newInquiry(question: try args.required("question"), context: args.string("context") ?? "",
                                     reminder: try reminder(args.string("remind")), divinations: divinations)
            return inquiryJSON(i, model, full: true)
        },
        AgentCommand(name: "outcomes add", summary: "Add a dated outcome to an inquiry. Outcomes stack.",
                     params: [.init(name: "id", required: true, positional: true, help: "the inquiry id"),
                              .init(name: "text", required: true, help: "what happened"),
                              .init(name: "fulfilled", help: "yes, partly, no or unclear (default unclear)")],
                     example: "grimoire outcomes add 01JBX4 --text \"The offer came through\" --fulfilled yes --json") { args, model in
            let id = try find(try args.required("id"), in: model)
            guard model.inquiry(id) != nil else { throw AgentError.notFound("\(id.string) is not an inquiry. Run `grimoire inquiries list`") }
            guard let f = Outcome.Fulfilled(rawValue: args.string("fulfilled") ?? "unclear") else {
                throw AgentError.usage("--fulfilled must be yes, partly, no or unclear")
            }
            model.addOutcome(to: id, Outcome(recordedAt: model.now(), body: try args.required("text"), fulfilled: f))
            return inquiryJSON(model.inquiry(id)!, model, full: true)
        },
        AgentCommand(name: "needs-outcome", summary: "Reminders that are due: inquiries waiting for an outcome.",
                     example: "grimoire needs-outcome --json", readOnly: true) { _, model in
            ["due": model.repository.needsOutcome(today: model.today).map {
                ["reminder": $0.id.string, "inquiry": $0.targetId.string, "dueOn": DisplayDate.day($0.dueOn), "question": model.title(for: $0.targetId)]
            }]
        },
        AgentCommand(name: "inbox list", summary: "Captures waiting to be checked, with their parsed drafts.",
                     example: "grimoire inbox list --json", readOnly: true) { _, model in
            ["inbox": try model.data.inbox.map { item -> JSONObject in
                var o: JSONObject = ["id": item.id.string, "capture": item.entry.captureId ?? "", "text": item.entry.body,
                                     "occurredAt": item.entry.occurredAt.iso8601, "source": item.source]
                if let d = item.draft { o["draft"] = try encoded(d); o["weakest"] = d.weakest.rawValue }
                return o
            }]
        },
        AgentCommand(name: "inbox confirm", summary: "File an Inbox capture as parsed. Fails while a card or cast is missing; fix those in the window.",
                     params: [.init(name: "id", required: true, positional: true, help: "the Inbox item id"),
                              .init(name: "type", help: "entry type when the capture has no reading (\(types))")],
                     example: "grimoire inbox confirm 01JBX4 --yes --json", destructive: true) { args, model in
            let key = try args.required("id")
            let matches = model.data.inbox.filter { $0.id.string.localizedCaseInsensitiveContains(key) }
            guard let item = matches.first else { throw AgentError.notFound("no Inbox item \(key). Run `grimoire inbox list`") }
            guard matches.count == 1 else { throw AgentError.usage("\(matches.count) Inbox items match \(key). Give more characters") }
            guard args.confirmed else {
                return ["confirmed": false, "wouldFile": item.draft?.question.value ?? item.entry.displayTitle,
                        "hint": "filing takes it out of the Inbox; add --yes, or check it in the window first (grimoire open \(item.id.string))"]
            }
            let type = try args.string("type").map { t -> EntryType in
                guard let type = EntryType(rawValue: t) else { throw AgentError.usage("--type must be one of \(types)") }
                return type
            }
            do {
                let id = try model.confirm(item.id, corrected: item.draft, entryType: type)
                return ["confirmed": true, "filed": id.string]
            } catch let e as ConfirmError {
                throw AgentError.invalid("\(e.description). Fix it in the Inbox: grimoire open \(item.id.string)")
            }
        },
        AgentCommand(name: "ingest", summary: "Check the ingest folders for new phone captures now.",
                     example: "grimoire ingest --json") { _, _ in
            IngestCoordinator.shared.scanAll()
            return ["started": true, "hint": "run `grimoire inbox list` in a few seconds"]
        },
        AgentCommand(name: "volumes list", summary: "List the physical notebooks.",
                     example: "grimoire volumes list --json", readOnly: true) { _, model in
            ["volumes": model.data.volumes.map { ["id": $0.id.string, "name": $0.name, "startedOn": $0.startedOn ?? "", "records": model.records(in: $0.id).count] }]
        },
        AgentCommand(name: "volumes add", summary: "Add a physical notebook.",
                     params: [.init(name: "name", required: true, help: "like Volume III"),
                              .init(name: "started", help: "yyyy-mm-dd")],
                     example: "grimoire volumes add --name \"Volume IV\" --started 2026-11-01 --json") { args, model in
            let v = Volume(name: try args.required("name"), startedOn: args.string("started"))
            model.repository.save(v)
            return ["id": v.id.string, "name": v.name]
        },
        AgentCommand(name: "export", summary: "Export to the Obsidian vault folder set in Settings. Writes only changed files.",
                     params: [.init(name: "to", help: "another folder, instead of the one in Settings")],
                     example: "grimoire export --json") { args, model in
            guard let report = model.exportNow(to: args.string("to").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }, quiet: true) else {
                throw AgentError.invalid("no vault folder. Set one in Settings > Export, or pass --to <folder>")
            }
            return ["written": report.written, "unchanged": report.unchanged]
        },
        AgentCommand(name: "delete", summary: "Delete an entry, inquiry or volume.",
                     params: [.init(name: "id", required: true, positional: true, help: "the record id")],
                     example: "grimoire delete 01JBX4 --yes --json", destructive: true) { args, model in
            let id = try find(try args.required("id"), in: model)
            let title = model.title(for: id)
            guard args.confirmed else { return ["deleted": false, "wouldDelete": ["id": id.string, "title": title], "hint": "add --yes to delete it"] }
            model.delete(id)
            return ["deleted": true, "id": id.string, "title": title]
        },
    ]

    // MARK: Helpers

    /// A record id from a full ULID or any unique part of one.
    static func find(_ key: String, in model: AppModel) throws -> ULID {
        let ids = model.data.entries.map(\.id) + model.data.inquiries.map(\.id) + model.data.volumes.map(\.id)
        let matches = ids.filter { $0.string.localizedCaseInsensitiveContains(key) }
        guard let id = matches.first else { throw AgentError.notFound("no record with id \(key). Run `grimoire search` or `grimoire entries list`") }
        guard matches.count == 1 else { throw AgentError.usage("\(matches.count) records match \(key). Give more characters") }
        return id
    }

    static func findVolume(_ key: String, in model: AppModel) throws -> Volume {
        if let v = model.data.volumes.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame || $0.id.string.localizedCaseInsensitiveContains(key) }) { return v }
        if let q = PageQuery.parse(key), let v = model.data.volumes.first(where: { q.matches(volumeName: $0.name) }) { return v }
        throw AgentError.notFound("no volume \(key). Run `grimoire volumes list`")
    }

    static func castOf(_ lines: String) throws -> YiJingCast {
        do { return try YiJingCast(quick: lines) } catch { throw AgentError.usage("\(error). Give six digits, each 6, 7, 8 or 9") }
    }

    static func reminder(_ raw: String?) throws -> ReminderChoice {
        guard let raw, !raw.isEmpty else { return .preset(model.settings.reminderDefault) }
        if let p = ReminderPreset(rawValue: raw) { return .preset(p) }
        if let n = Int(raw), n > 0 { return .customDays(n) }
        throw AgentError.usage("--remind must be none, 1w, 1m, 3m or a number of days")
    }

    static var model: AppModel { AppModel.shared }

    static func encoded<T: Encodable>(_ value: T) throws -> Any {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return try JSONSerialization.jsonObject(with: enc.encode(value))
    }

    static func paged(_ items: [JSONObject], _ args: Args, key: String) throws -> JSONObject {
        let limit = try args.int("limit", default: 50)
        let offset = try args.int("offset", default: 0)
        let page = Array(items.dropFirst(offset).prefix(limit))
        var result: JSONObject = [key: page, "total": items.count]
        if offset + page.count < items.count { result["nextOffset"] = offset + page.count }
        return result
    }

    static func entryJSON(_ e: Entry, _ model: AppModel) -> JSONObject {
        var o: JSONObject = ["id": e.id.string, "type": e.type.rawValue, "title": e.displayTitle, "occurredAt": e.occurredAt.iso8601,
                             "tags": e.tags.map(\.path), "mode": e.mode.rawValue]
        if let ref = e.physicalRef { o["page"] = "\(model.volume(ref.volumeId)?.name ?? "?") p. \(ref.page)" }
        return o
    }

    static func castJSON(_ cast: YiJingCast, _ model: AppModel) -> JSONObject {
        let yj = model.library.yijing
        let primary = cast.primaryHexagram(in: yj)
        var o: JSONObject = ["lines": cast.lines, "primary": ["number": primary, "name": yj.hexagram(primary)?.name ?? ""],
                             "changing": cast.changingLines]
        if let r = cast.resultingHexagram(in: yj) { o["resulting"] = ["number": r, "name": yj.hexagram(r)?.name ?? ""] }
        return o
    }

    static func inquiryJSON(_ i: Inquiry, _ model: AppModel, full: Bool) -> JSONObject {
        var o: JSONObject = ["id": i.id.string, "question": i.question, "askedAt": i.askedAt.iso8601, "status": i.status.rawValue]
        o["divinations"] = i.divinations.map { d -> JSONObject in
            if let c = d.cast { return ["system": "yijing", "cast": castJSON(c, model)] }
            let deck = d.deckId.flatMap(model.library.deck)
            let spread = d.spreadId.flatMap(model.library.spread) ?? model.library.freeform
            return ["system": d.system.rawValue, "deck": d.deckId ?? "", "spread": spread.id,
                    "draws": d.draws.map { ["card": deck?.card($0.cardId)?.name ?? $0.cardId, "position": spread.label(for: $0.positionKey),
                                            "orientation": $0.orientation.rawValue] }]
        }
        if full {
            o["context"] = i.context
            o["synthesis"] = i.synthesis?.body ?? ""
            o["outcomes"] = i.outcomes.map { ["recordedAt": $0.recordedAt.iso8601, "text": $0.body, "fulfilled": $0.fulfilled.rawValue, "daysAfter": i.daysAfter($0)] }
            o["reminders"] = model.data.reminders.filter { $0.targetId == i.id }.map { ["dueOn": DisplayDate.day($0.dueOn), "status": $0.status.rawValue] }
            o["backlinks"] = backlinks(i.id, model)
        }
        return o
    }

    static func backlinks(_ id: ULID, _ model: AppModel) -> [JSONObject] {
        model.repository.backlinks(to: id).map { ["from": $0.source.string, "kind": $0.kind.rawValue, "title": model.title(for: $0.source)] }
    }
}
