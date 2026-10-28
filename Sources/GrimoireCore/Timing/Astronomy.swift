import Foundation

/// Low-precision solar and lunar positions (after Meeus, "Astronomical Algorithms").
/// Accuracy: Sun ~0.01°, Moon ~0.3°, sunrise ~1–2 min. Good enough for sign, phase and planetary hours;
/// signs within ~0.5° of a cusp are flagged so the UI can show them as approximate.
public enum Astronomy {
    static let deg = Double.pi / 180

    public static func julianDay(_ date: Date) -> Double { date.timeIntervalSince1970 / 86_400 + 2_440_587.5 }

    static func norm360(_ x: Double) -> Double { let r = x.truncatingRemainder(dividingBy: 360); return r < 0 ? r + 360 : r }

    /// Apparent geocentric ecliptic longitude of the Sun, degrees.
    public static func sunLongitude(_ date: Date) -> Double {
        let T = (julianDay(date) - 2_451_545.0) / 36_525
        let L0 = norm360(280.46646 + 36_000.76983 * T + 0.0003032 * T * T)
        let M = norm360(357.52911 + 35_999.05029 * T - 0.0001537 * T * T) * deg
        let C = (1.914602 - 0.004817 * T - 0.000014 * T * T) * sin(M)
            + (0.019993 - 0.000101 * T) * sin(2 * M) + 0.000289 * sin(3 * M)
        let omega = (125.04 - 1934.136 * T) * deg
        return norm360(L0 + C - 0.00569 - 0.00478 * sin(omega))
    }

    /// Geocentric ecliptic longitude of the Moon, degrees (main periodic terms).
    public static func moonLongitude(_ date: Date) -> Double {
        let T = (julianDay(date) - 2_451_545.0) / 36_525
        let Lp = norm360(218.3164477 + 481_267.88123421 * T - 0.0015786 * T * T)
        let D = norm360(297.8501921 + 445_267.1114034 * T - 0.0018819 * T * T) * deg
        let M = norm360(357.5291092 + 35_999.0502909 * T - 0.0001536 * T * T) * deg
        let Mp = norm360(134.9633964 + 477_198.8675055 * T + 0.0087414 * T * T) * deg
        let F = norm360(93.2720950 + 483_202.0175233 * T - 0.0036539 * T * T) * deg
        let E = 1 - 0.002516 * T
        var sum = 0.0
        sum += 6.288774 * sin(Mp)
        sum += 1.274027 * sin(2 * D - Mp)
        sum += 0.658314 * sin(2 * D)
        sum += 0.213618 * sin(2 * Mp)
        sum -= 0.185116 * E * sin(M)
        sum -= 0.114332 * sin(2 * F)
        sum += 0.058793 * sin(2 * D - 2 * Mp)
        sum += 0.057066 * E * sin(2 * D - M - Mp)
        sum += 0.053322 * sin(2 * D + Mp)
        sum += 0.045758 * E * sin(2 * D - M)
        sum -= 0.040923 * E * sin(M - Mp)
        sum -= 0.034720 * sin(D)
        sum -= 0.030383 * E * sin(M + Mp)
        sum += 0.015327 * sin(2 * D - 2 * F)
        sum -= 0.012528 * sin(Mp + 2 * F)
        sum += 0.010980 * sin(Mp - 2 * F)
        sum += 0.010675 * sin(4 * D - Mp)
        sum += 0.010034 * sin(3 * Mp)
        sum += 0.008548 * sin(4 * D - 2 * Mp)
        return norm360(Lp + sum)
    }

    /// Sunrise and sunset (UTC instants) for the civil day containing `date` in `zone`,
    /// using the NOAA algorithm with the standard -0.833° altitude. Nil in polar day/night.
    public static func sunTimes(on date: Date, latitude: Double, longitude: Double, zone: TimeZone) -> (rise: Date, set: Date)? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let noonUTCGuess = utcCal.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 12)) else { return nil }
        // Solar noon shifts with longitude; iterate twice for rise and set separately.
        func event(rising: Bool) -> Date? {
            var t = noonUTCGuess.addingTimeInterval(-longitude / 15 * 3600)
            for _ in 0..<3 {
                let T = (julianDay(t) - 2_451_545.0) / 36_525
                let L0 = norm360(280.46646 + 36_000.76983 * T)
                let M = norm360(357.52911 + 35_999.05029 * T) * deg
                let e = 0.016708634 - 0.000042037 * T
                let C = (1.914602 - 0.004817 * T) * sin(M) + 0.019993 * sin(2 * M) + 0.000289 * sin(3 * M)
                let omega = (125.04 - 1934.136 * T) * deg
                let lambda = (L0 + C - 0.00569 - 0.00478 * sin(omega)) * deg
                let eps0 = 23 + (26 + (21.448 - T * 46.815) / 60) / 60
                let eps = (eps0 + 0.00256 * cos(omega)) * deg
                let decl = asin(sin(eps) * sin(lambda))
                let y = pow(tan(eps / 2), 2)
                let L0r = L0 * deg
                let eqTime = 4 / deg * (y * sin(2 * L0r) - 2 * e * sin(M) + 4 * e * y * sin(M) * cos(2 * L0r)
                    - 0.5 * y * y * sin(4 * L0r) - 1.25 * e * e * sin(2 * M)) // minutes
                let lat = latitude * deg
                let cosH = (cos(90.833 * deg) - sin(lat) * sin(decl)) / (cos(lat) * cos(decl))
                guard cosH >= -1, cosH <= 1 else { return nil }
                let H = acos(cosH) / deg
                let minutesUTC = 720 - 4 * (longitude + (rising ? H : -H)) - eqTime
                guard let midnight = utcCal.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day)) else { return nil }
                t = midnight.addingTimeInterval(minutesUTC * 60)
            }
            return t
        }
        guard let r = event(rising: true), let s = event(rising: false) else { return nil }
        return (r, s)
    }
}
