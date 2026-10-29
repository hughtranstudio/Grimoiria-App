import Foundation

/// How Grimoire uses Uranika. Saved as JSON; the Mac app shows it in Settings.
public struct UranikaSettings: Codable, Hashable, Sendable {
    public enum Scope: String, Codable, Sendable {
        /// Every captured entry gets a chart (useful for the moon/transit analytics later).
        case all
        /// Only life events.
        case events
    }

    public var enabled: Bool
    public var baseURL: String
    /// Hugh's own chart in Uranika's library. Without it only the sky of the moment is stored, no hits.
    public var natalChartId: Int?
    /// The fixed place charts are cast for (Hugh's choice, 2026-10-29: a fixed home place first).
    public var home: AstroPlace?
    /// Use the phone's position when the capture has one, instead of `home`.
    public var useCapturedLocation: Bool
    /// Coordinates are rounded to this many decimals on arrival (2 ≈ 1 km).
    public var coordinateDecimals: Int
    public var scope: Scope
    public var hits: HitSettings
    /// After confirm, add life events to the natal chart's case file in Uranika.
    public var recordEventsInUranika: Bool
    public var eventCategory: String

    public init(enabled: Bool = true, baseURL: String = "http://127.0.0.1:8765", natalChartId: Int? = nil, home: AstroPlace? = nil,
                useCapturedLocation: Bool = false, coordinateDecimals: Int = 2, scope: Scope = .all, hits: HitSettings = HitSettings(),
                recordEventsInUranika: Bool = false, eventCategory: String = "other") {
        self.enabled = enabled; self.baseURL = baseURL; self.natalChartId = natalChartId; self.home = home
        self.useCapturedLocation = useCapturedLocation; self.coordinateDecimals = coordinateDecimals; self.scope = scope
        self.hits = hits; self.recordEventsInUranika = recordEventsInUranika; self.eventCategory = eventCategory
    }

    public static func load(from url: URL) throws -> UranikaSettings {
        try JSONDecoder().decode(UranikaSettings.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try enc.encode(self).write(to: url, options: .atomic)
    }
}

/// Builds `AstroSnapshot`s from Uranika. Never throws for a missing Uranika: the snapshot comes
/// back `pending` and `fillPending` completes it the next time Uranika is open.
public struct UranikaAstrologer: Sendable {
    public var service: UranikaService
    public var settings: UranikaSettings

    public init(service: UranikaService, settings: UranikaSettings) {
        self.service = service
        self.settings = settings
    }

    public init(settings: UranikaSettings) {
        self.init(service: UranikaHTTPClient(baseURL: URL(string: settings.baseURL) ?? URL(string: "http://127.0.0.1:8765")!), settings: settings)
    }

    public func applies(to type: EntryType) -> Bool {
        settings.enabled && (settings.scope == .all || type == .event)
    }

    /// The place to cast for: home by default, the phone's position when allowed (or when no home is set).
    public func place(captured: GeoLocation?, fallback: GeoLocation?) -> AstroPlace? {
        let phone = captured.map { AstroPlace(name: nil, latitude: $0.latitude, longitude: $0.longitude) }
        let other = fallback.map { AstroPlace(name: $0.name, latitude: $0.latitude, longitude: $0.longitude) }
        let chosen = settings.useCapturedLocation ? (phone ?? settings.home ?? other) : (settings.home ?? other ?? phone)
        return chosen?.rounded(settings.coordinateDecimals)
    }

    public func snapshot(at moment: ZonedDate, place: AstroPlace?, now: Date = Date()) async -> AstroSnapshot {
        let hs = settings.hits
        var notes: [String] = []
        do {
            let req = UranikaComputeRequest.moment(moment.instant, lat: place?.latitude ?? 0, lon: place?.longitude ?? 0, rate: hs.rate)
            let sky = try await service.compute(req)
            var snap = AstroSnapshot(status: .computed, computedAt: now, place: place, points: Self.points(sky.transit.points), settings: hs)
            if place != nil {
                snap.asc = UranianMath.round(sky.natal.asc)
                snap.mc = UranianMath.round(sky.natal.mc)
            } else {
                notes.append("No place set, so the Ascendant and Meridian were left out")
            }
            if let w = sky.warning { notes.append(w) }

            if let id = settings.natalChartId {
                if let chart = try await service.charts().first(where: { $0.id == id }) {
                    let directed = try await service.compute(.natal(chart, directedTo: moment.instant, rate: hs.rate))
                    var natal = Self.rawPoints(directed.natal.points)
                    natal["AS"] = directed.natal.asc
                    natal["MC"] = directed.natal.mc
                    natal["AR"] = 0
                    let transits = Self.rawPoints(directed.transit.points)
                    let arcs = natal.mapValues { UranianMath.norm($0 + directed.arc) }
                    let t = UranianMath.hits(method: .transit, movers: transits, targets: natal, modulus: hs.modulus, orb: hs.orb)
                    let d = UranianMath.hits(method: .solarArc, movers: arcs, targets: natal, modulus: hs.modulus, orb: hs.orb)
                    snap.natal = NatalRef(uranikaChart: chart.id, name: chart.name)
                    snap.solarArc = UranianMath.round(directed.arc)
                    snap.hits = (Array(t.prefix(hs.maxHits)) + Array(d.prefix(hs.maxHits))).map { h in
                        var h = h; h.orb = UranianMath.round(h.orb); return h
                    }
                } else {
                    notes.append("Chart \(id) is not in Uranika's library, so no transits or solar arcs were measured")
                }
            } else {
                notes.append("No natal chart chosen, so no transits or solar arcs were measured")
            }
            snap.note = notes.isEmpty ? nil : notes.joined(separator: ". ")
            return snap
        } catch let e as UranikaError {
            if case .unreachable = e { return .pending(place: place, settings: hs, note: "Chart pending: Uranika was not open") }
            return .pending(place: place, settings: hs, note: "Chart pending: \(e)")
        } catch {
            return .pending(place: place, settings: hs, note: "Chart pending: \(error)")
        }
    }

    /// Completes pending snapshots. Returns only the entries that changed.
    public func fillPending(_ entries: [Entry], now: Date = Date()) async -> [Entry] {
        var out: [Entry] = []
        for var e in entries where e.astro?.status == .pending {
            let snap = await snapshot(at: e.occurredAt, place: e.astro?.place, now: now)
            guard snap.status == .computed else {
                // Uranika still closed: stop early rather than waiting on every entry.
                if snap.note?.contains("not open") == true { break }
                continue
            }
            var filled = snap
            filled.uranikaEvent = e.astro?.uranikaEvent
            e.astro = filled
            out.append(e)
        }
        return out
    }

    /// Adds a filed life event to the natal chart's case file in Uranika, once. Returns the entry
    /// with `astro.uranikaEvent` set, or nil when nothing was sent.
    public func recordEvent(_ entry: Entry) async throws -> Entry? {
        guard settings.recordEventsInUranika, entry.type == .event, let chartId = settings.natalChartId,
              entry.astro?.uranikaEvent == nil else { return nil }
        let event = UranikaEvent(chartId: chartId, date: entry.occurredAt.day, category: settings.eventCategory,
                                 title: entry.displayTitle, notes: "From Grimoire \(entry.id)")
        let id = try await service.addEvent(event)
        var e = entry
        if e.astro == nil { e.astro = AstroSnapshot(status: .pending, settings: settings.hits, note: "Chart pending") }
        e.astro?.uranikaEvent = id
        return e
    }

    static func rawPoints(_ p: [String: UranikaComputeResult.Point]) -> [String: Double] {
        var out: [String: Double] = [:]
        for (k, v) in p { if let c = UranianMath.code(forKey: k) { out[c] = v.lon } }
        return out
    }

    static func points(_ p: [String: UranikaComputeResult.Point]) -> [String: Double] {
        rawPoints(p).mapValues { UranianMath.round($0) }
    }
}
