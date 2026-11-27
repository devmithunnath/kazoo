import Foundation

public enum GaugeMath {
    /// Rounds a percentage to the integer the UI prints. Values are clamped to 0...100.
    /// A reported value that is above zero but rounds to zero is kept at 1 so "nearly empty" is not shown as empty.
    public static func displayPercent(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let clamped = min(100, max(0, value))
        let rounded = Int(clamped.rounded())
        if rounded == 0, clamped > 0 { return 1 }
        if rounded == 100, clamped < 100 { return 99 }
        return rounded
    }

    /// Lit squares for a printed percentage. Any nonzero percentage lights at least one square,
    /// and only 100% lights every square.
    public static func litSquares(percent: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        let p = min(100, max(0, percent))
        if p == 0 { return 0 }
        if p == 100 { return total }
        let lit = Int((Double(p) * Double(total) / 100).rounded())
        return min(total - 1, max(1, lit))
    }
}

public enum ResetFormatter {
    /// Compact countdown such as "48m", "2h 10m", "4d 6h". Returns nil when the time has passed.
    public static func countdown(to date: Date, now: Date = Date()) -> String? {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return nil }
        let minutes = Int((Double(seconds) / 60).rounded(.up))
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remMinutes = minutes % 60
        if hours < 24 { return remMinutes == 0 ? "\(hours)h" : "\(hours)h \(remMinutes)m" }
        let days = hours / 24
        let remHours = hours % 24
        return remHours == 0 ? "\(days)d" : "\(days)d \(remHours)h"
    }

    /// "Resets in 2h 10m", or a waiting message once the provider timestamp has passed.
    public static func resetLine(for meter: Meter, now: Date = Date()) -> String? {
        if let resetsAt = meter.resetsAt {
            if let text = countdown(to: resetsAt, now: now) { return "Resets in \(text)" }
            return "Reset due · confirming…"
        }
        return meter.resetDescription
    }

    public static func shortDate(_ date: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: date)
    }

    public static func monthName(_ date: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate("MMMM")
        return f.string(from: date)
    }

    /// "Updated 3m ago" style age for cached readings.
    public static func age(of date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}

public enum ValueFormatter {
    public static func money(_ amount: Double, currencyCode: String = "USD") -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.locale = Locale(identifier: currencyCode == "USD" ? "en_US" : Locale.current.identifier)
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }

    public static func count(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = value.rounded() == value ? 0 : 1
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// The big numeral for a meter: "31%", "$2.80", "184", or "—".
    public static func numeral(for meter: Meter) -> String {
        switch meter.value {
        case .remainingPercent:
            return "\(meter.gauge?.percent ?? 0)%"
        case let .money(amount, code):
            return money(amount, currencyCode: code)
        case let .count(used, _, _):
            return count(used)
        case .unavailable:
            return "—"
        }
    }

    /// Unit text after/under the numeral: "left", "AI credits used", etc.
    public static func unit(for meter: Meter) -> String {
        switch meter.value {
        case .remainingPercent: "left"
        case .money: ""
        case let .count(_, _, unit): unit
        case let .unavailable(reason): reason
        }
    }

    /// Collapsed-notch text: "31% weekly left", "$2.80 today", "184 credits".
    public static func compact(for meter: Meter) -> String {
        switch meter.value {
        case .remainingPercent:
            return "\(meter.gauge?.percent ?? 0)% \(meter.shortTitle) left"
        case let .money(amount, code):
            return "\(money(amount, currencyCode: code)) \(meter.shortTitle)"
        case let .count(used, _, _):
            return "\(count(used)) \(meter.shortTitle)"
        case .unavailable:
            return "—"
        }
    }
}
