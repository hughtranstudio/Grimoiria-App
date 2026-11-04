import Foundation

/// A `grimoire://` link: what the calendar export, the vault and the Chamber's "Needs you" line point at.
/// Links carry ids and page names only, never content, so they are safe to leave the Mac.
///
///     grimoire://inbox                 the Inbox
///     grimoire://inbox/<ulid>          one capture waiting in the Inbox
///     grimoire://entry/<ulid>          a filed entry
///     grimoire://inquiry/<ulid>        a reading
///     grimoire://today                 Today
public enum GrimoireLink: Equatable, Sendable {
    public static let scheme = "grimoire"

    case today
    case inbox(ULID?)
    case entry(ULID)
    case inquiry(ULID)

    /// Reads a link; nil for another scheme, an unknown page, or a malformed id.
    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host()?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count <= 1 else { return nil }
        let id: ULID?
        if let first = parts.first {
            guard let parsed = ULID(first) else { return nil }
            id = parsed
        } else {
            id = nil
        }
        switch host {
        case "today" where id == nil: self = .today
        case "inbox": self = .inbox(id)
        case "entry": guard let id else { return nil }; self = .entry(id)
        case "inquiry": guard let id else { return nil }; self = .inquiry(id)
        default: return nil
        }
    }

    public init?(string: String) {
        guard let url = URL(string: string) else { return nil }
        self.init(url)
    }

    public var url: URL {
        let text = switch self {
        case .today: "today"
        case .inbox(let id): id.map { "inbox/\($0)" } ?? "inbox"
        case .entry(let id): "entry/\(id)"
        case .inquiry(let id): "inquiry/\(id)"
        }
        return URL(string: "\(Self.scheme)://\(text)")!
    }
}
