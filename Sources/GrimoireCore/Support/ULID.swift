import Foundation

/// Universally Unique Lexicographically Sortable Identifier.
/// 48-bit millisecond timestamp + 80 random bits, Crockford base32, 26 chars.
public struct ULID: Hashable, Comparable, Codable, CustomStringConvertible, Sendable {
    public let string: String

    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public init(date: Date = Date()) {
        var rng = SystemRandomNumberGenerator()
        self.init(date: date, using: &rng)
    }

    public init<R: RandomNumberGenerator>(date: Date, using rng: inout R) {
        let ms = UInt64(max(0, (date.timeIntervalSince1970 * 1000).rounded(.down)))
        var chars = [Character]()
        chars.reserveCapacity(26)
        // 10 chars of time (50 bits, top 2 always zero for 48-bit time)
        for i in (0..<10).reversed() {
            chars.append(Self.alphabet[Int((ms >> (UInt64(i) * 5)) & 0x1F)])
        }
        for _ in 0..<16 {
            chars.append(Self.alphabet[Int(rng.next() & 0x1F)])
        }
        self.string = String(chars)
    }

    public init?(_ string: String) {
        let upper = string.uppercased()
        guard upper.count == 26, upper.allSatisfy({ Self.alphabet.contains($0) }) else { return nil }
        self.string = upper
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let id = ULID(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid ULID \(raw)"))
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(string)
    }

    /// Milliseconds since the Unix epoch encoded in the first 10 chars.
    public var date: Date {
        var ms: UInt64 = 0
        for ch in string.prefix(10) {
            ms = (ms << 5) | UInt64(Self.alphabet.firstIndex(of: ch)!)
        }
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }

    public var description: String { string }
    public static func < (a: ULID, b: ULID) -> Bool { a.string < b.string }
}
