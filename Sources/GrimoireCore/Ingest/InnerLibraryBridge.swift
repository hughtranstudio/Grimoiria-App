import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The courier between Hugh's Inner Library (hughtranstudio.com/intima) and this app, run by `grimoire bridge`.
/// The site is one more capture device: it speaks the phone's sidecar contract v1, and gets back only the
/// counts in `grimoire-status.json`. Grimoire stays the one home for the practice record (my-website ADR 0005).
///
/// One `sync()`:
///   1. pull: the sidecars waiting in the room's outbox;
///   2. write each into `GrimoireInbox/incoming/<id>.json` (atomically), where `InboxIngestor` picks it up and the
///      Inbox asks you to confirm it, like any phone capture. A capture already in `incoming/` or `processed/`
///      is not written again; the ingestor also ignores a capture id it already knows;
///   3. ack: the ids now safely on disk, so the site deletes them;
///   4. status: the StatusSummary card, counts and `grimoire://` links only.
/// Nothing from the Grimoire's records is ever sent: only the status card.
public final class InnerLibraryBridge: @unchecked Sendable {
    /// The `device` every capture from the room carries.
    public static let device = "inner-library"

    public let inbox: URL
    public let fs: IngestFileSystem
    public let transport: BridgeTransport

    public var incoming: URL { inbox.appendingPathComponent("incoming") }
    public var processed: URL { inbox.appendingPathComponent("processed") }

    public init(inbox: URL, transport: BridgeTransport, fs: IngestFileSystem = LocalFileSystem()) {
        self.inbox = inbox
        self.transport = transport
        self.fs = fs
    }

    public struct Report: Equatable, Sendable {
        /// Written into `incoming/` this time.
        public var delivered: [String] = []
        /// Already on disk from an earlier run (acked again, not rewritten).
        public var alreadyHere: [String] = []
        /// Refused, with the reason; left in the room's outbox.
        public var refused: [String: String] = [:]
        /// How many the site says it has now forgotten.
        public var collected: Int = 0
        public var statusSent = false
        public init() {}
    }

    /// The setup check: answers how many captures wait, or throws why the bridge is shut.
    public func hello() async throws -> Int {
        let o = try await call(["action": "hello"])
        return o["waiting"] as? Int ?? 0
    }

    /// Pull, write, ack, then push the status card (raw `grimoire-status.json` bytes), if given.
    public func sync(status: Data? = nil) async throws -> Report {
        var report = Report()
        let answer = try await call(["action": "pull"])
        guard let captures = answer["captures"] as? [[String: Any]] else { throw BridgeError.badResponse("no captures list") }
        if !captures.isEmpty, !fs.exists(incoming) { try fs.makeDirectory(incoming) }

        var done: [String] = []
        for raw in captures {
            let label = (raw["id"] as? String) ?? "(no id)"
            do {
                let data = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys])
                let sidecar = try Self.check(data)
                let name = "\(sidecar.id).json"
                if fs.exists(incoming.appendingPathComponent(name)) || fs.exists(processed.appendingPathComponent(name)) {
                    report.alreadyHere.append(sidecar.id)
                } else {
                    try fs.write(data, to: incoming.appendingPathComponent(name))
                    report.delivered.append(sidecar.id)
                }
                done.append(sidecar.id)
            } catch {
                report.refused[label] = "\(error)"
            }
        }
        if !done.isEmpty {
            let acked = try await call(["action": "ack", "ids": done])
            report.collected = acked["collected"] as? Int ?? 0
        }
        if let status {
            guard let card = try? JSONSerialization.jsonObject(with: status) as? [String: Any] else { throw BridgeError.badResponse("the status file is not JSON") }
            _ = try await call(["action": "status", "status": card])
            report.statusSent = true
        }
        return report
    }

    /// A sidecar from the room must pass the same decode as a phone's, and more: a plain file-safe id, the room's
    /// device name, and no audio (the room never sends any), so nothing it sends can name a path.
    public static func check(_ data: Data) throws -> CaptureSidecar {
        let s = try CaptureSidecar.decode(data)
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        guard s.id.count <= 64, s.id.unicodeScalars.allSatisfy({ safe.contains($0) }), !s.id.hasPrefix("-") else {
            throw IngestError.badSidecar("id must be letters, digits and hyphens")
        }
        guard s.device == device else { throw IngestError.badSidecar("device must be \(device)") }
        guard s.audio == nil else { throw IngestError.badSidecar("the Inner Library sends no audio") }
        return s
    }

    private func call(_ body: [String: Any]) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let (status, reply) = try await transport.post(data)
        let object = (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any]
        guard status == 200 else { throw BridgeError.refused(status, object?["error"] as? String ?? "HTTP \(status)") }
        guard let object else { throw BridgeError.badResponse("not JSON") }
        return object
    }
}

public enum BridgeError: Error, Equatable, CustomStringConvertible {
    case notSetUp(String)
    case refused(Int, String)
    case unreachable(String)
    case badResponse(String)

    public var description: String {
        switch self {
        case .notSetUp(let s): return "The Inner Library bridge is not set up: \(s)"
        case .refused(let code, let s):
            switch code {
            case 401: return "The Inner Library refused the token (401). Check INTIMA_BRIDGE_TOKEN matches Netlify."
            case 423: return "The Inner Library is locked everywhere (423). Open it with your passkey to start the bridge again."
            case 503: return "The Inner Library bridge is not set up on the site (503): \(s)"
            default: return "The Inner Library said \(code): \(s)"
            }
        case .unreachable(let s): return "The Inner Library could not be reached: \(s)"
        case .badResponse(let s): return "Unexpected answer from the Inner Library: \(s)"
        }
    }
}

/// How the bridge reaches the site; tests swap in a fake.
public protocol BridgeTransport: Sendable {
    func post(_ body: Data) async throws -> (Int, Data)
}

/// `POST <site>/api/intima/bridge` with `Authorization: Bearer <INTIMA_BRIDGE_TOKEN>`.
public struct HTTPBridgeTransport: BridgeTransport {
    public let url: URL
    let token: String
    public var timeout: TimeInterval = 30

    /// `site` like https://hughtranstudio.com. Only https is allowed, except a localhost address for `npm run dev`.
    public init(site: String, token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 32 else { throw BridgeError.notSetUp("INTIMA_BRIDGE_TOKEN is missing or shorter than 32 characters") }
        guard let base = URL(string: site), let scheme = base.scheme, let host = base.host else { throw BridgeError.notSetUp("not a web address: \(site)") }
        guard scheme == "https" || (scheme == "http" && (host == "localhost" || host == "127.0.0.1")) else {
            throw BridgeError.notSetUp("the site must be https (or localhost for a dev server)")
        }
        url = base.appendingPathComponent("api/intima/bridge")
        self.token = trimmed
    }

    public func post(_ body: Data) async throws -> (Int, Data) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("grimoiria-bridge/1", forHTTPHeaderField: "User-Agent")
        req.httpBody = body
        req.timeoutInterval = timeout
        return try await withCheckedThrowingContinuation { cont in
            URLSession.shared.dataTask(with: req) { data, response, error in
                if let error { cont.resume(throwing: BridgeError.unreachable(error.localizedDescription)); return }
                guard let http = response as? HTTPURLResponse else { cont.resume(throwing: BridgeError.badResponse("no HTTP response")); return }
                cont.resume(returning: (http.statusCode, data ?? Data()))
            }.resume()
        }
    }
}
