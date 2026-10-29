import Foundation

/// Just enough ZIP to read a .docx: stored and deflated entries, located through the central
/// directory. No Zip64, no encryption. Pure Swift so it runs the same on macOS and Linux.
public struct ZipArchive: Sendable {
    public struct Entry: Sendable {
        public var name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    let bytes: [UInt8]
    public let entries: [Entry]

    public init(data: Data) throws {
        bytes = [UInt8](data)
        entries = try Self.readCentralDirectory(bytes)
    }

    public func entry(_ name: String) -> Entry? { entries.first { $0.name == name } }

    public func contents(of name: String) throws -> Data {
        guard let e = entry(name) else { throw ImportError.badFile("zip has no \(name)") }
        return try contents(of: e)
    }

    public func contents(of e: Entry) throws -> Data {
        let h = e.localHeaderOffset
        guard h + 30 <= bytes.count, u32(bytes, h) == 0x0403_4B50 else { throw ImportError.badFile("bad local header for \(e.name)") }
        let start = h + 30 + Int(u16(bytes, h + 26)) + Int(u16(bytes, h + 28))
        guard start + e.compressedSize <= bytes.count else { throw ImportError.badFile("\(e.name) runs past the end of the zip") }
        let raw = Array(bytes[start..<(start + e.compressedSize)])
        switch e.method {
        case 0: return Data(raw)
        case 8:
            let out = try Inflate.inflate(raw, expectedSize: e.uncompressedSize)
            guard out.count == e.uncompressedSize else { throw ImportError.badFile("\(e.name) inflated to the wrong size") }
            return Data(out)
        default: throw ImportError.badFile("\(e.name) uses unsupported compression method \(e.method)")
        }
    }

    static func readCentralDirectory(_ b: [UInt8]) throws -> [Entry] {
        // End of central directory: 22 bytes plus up to 64 KB of comment, searched from the end.
        guard b.count >= 22 else { throw ImportError.badFile("too short to be a zip") }
        var eocd = -1
        var i = b.count - 22
        while i >= max(0, b.count - 22 - 0xFFFF) {
            if u32(b, i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ImportError.badFile("not a zip (no end of central directory)") }
        let count = Int(u16(b, eocd + 10))
        var p = Int(u32(b, eocd + 16))
        if count == 0xFFFF || p == 0xFFFF_FFFF { throw ImportError.badFile("Zip64 archives are not supported") }
        var out: [Entry] = []
        for _ in 0..<count {
            guard p + 46 <= b.count, u32(b, p) == 0x0201_4B50 else { throw ImportError.badFile("bad central directory") }
            let nameLen = Int(u16(b, p + 28)), extraLen = Int(u16(b, p + 30)), commentLen = Int(u16(b, p + 32))
            guard p + 46 + nameLen <= b.count else { throw ImportError.badFile("bad central directory") }
            let name = String(decoding: b[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            out.append(Entry(name: name, method: u16(b, p + 10), compressedSize: Int(u32(b, p + 20)),
                             uncompressedSize: Int(u32(b, p + 24)), localHeaderOffset: Int(u32(b, p + 42))))
            p += 46 + nameLen + extraLen + commentLen
        }
        return out
    }
}

@inline(__always) func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
@inline(__always) func u32(_ b: [UInt8], _ i: Int) -> UInt32 { UInt32(u16(b, i)) | UInt32(u16(b, i + 2)) << 16 }

/// Raw DEFLATE decoder (RFC 1951), after Mark Adler's puff.c: canonical Huffman tables built
/// from code lengths, decoded one bit at a time. Fast enough for documents.
public enum Inflate {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    struct Huffman {
        var count = [Int](repeating: 0, count: 16)
        var symbol: [Int]

        init(lengths: ArraySlice<Int>) throws {
            symbol = [Int](repeating: 0, count: lengths.count)
            for l in lengths { count[l] += 1 }
            count[0] = 0
            var left = 1
            for len in 1...15 {
                left <<= 1
                left -= count[len]
                if left < 0 { throw Failure(description: "over-subscribed Huffman code") }
            }
            var offs = [Int](repeating: 0, count: 16)
            for len in 1..<15 { offs[len + 1] = offs[len] + count[len] }
            for (sym, l) in lengths.enumerated() where l != 0 {
                symbol[offs[l]] = sym
                offs[l] += 1
            }
        }
    }

    struct Reader {
        let input: [UInt8]
        var pos = 0
        var bitBuf = 0
        var bitCount = 0

        mutating func bits(_ need: Int) throws -> Int {
            var val = bitBuf
            while bitCount < need {
                guard pos < input.count else { throw Failure(description: "unexpected end of compressed data") }
                val |= Int(input[pos]) << bitCount
                pos += 1
                bitCount += 8
            }
            bitBuf = val >> need
            bitCount -= need
            return val & ((1 << need) - 1)
        }

        mutating func decode(_ h: Huffman) throws -> Int {
            var code = 0, first = 0, index = 0
            for len in 1...15 {
                code |= try bits(1)
                let count = h.count[len]
                if code - count < first { return h.symbol[index + (code - first)] }
                index += count
                first += count
                first <<= 1
                code <<= 1
            }
            throw Failure(description: "invalid Huffman code")
        }
    }

    static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    static let distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
                           4097, 6145, 8193, 12289, 16385, 24577]
    static let distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    static let fixed: (Huffman, Huffman) = {
        var l = [Int](repeating: 8, count: 288)
        for i in 144..<256 { l[i] = 9 }
        for i in 256..<280 { l[i] = 7 }
        return (try! Huffman(lengths: l[...]), try! Huffman(lengths: [Int](repeating: 5, count: 30)[...]))
    }()

    public static func inflate(_ input: [UInt8], expectedSize: Int = 0) throws -> [UInt8] {
        var r = Reader(input: input)
        var out: [UInt8] = []
        out.reserveCapacity(expectedSize)
        var last = 0
        repeat {
            last = try r.bits(1)
            switch try r.bits(2) {
            case 0:
                r.bitBuf = 0; r.bitCount = 0
                guard r.pos + 4 <= input.count else { throw Failure(description: "truncated stored block") }
                let len = Int(u16(input, r.pos)), nlen = Int(u16(input, r.pos + 2))
                guard len == (~nlen & 0xFFFF) else { throw Failure(description: "stored block length mismatch") }
                r.pos += 4
                guard r.pos + len <= input.count else { throw Failure(description: "truncated stored block") }
                out.append(contentsOf: input[r.pos..<(r.pos + len)])
                r.pos += len
            case 1:
                try codes(&r, &out, fixed.0, fixed.1)
            case 2:
                let (lit, dist) = try dynamicTables(&r)
                try codes(&r, &out, lit, dist)
            default:
                throw Failure(description: "invalid block type")
            }
        } while last == 0
        return out
    }

    static func dynamicTables(_ r: inout Reader) throws -> (Huffman, Huffman) {
        let nlen = try r.bits(5) + 257, ndist = try r.bits(5) + 1, ncode = try r.bits(4) + 4
        guard nlen <= 286, ndist <= 30 else { throw Failure(description: "bad dynamic block counts") }
        var lengths = [Int](repeating: 0, count: 19)
        for i in 0..<ncode { lengths[codeLengthOrder[i]] = try r.bits(3) }
        let lencode = try Huffman(lengths: lengths[...])
        lengths = []
        while lengths.count < nlen + ndist {
            let sym = try r.decode(lencode)
            if sym < 16 { lengths.append(sym); continue }
            var value = 0, repeatCount: Int
            switch sym {
            case 16:
                guard let prev = lengths.last else { throw Failure(description: "repeat with no previous length") }
                value = prev
                repeatCount = 3 + (try r.bits(2))
            case 17: repeatCount = 3 + (try r.bits(3))
            default: repeatCount = 11 + (try r.bits(7))
            }
            guard lengths.count + repeatCount <= nlen + ndist else { throw Failure(description: "too many code lengths") }
            lengths.append(contentsOf: repeatElement(value, count: repeatCount))
        }
        guard lengths[256] != 0 else { throw Failure(description: "no end-of-block code") }
        return (try Huffman(lengths: lengths[0..<nlen]), try Huffman(lengths: lengths[nlen...]))
    }

    static func codes(_ r: inout Reader, _ out: inout [UInt8], _ lit: Huffman, _ dist: Huffman) throws {
        while true {
            let sym = try r.decode(lit)
            if sym < 256 { out.append(UInt8(sym)); continue }
            if sym == 256 { return }
            let li = sym - 257
            guard li < lengthBase.count else { throw Failure(description: "bad length code") }
            let len = lengthBase[li] + (try r.bits(lengthExtra[li]))
            let di = try r.decode(dist)
            guard di < distBase.count else { throw Failure(description: "bad distance code") }
            let d = distBase[di] + (try r.bits(distExtra[di]))
            guard d <= out.count else { throw Failure(description: "distance too far back") }
            let start = out.count - d
            for k in 0..<len { out.append(out[start + k]) }
        }
    }
}
