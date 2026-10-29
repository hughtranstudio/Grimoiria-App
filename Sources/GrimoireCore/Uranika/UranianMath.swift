import Foundation

/// The Hamburg-school arithmetic Grimoire needs, ported from Uranika's `static/astro.js`
/// (`hits`, `angleOf`, `sdiff`) so both apps read a moment the same way.
public enum UranianMath {
    /// Uranika's point keys (from `/api/compute`) → the formula codes Uranika shows (SU, MO … PO).
    public static let codes: [(key: String, code: String)] = [
        ("SUN", "SU"), ("MOO", "MO"), ("MER", "ME"), ("VEN", "VE"), ("MAR", "MA"), ("JUP", "JU"),
        ("SAT", "SA"), ("URA", "UR"), ("NEP", "NE"), ("PLU", "PL"), ("NOD", "NN"),
        ("CUP", "CU"), ("HAD", "HA"), ("ZEU", "ZE"), ("KRO", "KR"), ("APO", "AP"), ("ADM", "AD"), ("VUL", "VU"), ("POS", "PO"),
    ]
    /// Bodies, then the personal points, in Uranika's order. Used for stable output.
    public static let order: [String] = codes.map(\.code) + ["AS", "MC", "AR"]
    static let codeOf: [String: String] = Dictionary(uniqueKeysWithValues: codes.map { ($0.key, $0.code) })

    public static func code(forKey key: String) -> String? { codeOf[key] }

    public static func norm(_ x: Double, _ m: Double = 360) -> Double {
        let r = x.truncatingRemainder(dividingBy: m)
        return r < 0 ? r + m : r
    }

    /// Signed difference folded into (-m/2, m/2].
    public static func sdiff(_ v: Double, _ m: Double) -> Double {
        var d = norm(v, m)
        if d > m / 2 { d -= m }
        return d
    }

    /// Nearest multiple of the modulus, folded to 0…180.
    public static func angleOf(_ delta: Double, _ mod: Double) -> Double {
        var a = norm(delta, 360)
        if a > 180 { a = 360 - a }
        return (a / mod).rounded() * mod
    }

    /// Moving points (`movers`) on natal points and midpoints (`targets`), within `orb` at `modulus`.
    /// Same rule as Uranika: a point hit is any multiple of the modulus; a midpoint hit is 2D = A + B (mod 2 × modulus).
    public static func hits(method: AstroHit.Method, movers: [String: Double], targets: [String: Double],
                            modulus: Double, orb: Double) -> [AstroHit] {
        let mk = order.filter { movers[$0] != nil }
        let tk = order.filter { targets[$0] != nil }
        var out: [AstroHit] = []
        for d in mk {
            let src = movers[d]!
            for n in tk {
                let off = abs(sdiff(src - targets[n]!, modulus))
                if off <= orb { out.append(AstroHit(method: method, mover: d, target: [n], angle: angleOf(src - targets[n]!, modulus), orb: off)) }
            }
            for i in tk.indices {
                for j in tk.indices where j > i {
                    let a = tk[i], b = tk[j]
                    let off = abs(sdiff(2 * src - targets[a]! - targets[b]!, 2 * modulus)) / 2
                    if off <= orb { out.append(AstroHit(method: method, mover: d, target: [a, b], angle: nil, orb: off)) }
                }
            }
        }
        return out.sorted { ($0.orb, $0.formula) < ($1.orb, $1.formula) }
    }

    public static func aspectSymbol(_ angle: Double) -> String {
        switch angle {
        case 0: return "☌"
        case 45: return "∠"
        case 90: return "□"
        case 135: return "⚼"
        case 180: return "☍"
        default: return angle == angle.rounded() ? "\(Int(angle))°" : "\(angle)°"
        }
    }

    /// 0°24′, with ° and ′ as in Uranika.
    public static func formatDegrees(_ x: Double) -> String {
        var d = Int(abs(x))
        var m = Int(((abs(x) - Double(d)) * 60).rounded())
        if m == 60 { d += 1; m = 0 }
        return "\(d)°" + (m < 10 ? "0" : "") + "\(m)′"
    }

    static func round(_ x: Double, _ decimals: Int = 2) -> Double {
        let f = pow(10, Double(decimals))
        return (x * f).rounded() / f
    }
}
