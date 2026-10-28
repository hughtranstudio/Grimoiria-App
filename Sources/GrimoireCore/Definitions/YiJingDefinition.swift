import Foundation

/// `yijing.json`: trigram table and the 64 hexagrams in King Wen order.
public struct YiJingDefinition: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var version: Int
    public var aliases: [String]
    public var trigrams: [Trigram]
    public var hexagrams: [Hexagram]

    public struct Trigram: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var symbol: String
        public var image: String
        /// Bottom to top, 1 = yang.
        public var lines: [Int]
    }

    public struct Hexagram: Codable, Hashable, Sendable {
        public var number: Int
        public var pinyin: String
        public var name: String
        public var lower: String
        public var upper: String
        /// Bottom to top, 1 = yang.
        public var lines: [Int]
        public var significations: [String: AttributeValue]?
    }

    public func hexagram(_ number: Int) -> Hexagram? { hexagrams.first { $0.number == number } }

    /// Hexagram number for six yin/yang lines, bottom to top.
    public func number(forLines lines: [Bool]) -> Int? {
        let bits = lines.map { $0 ? 1 : 0 }
        return hexagrams.first { $0.lines == bits }?.number
    }
}
