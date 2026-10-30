import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What Grimoire uses of Uranika's local server (`~/Uranika/server.py`, 127.0.0.1:8765).
/// Nothing here leaves the Mac: Uranika runs on the same computer.
public protocol UranikaService: Sendable {
    /// Swiss Ephemeris version; throws `.unreachable` when Uranika is not open.
    func health() async throws -> String
    func compute(_ request: UranikaComputeRequest) async throws -> UranikaComputeResult
    func charts() async throws -> [UranikaChart]
    /// Adds a life event to a chart's case file; returns the new event's id.
    func addEvent(_ event: UranikaEvent) async throws -> Int
}

public enum UranikaError: Error, Equatable, CustomStringConvertible {
    case unreachable(String)
    case server(String)
    case badResponse(String)

    public var description: String {
        switch self {
        case .unreachable(let s): return "Uranika is not open (\(s))"
        case .server(let s): return "Uranika said: \(s)"
        case .badResponse(let s): return "Unexpected answer from Uranika: \(s)"
        }
    }
}

/// Body of `POST /api/compute`. `date`/`time` are local to `tz` (IANA); `target` is the
/// directing moment in UTC.
public struct UranikaComputeRequest: Codable, Hashable, Sendable {
    public var date: String
    public var time: String
    public var tz: String
    public var lat: Double
    public var lon: Double
    public var target: String
    public var rate: String

    public init(date: String, time: String, tz: String, lat: Double, lon: Double, target: String, rate: String) {
        self.date = date; self.time = time; self.tz = tz; self.lat = lat; self.lon = lon; self.target = target; self.rate = rate
    }

    /// A chart cast for `instant` itself, sent in UTC so any recorded zone works.
    public static func moment(_ instant: Date, lat: Double, lon: Double, rate: String) -> UranikaComputeRequest {
        let (d, t) = utcParts(instant)
        return UranikaComputeRequest(date: d, time: t, tz: "UTC", lat: lat, lon: lon, target: "\(d)T\(t)", rate: rate)
    }

    /// A natal chart directed to `instant`.
    public static func natal(_ chart: UranikaChart, directedTo instant: Date, rate: String) -> UranikaComputeRequest {
        let (d, t) = utcParts(instant)
        return UranikaComputeRequest(date: chart.date, time: chart.time, tz: chart.tz, lat: chart.lat, lon: chart.lon, target: "\(d)T\(t)", rate: rate)
    }

    static func utcParts(_ instant: Date) -> (String, String) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        let d = f.string(from: instant)
        f.dateFormat = "HH:mm:ss"
        return (d, f.string(from: instant))
    }
}

/// The parts of `/api/compute`'s answer Grimoire reads.
public struct UranikaComputeResult: Decodable, Sendable {
    public struct Point: Decodable, Sendable { public var lon: Double }
    public struct Natal: Decodable, Sendable {
        public var points: [String: Point]
        public var asc: Double
        public var mc: Double
    }
    public struct Moving: Decodable, Sendable { public var points: [String: Point] }

    public var natal: Natal
    public var transit: Moving
    public var arc: Double
    public var warning: String?

    public init(natal: Natal, transit: Moving, arc: Double, warning: String? = nil) {
        self.natal = natal; self.transit = transit; self.arc = arc; self.warning = warning
    }
}

/// A saved chart in Uranika's library (`GET /api/charts`).
public struct UranikaChart: Codable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var date: String
    public var time: String
    public var tz: String
    public var lat: Double
    public var lon: Double

    public init(id: Int, name: String, date: String, time: String, tz: String, lat: Double, lon: Double) {
        self.id = id; self.name = name; self.date = date; self.time = time; self.tz = tz; self.lat = lat; self.lon = lon
    }
}

/// Body of `POST /api/events`, as Uranika's Library sends it.
public struct UranikaEvent: Codable, Hashable, Sendable {
    public var chartId: Int
    /// yyyy-MM-dd
    public var date: String
    /// day, month, year or approx
    public var certainty: String
    /// One of Uranika's categories: relationship, family, career, finances, health, relocation,
    /// public life, education, loss, accident, spiritual, other.
    public var category: String
    public var title: String
    public var notes: String

    enum CodingKeys: String, CodingKey { case chartId = "chart_id", date, certainty, category, title, notes }

    public init(chartId: Int, date: String, certainty: String = "day", category: String, title: String, notes: String) {
        self.chartId = chartId; self.date = date; self.certainty = certainty; self.category = category; self.title = title; self.notes = notes
    }
}

/// Talks to Uranika over HTTP on the same Mac.
public struct UranikaHTTPClient: UranikaService {
    public var baseURL: URL
    public var timeout: TimeInterval

    public init(baseURL: URL = URL(string: "http://127.0.0.1:8765")!, timeout: TimeInterval = 10) {
        self.baseURL = baseURL
        self.timeout = timeout
    }

    public func health() async throws -> String {
        struct H: Decodable { var ok: Bool; var swisseph: String? }
        let h: H = try await get("/api/health")
        return h.swisseph ?? "?"
    }

    public func compute(_ request: UranikaComputeRequest) async throws -> UranikaComputeResult {
        try await post("/api/compute", request)
    }

    public func charts() async throws -> [UranikaChart] {
        // Rows carry many more columns; decode the ones we need and skip rows missing birth data.
        struct Row: Decodable {
            var id: Int; var name: String?; var date: String?; var time: String?; var tz: String?; var lat: Double?; var lon: Double?
        }
        let rows: [Row] = try await get("/api/charts")
        return rows.compactMap { r in
            guard let d = r.date, let t = r.time, let z = r.tz, let la = r.lat, let lo = r.lon else { return nil }
            return UranikaChart(id: r.id, name: r.name ?? "Untitled", date: d, time: t, tz: z, lat: la, lon: lo)
        }
    }

    public func addEvent(_ event: UranikaEvent) async throws -> Int {
        struct R: Decodable { var id: Int }
        let r: R = try await post("/api/events", event)
        return r.id
    }

    // MARK: Plumbing

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(URLRequest(url: baseURL.appendingPathComponent(path)))
    }

    func post<B: Encodable, T: Decodable>(_ path: String, _ body: B) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        return try await send(req)
    }

    func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        var request = request
        request.timeoutInterval = timeout
        let (data, status) = try await Self.load(request)
        if status != 200 {
            if let e = try? JSONDecoder().decode(ErrorBody.self, from: data) { throw UranikaError.server(e.error) }
            throw UranikaError.server("HTTP \(status)")
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw UranikaError.badResponse("\(error)") }
    }

    struct ErrorBody: Decodable { var error: String }

    static func load(_ request: URLRequest) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { cont in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error { cont.resume(throwing: UranikaError.unreachable(error.localizedDescription)); return }
                guard let http = response as? HTTPURLResponse else { cont.resume(throwing: UranikaError.badResponse("no HTTP response")); return }
                cont.resume(returning: (data ?? Data(), http.statusCode))
            }.resume()
        }
    }
}
