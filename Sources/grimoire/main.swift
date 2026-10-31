import Foundation
import GrimoireCore

// grimoire: the agent CLI (spec §10). Read-heavy; writes only create records or file Inbox items,
// never delete. On Linux it works against a JSON store; the Mac app will point it at its own store.

let usage = """
usage: grimoire <command> [options]

  validate [--definitions DIR]            check deck, spread and Yi Jing files
  parse "<transcript>"                    show the draft a spoken capture would produce
  draw --deck ID [--spread ID] "<cards>"  quick draw, e.g. "3 cups r, tower, page wands"
  cast <lines>                            quick Yi Jing cast, e.g. 789676 (bottom to top)
  timing <iso-date> [--lat N --lon N]     moon phase/sign, sun sign, planetary day/hour
  ingest <GrimoireInbox folder> [--lat N --lon N --tz Zone] [--stable-seconds 3] [--uranika]
                                          ingest phone captures into the Inbox (--uranika adds the chart)
  import <file or folder>... [--tz Zone] [--lat N --lon N] [--dmy] [--tag T]... [--attachments DIR] [--dry-run]
                                          split .docx/.md/.txt records into Inbox items
  inbox                                   list Inbox items waiting for confirm
  confirm <id> [corrections] [--reminder 7-30-90|none|1w|1m|3m]   (default 7-30-90)
        corrections: --deck D=ID --card D.N=CARD --orientation D.N=upright|reversed
                     --lines D=789676 --question "text"   (D, N count from 1)
  add <type> "<body>" [--title T] [--tag T]... [--lat N --lon N]
  session <ritual|meditation|vision> --transcript FILE [--start ISO] [--end ISO] [--tz Zone] [--intention T] [--technique T]
          [--tag T]... [--lat N --lon N]   a recorded session from a timed transcript ("[mm:ss] text" lines) into the Inbox
  observe <entry id> <kind> "<text>" [--at mm:ss] [--tag T]... [--intensity 1-5] [--clarity 1-5]
                                          add an observation to a session (no --at: recalled afterwards)
        kinds: imagery entity place symbol message sound sensation emotion insight omen event action note
  observations [--type T] [--kind K] [--tag T]... [--from yyyy-MM-dd] [--to yyyy-MM-dd] [--json]
                                          every observation in filed sessions, oldest first
  vocab ["<text>"] [--free]               the tag vocabulary, tags suggested for a text, or (--free) free tags in use
  timing-fill [--lat N --lon N] [--overwrite]
                                          fill moon phase and planetary day/hour on records missing it
  search [text] [--tag T]... [--type T] [--volume NAME] [--pages 40-50]
  show <id>
  inquiries [--open]
  needs-outcome [--today yyyy-MM-dd]
  outcome <inquiry id> "<what happened>" --fulfilled yes|partly|no|unclear [--date ISO]
                                          stack an outcome; due check-ins roll on to the next step
  remind <inquiry id> [--preset 7-30-90|1w|1m|3m] [--stop]
  remind-backfill [--today yyyy-MM-dd]    check-ins for open inquiries that have none (old notes)
  export --out DIR [--keep-stale] [--no-coordinates]
                                          Obsidian Markdown, card and hexagram notes, grimoire.jsonl, ML/ files;
                                          removes notes it wrote for records that are gone
  calendar [--from yyyy-MM-dd] [--days 14] [--tz Zone] [--lat N --lon N] [--hours]
                                          moon phases, sign changes, day rulers (and planetary hours) ahead
  calendar-export --out FILE.ics [--from yyyy-MM-dd] [--days 90] [--tz Zone] [--sky phases|all|none]
                  [--hours venus,mars] [--its-day] [--lat N --lon N] [--no-rituals] [--no-checkins]
                                          planned rituals, check-ins, lunations and chosen planetary hours as an
                                          .ics file for Google or Apple Calendar: timing and a grimoire:// link only
  hours <planet> [--after ISO] [--its-day] [--limit 5] [--tz Zone] [--lat N --lon N]
                                          next planetary hours of a planet, e.g. hours mars --its-day
  status [--today yyyy-MM-dd] [--json]    counts for Mission Control: check-ins due, open inquiries, Inbox waiting, last practice
  correspond [text] [--json]              look up planets, signs, elements, trigrams: correspond iron, correspond aries
  meaning <card or hexagram> [--deck ID] [--json]
                                          what it has meant in your readings: meaning "the tower", meaning yijing/29
  patterns [--from yyyy-MM-dd] [--to yyyy-MM-dd] [--top N] [--within DAYS] [--json]
                                          most-drawn cards and hexagrams, recurrences, moon and day, outcomes
  uranika check                           is Uranika open? lists its saved charts and their ids
  uranika chart <iso-date> [--lat N --lon N] [--natal ID]
                                          the chart Grimoire would store for that moment
  uranika fill                            complete "chart pending" entries and Inbox items
  uranika record <id>                     add a filed life event to your chart in Uranika

  Uranika settings: --uranika-settings PATH (default $GRIMOIRE_URANIKA or ./uranika-settings.json),
                    --uranika-url URL, --natal ID override it for one run
  book --out DIR [--design working-journal|book-of-shadows|FOLDER] [--from D] [--to D]
       [--type T]... [--tag T]... [--deck ID]... [--card ID]... [--group month|week|type|tag|deck|card|none]
       [--title T] [--subtitle T] [--transcripts] [--attachments DIR] [--fonts DIR]... [--typst PATH] [--no-pdf]
                                          printable PDF via Typst (writes a Typst project, then book.pdf)

  Global: --store PATH (default $GRIMOIRE_STORE or ./grimoire-store.json)
          home location for --lat/--lon defaults: $GRIMOIRE_HOME="lat,lon"
"""

struct CLIError: Error, CustomStringConvertible { let description: String }

extension Optional {
    func orThrow(_ message: String) throws -> Wrapped {
        guard let v = self else { throw CLIError(description: message) }
        return v
    }
}

enum TagInputFormat {
    static func join(_ tags: [TagPath]) -> String { tags.map(\.path).joined(separator: ", ") }
}

struct Args {
    var positional: [String] = []
    var options: [String: [String]] = [:]

    init(_ argv: [String]) {
        var i = 0
        while i < argv.count {
            let a = argv[i]
            if a.hasPrefix("--") {
                let key = String(a.dropFirst(2))
                if i + 1 < argv.count, !argv[i + 1].hasPrefix("--") {
                    options[key, default: []].append(argv[i + 1]); i += 2
                } else {
                    options[key, default: []].append(""); i += 1
                }
            } else { positional.append(a); i += 1 }
        }
    }
    func one(_ k: String) -> String? { options[k]?.last }
    func all(_ k: String) -> [String] { options[k] ?? [] }
    func has(_ k: String) -> Bool { options[k] != nil }
}

func printJSON<T: Encodable>(_ v: T) throws {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    enc.dateEncodingStrategy = .iso8601
    print(String(decoding: try enc.encode(v), as: UTF8.self))
}

func loadLibrary(_ args: Args) throws -> DefinitionLibrary {
    if let dir = args.one("definitions") { return try DefinitionLibrary.load(from: URL(fileURLWithPath: dir)) }
    return try DefinitionLibrary.bundled()
}

func openStore(_ args: Args) throws -> JSONFileRepository {
    let path = args.one("store") ?? ProcessInfo.processInfo.environment["GRIMOIRE_STORE"] ?? "grimoire-store.json"
    return try JSONFileRepository(url: URL(fileURLWithPath: path))
}

/// --lat/--lon, else $GRIMOIRE_HOME ("lat,lon").
func location(_ args: Args) -> GeoLocation? {
    if let la = args.one("lat").flatMap(Double.init), let lo = args.one("lon").flatMap(Double.init) { return GeoLocation(latitude: la, longitude: lo) }
    let home = (ProcessInfo.processInfo.environment["GRIMOIRE_HOME"] ?? "").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    return home.count == 2 ? GeoLocation(latitude: home[0], longitude: home[1]) : nil
}

func uranikaSettings(_ args: Args) throws -> UranikaSettings {
    let path = args.one("uranika-settings") ?? ProcessInfo.processInfo.environment["GRIMOIRE_URANIKA"] ?? "uranika-settings.json"
    var s = FileManager.default.fileExists(atPath: path) ? try UranikaSettings.load(from: URL(fileURLWithPath: path)) : UranikaSettings()
    if let u = args.one("uranika-url") { s.baseURL = u }
    if let n = args.one("natal").flatMap(Int.init) { s.natalChartId = n }
    return s
}

func today(_ tz: TimeZone = .current) -> String { GrimoireDateFormat.day(Date(), in: tz) }

func describe(_ d: DraftReading, library: DefinitionLibrary) -> String {
    var s = ""
    if let q = d.question.value { s += "Question: \(q)\n" }
    for (n, div) in d.divinations.enumerated() {
        if div.system == .yijing {
            let lines = div.cast?.lines.value ?? []
            s += "\(n + 1). Yi Jing (\(div.cast?.method.rawValue ?? "?")): \(lines.map(String.init).joined()) [\(div.cast?.lines.confidence.rawValue ?? "missing")]\n"
            if let c = try? YiJingCast(lines: lines) {
                let p = c.primaryHexagram(in: library.yijing)
                s += "   primary \(p) \(library.yijing.hexagram(p)!.name)"
                if let r = c.resultingHexagram(in: library.yijing) { s += " → \(r) \(library.yijing.hexagram(r)!.name), changing \(c.changingLines)" }
                s += "\n"
            }
        } else {
            let deck = div.deckId.value.flatMap(library.deck)
            s += "\(n + 1). \(deck?.name ?? div.deckId.value ?? "(no deck)") [\(div.deckId.confidence.rawValue)] · \(div.spreadId.value ?? "?") [\(div.spreadId.confidence.rawValue)]\n"
            for (k, w) in div.draws.enumerated() {
                let name = w.cardId.value.flatMap { deck?.card($0)?.name } ?? w.cardId.value ?? "?"
                s += "   \(k + 1). \(w.positionKey): \(name), \(w.orientation.value?.rawValue ?? "?") [\(w.cardId.confidence.rawValue)] heard \"\(w.cardId.heard ?? "")\"\n"
            }
        }
    }
    if !d.unparsed.isEmpty { s += "Unplaced words: \(d.unparsed.joined(separator: " "))\n" }
    for w in d.warnings { s += "! \(w)\n" }
    return s
}

func parseIndex(_ s: String) throws -> (Int, Int?, String) {
    // "D.N=value" or "D=value"
    let kv = s.split(separator: "=", maxSplits: 1).map(String.init)
    guard kv.count == 2 else { throw CLIError(description: "expected X=value, got \(s)") }
    let parts = kv[0].split(separator: ".").compactMap { Int($0) }
    guard let d = parts.first, d >= 1 else { throw CLIError(description: "bad index in \(s)") }
    return (d - 1, parts.count > 1 ? parts[1] - 1 : nil, kv[1])
}

func run() async throws {
    var argv = Array(CommandLine.arguments.dropFirst())
    guard !argv.isEmpty, argv[0] != "help", argv[0] != "--help" else { print(usage); return }
    let command = argv.removeFirst()
    let args = Args(argv)

    switch command {
    case "validate":
        let lib = try loadLibrary(args)
        let r = lib.validate()
        print("decks: \(lib.decks.map { "\($0.id) (\($0.cards.count) cards, \($0.status.rawValue))" }.joined(separator: ", "))")
        print("spreads: \(lib.spreads.map(\.id).joined(separator: ", "))")
        print("yijing: \(lib.yijing.hexagrams.count) hexagrams, \(lib.yijing.trigrams.count) trigrams")
        for w in r.warnings { print("warning: \(w)") }
        for e in r.errors { print("error: \(e)") }
        if !r.isValid { exit(1) }
        print("ok")

    case "parse":
        let lib = try loadLibrary(args)
        guard let text = args.positional.first else { throw CLIError(description: "parse needs a transcript") }
        let draft = ReadingParser(library: lib).parse(text)
        if args.has("json") { try printJSON(draft) } else { print(describe(draft, library: lib), terminator: "") }

    case "draw":
        let lib = try loadLibrary(args)
        guard let deck = args.one("deck"), let text = args.positional.first else { throw CLIError(description: "draw needs --deck and card text") }
        let div = ReadingParser(library: lib).parseQuickDraw(text, deckId: deck, spreadId: args.one("spread"))
        print(describe(DraftReading(divinations: [div]), library: lib), terminator: "")

    case "cast":
        let lib = try loadLibrary(args)
        guard let lines = args.positional.first else { throw CLIError(description: "cast needs six line values") }
        let c = try YiJingCast(quick: lines)
        let p = c.primaryHexagram(in: lib.yijing)
        let ph = lib.yijing.hexagram(p)!
        print("primary: \(p). \(ph.name) (\(ph.pinyin))")
        print("changing lines: \(c.changingLines.isEmpty ? "none" : c.changingLines.map(String.init).joined(separator: ", "))")
        if let r = c.resultingHexagram(in: lib.yijing), let rh = lib.yijing.hexagram(r) { print("resulting: \(r). \(rh.name) (\(rh.pinyin))") }

    case "timing":
        guard let s = args.positional.first, let z = ZonedDate.parse(s, timeZone: args.one("tz")) else { throw CLIError(description: "timing needs an ISO 8601 date with offset") }
        try printJSON(TimingContext.compute(at: z, location: location(args)))

    case "ingest":
        let lib = try loadLibrary(args)
        guard let folder = args.positional.first else { throw CLIError(description: "ingest needs the GrimoireInbox folder") }
        let store = try openStore(args)
        let ingestor = InboxIngestor(root: URL(fileURLWithPath: folder), transcriber: SidecarTextTranscriber(), parser: ReadingParser(library: lib))
        if let s = args.one("stable-seconds").flatMap(Double.init) { ingestor.stableSeconds = s }
        if let tz = args.one("tz") { ingestor.defaultTimeZone = tz }
        ingestor.location = location(args)
        if args.has("uranika") { ingestor.astrologer = UranikaAstrologer(settings: try uranikaSettings(args)) }
        ingestor.tagVocabulary = Array(store.tagTree.all)
        let outcomes = await ingestor.scan(isKnown: store.knowsCapture, deliver: store.addToInbox)
        try store.flush()
        for o in outcomes { print(o) }

    case "import":
        let lib = try loadLibrary(args)
        guard !args.positional.isEmpty else { throw CLIError(description: "import needs files or folders (.docx, .md, .txt)") }
        let store = try openStore(args)
        var importer = DocumentImporter(parser: ReadingParser(library: lib))
        if let tz = args.one("tz") { importer.timeZone = tz }
        importer.location = location(args)
        if args.has("dmy") { importer.slashOrder = .dayFirst }
        importer.tags = args.all("tag").map { TagPath($0) }
        let dryRun = args.has("dry-run")
        let run = ImportRun(importer: importer, attachmentsFolder: dryRun ? nil : args.one("attachments").map { URL(fileURLWithPath: $0) })
        var preview: [InboxItem] = []
        let outcomes = run.run(args.positional.map { URL(fileURLWithPath: $0) },
                               isKnown: { cid in store.knowsCapture(cid) || preview.contains { $0.entry.captureId == cid } },
                               deliver: { dryRun ? preview.append($0) : store.addToInbox($0) })
        if !dryRun { try store.flush() }
        for o in outcomes {
            switch o {
            case .imported(let file, let id, _):
                let item = preview.first { $0.id == id } ?? store.data.inbox.first { $0.id == id }!
                let e = item.entry
                print("\(dryRun ? "would import" : "imported")  \(id)  \(e.occurredAt.day)  \(e.type.rawValue)  \(e.displayTitle)  [\(file)]")
                if dryRun, let d = item.draft { print(describe(d, library: lib).split(separator: "\n").map { "    " + $0 }.joined(separator: "\n")) }
                for n in item.notes ?? [] { print("    ! \(n)") }
            case .duplicate(let file, let cid): print("duplicate  \(cid)  [\(file)]")
            case .failed(let file, let reason): print("failed  \(file): \(reason)")
            }
        }

    case "inbox":
        let lib = try loadLibrary(args)
        let store = try openStore(args)
        if store.data.inbox.isEmpty { print("Inbox is empty") }
        for item in store.data.inbox.sorted(by: { $0.id < $1.id }) {
            print("\(item.id)  \(item.entry.occurredAt.iso8601)  \(item.entry.type.rawValue)  \(item.source)  [\(item.draft?.weakest.rawValue ?? "no draws")]")
            if let d = item.draft { print(describe(d, library: lib).split(separator: "\n").map { "    " + $0 }.joined(separator: "\n")) }
            else { print("    " + item.entry.displayTitle) }
            for n in item.notes ?? [] { print("    ! \(n)") }
        }

    case "confirm":
        let lib = try loadLibrary(args)
        let store = try openStore(args)
        guard let raw = args.positional.first, let id = ULID(raw), let item = store.data.inbox.first(where: { $0.id == id }) else {
            throw CLIError(description: "confirm needs an Inbox item id (see `grimoire inbox`)")
        }
        var draft = item.draft
        for s in args.all("deck") { let (d, _, v) = try parseIndex(s); draft?.divinations[d].deckId = Parsed(v, confidence: .high) }
        for s in args.all("card") {
            let (d, n, v) = try parseIndex(s)
            guard var dr = draft, let n else { throw CLIError(description: "--card needs D.N=card") }
            let spread = dr.divinations[d].spreadId.value.flatMap(lib.spread) ?? lib.freeform
            while dr.divinations[d].draws.count <= n {
                dr.divinations[d].draws.append(DraftDraw(cardId: .missing, orientation: Parsed(.upright, confidence: .high), positionKey: spread.positionKey(at: dr.divinations[d].draws.count)))
            }
            dr.divinations[d].draws[n].cardId = Parsed(v, confidence: .high)
            draft = dr
        }
        for s in args.all("orientation") {
            let (d, n, v) = try parseIndex(s)
            guard let n, let o = Orientation(rawValue: v) else { throw CLIError(description: "--orientation needs D.N=upright|reversed") }
            draft?.divinations[d].draws[n].orientation = Parsed(o, confidence: .high)
        }
        for s in args.all("lines") {
            let (d, _, v) = try parseIndex(s)
            draft?.divinations[d].cast?.lines = Parsed(v.compactMap(\.wholeNumberValue), confidence: .high)
        }
        if let q = args.one("question") { draft?.question = Parsed(q, confidence: .high) }
        guard let preset = ReminderPreset(rawValue: args.one("reminder") ?? "7-30-90") else { throw CLIError(description: "--reminder must be 7-30-90, none, 1w, 1m or 3m") }
        let result = try store.confirm(id, corrected: draft, library: lib, reminder: preset)
        try store.flush()
        print("filed entry \(result.entry.id)" + (result.inquiry.map { " and inquiry \($0.id): \($0.question)" } ?? ""))
        if !result.corrections.isEmpty { print("logged \(result.corrections.count) correction(s)") }

    case "add":
        let store = try openStore(args)
        guard args.positional.count >= 2, let type = EntryType(rawValue: args.positional[0]), type != .divination else {
            throw CLIError(description: "add needs a type (journal, ritual, meditation, vision, contact, omen, insight, dream, event) and a body")
        }
        let now = ZonedDate(Date())
        let e = Entry(type: type, title: args.one("title"), occurredAt: now, body: args.positional[1],
                      tags: args.all("tag").map { TagPath($0) }, timing: TimingContext.compute(at: now, location: location(args)), mode: .quick)
        store.save(e)
        try store.flush()
        print(e.id)

    case "session":
        let store = try openStore(args)
        guard let type = args.positional.first.flatMap(EntryType.init), EntryType.sessionTypes.contains(type) else {
            throw CLIError(description: "session needs a type: ritual, meditation or vision")
        }
        guard let file = args.one("transcript") else { throw CLIError(description: "session needs --transcript FILE") }
        let segments = TimedTranscript.parse(try String(contentsOfFile: file, encoding: .utf8))
        let start = try args.one("start").map { s in try ZonedDate.parse(s, timeZone: args.one("tz")).orThrow("--start must be ISO 8601 with offset") } ?? ZonedDate(Date())
        var rec = SessionRecorder(type: type, startedAt: start, intention: args.one("intention"), technique: args.one("technique"),
                                  tags: args.all("tag").map { TagPath($0) })
        let end = try args.one("end").map { s in try ZonedDate.parse(s).orThrow("--end must be ISO 8601 with offset").instant }
        rec.finish(at: end ?? start.instant.addingTimeInterval(segments.map(\.offset).max() ?? 0))
        let item = SessionAssembler.retranscribed(
            rec.inboxItem(recording: nil, extractor: ObservationExtractor(), timing: TimingContext.compute(at: start, location: location(args)), source: "cli:\(file)"),
            segments: segments, extractor: ObservationExtractor())
        store.addToInbox(item)
        try store.flush()
        print("\(item.id)  \(type.rawValue) in the Inbox with \(item.entry.session?.observations.count ?? 0) observation(s); check them, then: grimoire confirm \(item.id)")

    case "observe":
        let store = try openStore(args)
        guard args.positional.count >= 3, let id = ULID(args.positional[0]) else { throw CLIError(description: "observe needs an entry id, a kind and text") }
        guard let kind = ObservationKind(rawValue: args.positional[1]) else {
            throw CLIError(description: "kind must be one of \(ObservationKind.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        let inInbox = store.data.inbox.first { $0.id == id }
        guard var entry = store.entry(id) ?? inInbox?.entry, var session = entry.session else { throw CLIError(description: "\(args.positional[0]) is not a recorded session") }
        let vocab = TagVocabulary.standard
        var tags = args.all("tag").map { vocab.canonical(TagPath($0)) }.filter { !$0.isEmpty }
        if tags.isEmpty { tags = vocab.suggest(in: args.positional[2]) }
        func scale(_ k: String) throws -> Int? {
            guard let v = args.one(k) else { return nil }
            guard let n = Int(v), (1...5).contains(n) else { throw CLIError(description: "--\(k) must be 1–5") }
            return n
        }
        let at = try args.one("at").map { a -> Double in
            guard let (t, _) = TimedTranscript.stamp("[\(a)]") else { throw CLIError(description: "--at must be mm:ss or h:mm:ss") }
            return t
        }
        let o = Observation(offset: at ?? session.duration ?? 0, phase: at == nil ? .aftermath : nil, kind: kind, text: args.positional[2], tags: tags,
                            intensity: try scale("intensity"), clarity: try scale("clarity"), capture: at == nil ? .recalled : .live)
        session.add(o)
        entry.session = session
        entry.updatedAt = Date()
        if var item = inInbox { item.entry = entry; store.addToInbox(item) } else { store.save(entry) }
        try store.flush()
        print("\(o.id)  \(TimedTranscript.clock(o.offset))  \(kind.rawValue)  \(TagInputFormat.join(tags))")

    case "observations":
        let store = try openStore(args)
        var data = store.data
        data.entries = data.entries.filter { e in
            (args.one("type").map { e.type.rawValue == $0 } ?? true)
                && (args.one("from").map { e.occurredAt.day >= $0 } ?? true) && (args.one("to").map { e.occurredAt.day <= $0 } ?? true)
        }
        let want = args.all("tag").map { TagPath($0) }
        let rows = SessionExporter().observationRows(data).filter { r in
            if let k = args.one("kind"), r["kind"] != .string(k) { return false }
            guard case .list(let tags) = r["tags"] ?? .null else { return want.isEmpty }
            return want.allSatisfy { w in tags.contains { TagPath($0).isUnder(w) } }
        }
        if args.has("json") { try printJSON(rows) }
        else {
            for r in rows {
                func v(_ k: String) -> String { if case .string(let s) = r[k] ?? .null { return s }; if case .double(let d) = r[k] ?? .null { return TimedTranscript.clock(d) }; return "" }
                var tags = ""
                if case .list(let l) = r["tags"] ?? .null { tags = l.joined(separator: ", ") }
                print("\(v("session_day"))  \(v("session_type"))  \(v("offset_s"))  \(v("kind"))  \(v("text"))" + (tags.isEmpty ? "" : "  [\(tags)]"))
            }
        }

    case "vocab":
        let vocab = TagVocabulary.standard
        if args.has("free") {
            let store = try openStore(args)
            let all = store.data.entries.flatMap { $0.tags + ($0.session?.observations.flatMap(\.tags) ?? []) }
            let free = Dictionary(grouping: all.map(vocab.canonical).filter { !vocab.isControlled($0) }, by: \.path).mapValues(\.count)
            for (tag, n) in free.sorted(by: { ($1.value, $0.key) < ($0.value, $1.key) }) { print("\(n)  \(tag)") }
        } else if let text = args.positional.first {
            for t in vocab.suggest(in: text) { print(t) }
        } else {
            for t in vocab.terms { print(t.path.path + (t.aliases.isEmpty ? "" : "  (\(t.aliases.joined(separator: ", ")))")) }
        }

    case "search":
        let lib = try loadLibrary(args)
        let store = try openStore(args)
        var q = SearchQuery(text: args.positional.first, tags: args.all("tag").map { TagPath($0) })
        if let t = args.one("type").flatMap(EntryType.init) { q.types = [t] }
        if let v = args.one("volume") {
            guard let vol = store.data.volumes.first(where: { $0.name.lowercased() == v.lowercased() || $0.id.string == v }) else { throw CLIError(description: "no volume \(v)") }
            q.volumeId = vol.id
        }
        if let p = args.one("pages") { q.pages = PhysicalRef(volumeId: ULID(), page: p).pageRange }
        for hit in store.search(q, library: lib) {
            switch hit {
            case .entry(let id): let e = store.entry(id)!; print("\(id)  entry    \(e.occurredAt.day)  \(e.type.rawValue)  \(e.displayTitle)" + (e.physicalRef.map { "  [p. \($0.page)]" } ?? ""))
            case .inquiry(let id): let i = store.inquiry(id)!; print("\(id)  inquiry  \(i.askedAt.day)  \(i.question)")
            }
        }

    case "show":
        let store = try openStore(args)
        guard let raw = args.positional.first, let id = ULID(raw) else { throw CLIError(description: "show needs an id") }
        if let e = store.entry(id) { try printJSON(e) }
        else if let i = store.inquiry(id) { try printJSON(i) }
        else if let item = store.data.inbox.first(where: { $0.id == id }) { try printJSON(item) }
        else { throw CLIError(description: "nothing with id \(raw)") }

    case "inquiries":
        let store = try openStore(args)
        for i in store.data.inquiries.sorted(by: { $0.id > $1.id }) where !args.has("open") || i.status == .open {
            print("\(i.id)  \(i.askedAt.day)  \(i.status.rawValue)  \(i.question)  (\(i.divinations.count) divination(s), \(i.outcomes.count) outcome(s))")
        }

    case "needs-outcome":
        let store = try openStore(args)
        for r in store.needsOutcome(today: args.one("today") ?? today()) {
            let q = store.inquiry(r.targetId)?.question ?? store.entry(r.targetId)?.displayTitle ?? r.targetId.string
            print("\(r.dueOn)  \(q)" + (r.prompt.map { "  — \($0)" } ?? ""))
        }

    case "status":
        let store = try openStore(args)
        let summary = StatusSummary(data: store.data, today: args.one("today") ?? today())
        if args.has("json") { print(String(decoding: try summary.json(), as: UTF8.self)) } else {
            print("Today \(summary.today): \(summary.checkInsDue) check-in(s) due, \(summary.openInquiries) open inquiry(ies), \(summary.inboxWaiting) waiting in Inbox.")
            print("Last practice: \(summary.lastPractice ?? "none")\(summary.practicedToday ? " (today)" : "")")
        }

    case "outcome":
        let store = try openStore(args)
        guard args.positional.count >= 2, let id = ULID(args.positional[0]) else { throw CLIError(description: "outcome needs an inquiry id and what happened") }
        guard let f = Outcome.Fulfilled(rawValue: args.one("fulfilled") ?? "") else { throw CLIError(description: "--fulfilled must be yes, partly, no or unclear") }
        var when = ZonedDate(Date())
        if let d = args.one("date") { guard let z = ZonedDate.parse(d) else { throw CLIError(description: "--date needs ISO 8601 with offset") }; when = z }
        let inq = try store.addOutcome(Outcome(recordedAt: when, body: args.positional[1], fulfilled: f), to: id)
        try store.flush()
        let next = store.data.reminders.first { $0.targetId == id && $0.status != .done }
        print("\(inq.status.rawValue), \(inq.outcomes.count) outcome(s)" + (next.map { "; next check-in \($0.dueOn)" } ?? "; no more check-ins"))

    case "remind":
        let store = try openStore(args)
        guard let raw = args.positional.first, let id = ULID(raw), let inq = store.inquiry(id) else { throw CLIError(description: "remind needs an inquiry id") }
        if args.has("stop") { store.stopReminders(for: id); try store.flush(); print("stopped"); break }
        guard let preset = ReminderPreset(rawValue: args.one("preset") ?? "7-30-90") else { throw CLIError(description: "--preset must be 7-30-90, 1w, 1m or 3m") }
        if let r = store.scheduleOutcomeCheckIn(for: inq, preset: preset, today: today(inq.askedAt.zone)) { try store.flush(); print("\(r.dueOn)  \(r.prompt ?? "")") }
        else { print("already has an open reminder") }

    case "remind-backfill":
        let store = try openStore(args)
        let made = store.backfillOutcomeCheckIns(today: args.one("today") ?? today())
        try store.flush()
        for r in made { print("\(r.dueOn)  day \(r.step ?? 0)  \(store.inquiry(r.targetId)?.question ?? r.targetId.string)") }
        print("\(made.count) check-in(s) scheduled")

    case "timing-fill":
        let store = try openStore(args)
        let n = store.fillTiming(location: location(args), overwrite: args.has("overwrite"))
        try store.flush()
        print("updated \(n) record(s)")

    case "calendar":
        let tz = args.one("tz").flatMap(TimeZone.init(identifier:)) ?? .current
        let days = RitualCalendar.days(from: args.one("from") ?? today(tz), count: args.one("days").flatMap(Int.init) ?? 14,
                                       zone: tz, location: location(args))
        func time(_ d: Date) -> String { String(GrimoireDateFormat.iso(d, in: tz).dropFirst(11).prefix(5)) }
        for d in days {
            print("\(d.day)  day of \(d.ruler.rawValue.capitalized)  \(d.moonPhase.rawValue) moon \(d.moonIllumination)% in \(d.moonSign.rawValue)")
            if let r = d.sunrise, let s = d.sunset { print("    sunrise \(time(r))  sunset \(time(s))") }
            for e in d.events { print("    \(time(e.at))  \(e.title)") }
            if args.has("hours") {
                for h in d.hours { print("      \(h.number < 10 ? " " : "")\(h.number)  \(time(h.start))–\(time(h.end))  \(h.planet.rawValue)") }
            }
        }

    case "calendar-export":
        let store = try openStore(args)
        guard let out = args.one("out"), !out.isEmpty else { throw CLIError(description: "calendar-export needs --out FILE.ics") }
        let tz = args.one("tz").flatMap(TimeZone.init(identifier:)) ?? .current
        guard var exporter = CalendarExporter(first: args.one("from") ?? today(tz), days: args.one("days").flatMap(Int.init) ?? 90, zone: tz) else {
            throw CLIError(description: "--from must be yyyy-MM-dd")
        }
        exporter.rituals = !args.has("no-rituals")
        exporter.checkIns = !args.has("no-checkins")
        switch args.one("sky") ?? "phases" {
        case "phases": break
        case "all": exporter.sky = Set(SkyEvent.Kind.allCases)
        case "none": exporter.sky = []
        case let other: throw CLIError(description: "--sky is phases, all or none, not \(other)")
        }
        exporter.hoursOf = try (args.one("hours") ?? "").split(separator: ",").map { name in
            guard let p = Planet(rawValue: name.trimmingCharacters(in: .whitespaces).lowercased()) else {
                throw CLIError(description: "unknown planet \(name): \(Planet.chaldean.map(\.rawValue).joined(separator: ", "))")
            }
            return p
        }
        exporter.hoursOnTheirDay = args.has("its-day")
        exporter.location = location(args)
        if !exporter.hoursOf.isEmpty && exporter.location == nil {
            throw CLIError(description: "--hours needs a location: --lat N --lon N or $GRIMOIRE_HOME")
        }
        let events = exporter.events(for: store.data)
        try Data(CalendarExporter.ics(events).utf8).write(to: URL(fileURLWithPath: out), options: .atomic)
        print("\(events.count) event(s) written to \(out)")

    case "hours":
        guard let name = args.positional.first, let planet = Planet(rawValue: name.lowercased()) else {
            throw CLIError(description: "hours needs a planet: \(Planet.chaldean.map(\.rawValue).joined(separator: ", "))")
        }
        guard let loc = location(args) else { throw CLIError(description: "hours needs a location: --lat N --lon N or $GRIMOIRE_HOME") }
        let tz = args.one("tz").flatMap(TimeZone.init(identifier:)) ?? .current
        let after = try args.one("after").map { s -> Date in
            guard let d = GrimoireDateFormat.parseISO(s) else { throw CLIError(description: "--after must be ISO 8601") }
            return d
        } ?? Date()
        for h in RitualCalendar.nextHours(of: planet, after: after, location: loc, zone: tz, onItsDay: args.has("its-day"),
                                          limit: args.one("limit").flatMap(Int.init) ?? 5) {
            print("\(GrimoireDateFormat.iso(h.start, in: tz))  to \(String(GrimoireDateFormat.iso(h.end, in: tz).dropFirst(11).prefix(5)))  hour \(h.number) of \(planet.rawValue)")
        }

    case "correspond":
        let lib = try loadLibrary(args)
        guard let table = lib.correspondences else { throw CLIError(description: "no correspondences.json in the definitions folder") }
        let hits = table.search(args.positional.joined(separator: " "))
        if args.has("json") { try printJSON(hits); break }
        if hits.isEmpty { print("nothing matches") }
        for e in hits {
            print("\(e.glyph.map { "\($0) " } ?? "")\(e.name)  (\(e.kind))")
            for f in e.fields { print("    \(f.label): \(f.values.joined(separator: ", "))") }
            let cards = lib.cards(for: e)
            if !cards.isEmpty { print("    Cards: " + cards.map { "\($0.card.name) (\($0.deck.name))" }.joined(separator: ", ")) }
            if e.kind == "trigram" { print("    Hexagrams: " + lib.hexagrams(withTrigram: e.key).map { "\($0.number)" }.joined(separator: " ")) }
        }

    case "patterns":
        let lib = try loadLibrary(args)
        let store = try openStore(args)
        func day(_ k: String, end: Bool) throws -> Date? {
            guard let s = args.one(k) else { return nil }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            guard let d = f.date(from: s) else { throw CLIError(description: "--\(k) must be yyyy-MM-dd") }
            return end ? d.addingTimeInterval(86_399) : d
        }
        let p = Patterns(data: store.data, library: lib, from: try day("from", end: false), to: try day("to", end: true))
        let report = p.report(top: args.one("top").flatMap(Int.init) ?? 10, recurrenceDays: args.one("within").flatMap(Int.init) ?? 30)
        if args.has("json") { try printJSON(report) } else { print(report.text) }

    case "meaning":
        let lib = try loadLibrary(args)
        let store = try openStore(args)
        let text = args.positional.joined(separator: " ")
        guard !text.isEmpty else { throw CLIError(description: "meaning needs a card or hexagram, e.g. meaning \"the tower\"") }
        guard let symbol = lib.symbol(named: text, deckId: args.one("deck")) else { throw CLIError(description: "no card or hexagram called \(text)") }
        let p = Patterns(data: store.data, library: lib)
        let meaning: PersonalMeaning?
        switch symbol {
        case let .card(deckId, cardId): meaning = p.meaning(card: cardId, deckId: deckId)
        case let .hexagram(n): meaning = p.meaning(hexagram: n)
        }
        guard let meaning else { print("\(text): not in any reading yet."); break }
        if args.has("json") { try printJSON(meaning.report) } else { print(meaning.text, terminator: "") }

    case "export":
        let lib = try loadLibrary(args)
        let store = try openStore(args)
        guard let out = args.one("out") else { throw CLIError(description: "export needs --out DIR") }
        let root = URL(fileURLWithPath: out)
        var exporter = ObsidianExporter(library: lib)
        exporter.includeCoordinates = !args.has("no-coordinates")
        var files = exporter.files(for: store.data)
        files["grimoire.jsonl"] = try JSONLExporter(library: lib).export(store.data)
        files.merge(try MLExporter(library: lib).files(for: store.data)) { a, _ in a }
        let report = try ExportWriter.write(files, to: root, prune: !args.has("keep-stale"))
        print("\(report.written.count) written, \(report.unchanged) unchanged, \(report.removed.count) removed")

    case "uranika":
        let settings = try uranikaSettings(args)
        let astro = UranikaAstrologer(settings: settings)
        switch args.positional.first {
        case "check":
            let version = try await astro.service.health()
            print("Uranika is open (Swiss Ephemeris \(version)) at \(settings.baseURL)")
            for c in try await astro.service.charts() {
                print("\(c.id)\t\(c.name)\t\(c.date) \(c.time) \(c.tz)" + (c.id == settings.natalChartId ? "\t← your chart" : ""))
            }
        case "chart":
            guard args.positional.count >= 2, let z = ZonedDate.parse(args.positional[1], timeZone: args.one("tz")) else {
                throw CLIError(description: "uranika chart needs an ISO 8601 date with offset")
            }
            var loc: GeoLocation?
            if let la = args.one("lat").flatMap(Double.init), let lo = args.one("lon").flatMap(Double.init) { loc = GeoLocation(latitude: la, longitude: lo) }
            let snap = await astro.snapshot(at: z, place: astro.place(captured: loc, fallback: nil))
            try printJSON(snap)
            for h in snap.hits { print(h.label) }
        case "fill":
            let store = try openStore(args)
            let filled = await astro.fillPending(store.data.entries)
            for e in filled { store.save(e) }
            var items = 0
            for item in store.data.inbox where item.entry.astro?.status == .pending {
                guard let e = await astro.fillPending([item.entry]).first else { continue }
                var updated = item
                updated.entry = e
                updated.notes = updated.notes?.filter { !$0.hasPrefix("Chart pending") }
                if updated.notes?.isEmpty == true { updated.notes = nil }
                store.addToInbox(updated)
                items += 1
            }
            try store.flush()
            let left = store.data.entries.filter { $0.astro?.status == .pending }.count + store.data.inbox.filter { $0.entry.astro?.status == .pending }.count
            print("\(filled.count) entries and \(items) Inbox items filled, \(left) still pending")
        case "record":
            let store = try openStore(args)
            guard args.positional.count >= 2, let id = ULID(args.positional[1]), let e = store.entry(id) else { throw CLIError(description: "uranika record needs a filed entry id") }
            var s = settings
            s.recordEventsInUranika = true
            guard let updated = try await UranikaAstrologer(service: astro.service, settings: s).recordEvent(e) else {
                throw CLIError(description: "nothing sent: the entry must be a life event, not sent before, and a natal chart must be set (--natal ID)")
            }
            store.save(updated)
            try store.flush()
            print("added to Uranika as event \(updated.astro?.uranikaEvent ?? 0)")
        default:
            throw CLIError(description: "uranika needs check, chart, fill or record")
        }

    case "book":
        let lib = try loadLibrary(args)
        let store = try openStore(args)
        guard let out = args.one("out") else { throw CLIError(description: "book needs --out DIR") }
        var spec = BookSpec(title: args.one("title") ?? "Grimoire", subtitle: args.one("subtitle"), from: args.one("from"), to: args.one("to"),
                            tags: args.all("tag").map { TagPath($0) }, decks: args.all("deck"), cards: args.all("card"),
                            includeTranscripts: args.has("transcripts"))
        spec.types = try args.all("type").map { t in
            guard let type = EntryType(rawValue: t == "reading" ? "divination" : t) else { throw CLIError(description: "unknown type \(t)") }
            return type
        }
        if let g = args.one("group") {
            guard let grouping = BookSpec.Grouping(rawValue: g) else { throw CLIError(description: "--group is one of \(BookSpec.Grouping.allCases.map(\.rawValue).joined(separator: ", "))") }
            spec.grouping = grouping
        }
        let design = try BookDesign.named(args.one("design") ?? "working-journal")
        let attachments = args.one("attachments").map { URL(fileURLWithPath: $0) }
        let book = BookExporter(library: lib).book(store.data, spec: spec, generatedOn: today(), attachmentExists: { path in
            attachments.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent(path).path) } ?? false
        })
        let root = URL(fileURLWithPath: out)
        try BookWriter.write(book, design: design, to: root, attachmentsRoot: attachments)
        print("\(design.name): \(book.chapters.count) chapter(s), \(book.counts.entries) entries, \(book.counts.readings) readings → \(root.path)")
        if args.has("no-pdf") { break }
        guard let typst = args.one("typst").map({ URL(fileURLWithPath: $0) }) ?? TypstRenderer.locate() else { throw BookError.typstNotFound }
        let pdf = try TypstRenderer(executable: typst, fontPaths: args.all("fonts").map { URL(fileURLWithPath: $0) }).render(folder: root)
        print(pdf.path)

    default:
        print(usage)
        throw CLIError(description: "unknown command \(command)")
    }
}

do { try await run() } catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
