import SwiftUI

/// "Resets in 2h 10m" with the countdown in green, or the provider's description.
struct ResetLine: View {
    let meter: Meter
    let now: Date
    var size: CGFloat = 17

    var body: some View {
        if let resetsAt = self.meter.resetsAt {
            if let countdown = ResetFormatter.countdown(to: resetsAt, now: self.now) {
                (Text("Resets in ").foregroundColor(KazooTheme.primaryText.opacity(0.85))
                    + Text(countdown).foregroundColor(KazooTheme.lime))
                    .font(.system(size: self.size))
                    .monospacedDigit()
            } else {
                Text("Reset due · confirming…")
                    .font(.system(size: self.size))
                    .foregroundStyle(KazooTheme.secondaryText)
            }
        } else if let description = self.meter.resetDescription {
            Text(description).font(.system(size: self.size)).foregroundStyle(KazooTheme.secondaryText)
        }
    }
}

enum MeterAccessibility {
    static func label(provider: ProviderID?, meter: Meter, now: Date) -> String {
        var parts: [String] = []
        if let provider { parts.append(provider.displayName) }
        parts.append(meter.title)
        switch meter.value {
        case .remainingPercent:
            parts.append("\(meter.gauge?.percent ?? 0) percent left")
        case let .money(amount, code):
            parts.append(ValueFormatter.money(amount, currencyCode: code))
        case let .count(used, limit, unit):
            parts.append("\(ValueFormatter.count(used)) \(unit)")
            if let limit { parts.append("of \(ValueFormatter.count(limit))") }
        case let .unavailable(reason):
            parts.append("unavailable, \(reason)")
        }
        if let resetsAt = meter.resetsAt, let countdown = ResetFormatter.countdown(to: resetsAt, now: now) {
            parts.append("resets in \(countdown.replacingOccurrences(of: "d", with: " days").replacingOccurrences(of: "h", with: " hours").replacingOccurrences(of: "m", with: " minutes"))")
        }
        return parts.joined(separator: ", ")
    }
}

/// A vertical column: title, big numeral, optional grid, reset line. Used in two/three-column detail layouts.
struct MeterColumn: View {
    let meter: Meter
    let now: Date
    var numeralSize: CGFloat = 60
    /// Shorter grid for dense layouts (four or more windows).
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: self.compact ? 8 : 10) {
            Text(self.meter.title)
                .font(.system(size: 18))
                .foregroundStyle(KazooTheme.primaryText.opacity(0.88))
                .lineLimit(1)
            NumeralText(meter: self.meter, size: self.numeralSize)
            if let gauge = self.meter.gauge {
                SquareGrid(gauge: gauge, columns: self.compact ? 10 : 7, rows: self.compact ? 3 : 6,
                           square: self.compact ? 13 : 17, spacing: self.compact ? 4 : 5)
                    .padding(.top, self.compact ? 2 : 4)
            }
            if let caption = self.meter.caption {
                Text(caption).font(.system(size: 15)).foregroundStyle(KazooTheme.secondaryText)
            }
            ResetLine(meter: self.meter, now: self.now)
                .padding(.top, 4)
        }
        .frame(minWidth: 190, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MeterAccessibility.label(provider: nil, meter: self.meter, now: self.now))
    }
}

/// "68% left" / "$3.80" / "184" in large condensed type.
struct NumeralText: View {
    let meter: Meter
    let size: CGFloat
    var showsUnitInline = true

    var body: some View {
        switch self.meter.value {
        case .remainingPercent:
            Text(self.showsUnitInline ? "\(ValueFormatter.numeral(for: self.meter)) left" : ValueFormatter.numeral(for: self.meter))
                .font(KazooTheme.numeral(self.size))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        case .unavailable:
            VStack(alignment: .leading, spacing: 2) {
                Text("—").font(KazooTheme.numeral(self.size)).foregroundStyle(KazooTheme.tertiaryText)
                Text(ValueFormatter.unit(for: self.meter)).font(.system(size: 13)).foregroundStyle(KazooTheme.tertiaryText)
            }
        default:
            Text(ValueFormatter.numeral(for: self.meter))
                .font(KazooTheme.numeral(self.size))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// Single-meter hero: huge numeral and unit on the left, grid on the right (Codex/Copilot references).
struct HeroMeter: View {
    let meter: Meter
    let now: Date

    var body: some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 4) {
                NumeralText(meter: self.meter, size: 112, showsUnitInline: false)
                Text(self.heroCaption)
                    .font(.system(size: 22))
                    .foregroundStyle(KazooTheme.secondaryText)
                if let caption = self.meter.caption {
                    Text(caption).font(.system(size: 14)).foregroundStyle(KazooTheme.tertiaryText)
                }
            }
            Spacer(minLength: 0)
            if let gauge = self.meter.gauge {
                SquareGrid(gauge: gauge, columns: 7, rows: 6, square: 20, spacing: 7)
            }
        }
        .frame(minWidth: 480)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MeterAccessibility.label(provider: nil, meter: self.meter, now: self.now))
    }

    private var heroCaption: String {
        switch self.meter.value {
        case .remainingPercent: "\(self.meter.title) remaining"
        case let .count(_, _, unit): unit
        case .money: self.meter.title
        case let .unavailable(reason): reason
        }
    }
}

/// Model-specific windows listed beneath the main pair, each with its own name and reset.
struct ModelMeterRow: View {
    let meter: Meter
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(self.meter.title)
                .font(.system(size: 15))
                .foregroundStyle(KazooTheme.primaryText.opacity(0.85))
            Spacer(minLength: 12)
            if let gauge = self.meter.gauge {
                SquareGrid(gauge: gauge, columns: 10, rows: 1, square: 9, spacing: 3)
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
            }
            NumeralText(meter: self.meter, size: 24)
            ResetLine(meter: self.meter, now: self.now, size: 13)
                .frame(minWidth: 110, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MeterAccessibility.label(provider: nil, meter: self.meter, now: self.now))
    }
}

/// Compact daily spend chart (OpenAI API).
struct SpendBars: View {
    let history: [DailySpend]

    var body: some View {
        let maxValue = max(self.history.map(\.amount).max() ?? 0, 0.01)
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(self.history) { day in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(KazooTheme.mint)
                    .frame(height: max(6, 70 * day.amount / maxValue))
                    .frame(maxWidth: .infinity)
                    .help("\(ResetFormatter.shortDate(day.day)): \(ValueFormatter.money(day.amount))")
            }
        }
        .frame(height: 74, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily spend, last \(self.history.count) days: "
            + self.history.map { "\(ResetFormatter.shortDate($0.day)) \(ValueFormatter.money($0.amount))" }.joined(separator: ", "))
    }
}

extension FooterStrip {
    func valueText(now: Date) -> String {
        switch self.value {
        case let .countdown(date): ResetFormatter.countdown(to: date, now: now) ?? "now"
        case let .date(date): ResetFormatter.shortDate(date)
        case let .month(date): ResetFormatter.monthName(date)
        case let .text(text): text
        }
    }
}
