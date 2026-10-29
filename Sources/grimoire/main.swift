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
  ingest <GrimoireInbox folder> [--lat N --lon N --tz Zone] [--stable-seconds 3]
                                          ingest phone captures into the Inbox
  import <file or folder>... [--tz Zone] [--lat N --lon N] [--dmy] [--tag T]... [--attachments DIR] [--dry-run]
                                          split .docx/.md/.txt records into Inbox items
  inbox                                   list Inbox items waiting for confirm
  confirm <id> [corrections] [--reminder none|1w|1m|3m]
        corrections: --deck D=ID --card D.N=CARD --orientation D.N=upright|reversed
                     --lines D=789676 --question "text"   (D, N count from 1)
  add <type> "<body>" [--title T] [--tag T]...
  search [text] [--tag T]... [--type T] [--volume NAME] [--pages 40-50]
  show <id>
  inquiries [--open]
  needs-outcome [--today yyyy-MM-dd]
  export --out DIR                        Obsidian Markdown + grimoire.jsonl

  Global: --store PATH (default $GRIMOIRE_STORE or ./grimoire-store.json)
"""

struct CLIError: Error, CustomStringConvertible { let description: String }

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
        var loc: GeoLocation?
        if let la = args.one("lat").flatMap(Double.init), let lo = args.one("lon").flatMap(Double.init) { loc = GeoLocation(latitude: la, longitude: lo) }
        try printJSON(TimingContext.compute(at: z, location: loc))

    case "ingest":
        let lib = try loadLibrary(args)
        guard let folder = args.positional.first else { throw CLIError(description: "ingest needs the GrimoireInbox folder") }
        let store = try openStore(args)
        let ingestor = InboxIngestor(root: URL(fileURLWithPath: folder), transcriber: SidecarTextTranscriber(), parser: ReadingParser(library: lib))
        if let s = args.one("stable-seconds").flatMap(Double.init) { ingestor.stableSeconds = s }
        if let tz = args.one("tz") { ingestor.defaultTimeZone = tz }
        if let la = args.one("lat").flatMap(Double.init), let lo = args.one("lon").flatMap(Double.init) { ingestor.location = GeoLocation(latitude: la, longitude: lo) }
        let outcomes = await ingestor.scan(isKnown: store.knowsCapture, deliver: store.addToInbox)
        try store.flush()
        for o in outcomes { print(o) }

    case "import":
        let lib = try loadLibrary(args)
        guard !args.positional.isEmpty else { throw CLIError(description: "import needs files or folders (.docx, .md, .txt)") }
        let store = try openStore(args)
        var importer = DocumentImporter(parser: ReadingParser(library: lib))
        if let tz = args.one("tz") { importer.timeZone = tz }
        if let la = args.one("lat").flatMap(Double.init), let lo = args.one("lon").flatMap(Double.init) { importer.location = GeoLocation(latitude: la, longitude: lo) }
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
        let preset = ReminderPreset(rawValue: args.one("reminder") ?? "none") ?? .none
        let result = try store.confirm(id, corrected: draft, library: lib, reminder: preset)
        try store.flush()
        print("filed entry \(result.entry.id)" + (result.inquiry.map { " and inquiry \($0.id): \($0.question)" } ?? ""))
        if !result.corrections.isEmpty { print("logged \(result.corrections.count) correction(s)") }

    case "add":
        let store = try openStore(args)
        guard args.positional.count >= 2, let type = EntryType(rawValue: args.positional[0]), type != .divination else {
            throw CLIError(description: "add needs a type (journal, ritual, meditation, vision, contact, omen, insight, dream) and a body")
        }
        let now = ZonedDate(Date())
        let e = Entry(type: type, title: args.one("title"), occurredAt: now, body: args.positional[1],
                      tags: args.all("tag").map { TagPath($0) }, timing: TimingContext.compute(at: now, location: nil), mode: .quick)
        store.save(e)
        try store.flush()
        print(e.id)

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

    case "export":
        let lib = try loadLibrary(args)
        let store = try openStore(args)
        guard let out = args.one("out") else { throw CLIError(description: "export needs --out DIR") }
        let root = URL(fileURLWithPath: out)
        var files = ObsidianExporter(library: lib).files(for: store.data)
        files["grimoire.jsonl"] = try JSONLExporter(library: lib).export(store.data)
        let report = try ExportWriter.write(files, to: root)
        print("\(report.written.count) written, \(report.unchanged) unchanged")

    default:
        print(usage)
        throw CLIError(description: "unknown command \(command)")
    }
}

do { try await run() } catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
