import SwiftUI

public enum KazooTheme {
    /// Pure black so the panel merges with the camera housing.
    public static let panel = Color.black
    public static let mint = Color(red: 0.62, green: 0.96, blue: 0.55)
    public static let lime = Color(red: 0.66, green: 0.97, blue: 0.40)
    public static let dimSquare = Color(white: 0.22)
    public static let primaryText = Color.white
    public static let secondaryText = Color.white.opacity(0.62)
    public static let tertiaryText = Color.white.opacity(0.42)
    public static let divider = Color.white.opacity(0.16)
    public static let warning = Color(red: 1.0, green: 0.78, blue: 0.35)

    /// Large condensed numerals.
    public static func numeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium).width(.condensed)
    }

    public static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }
}

/// A grid of softly rounded squares communicating a fraction. Lit squares fill from the bottom row upward,
/// left to right. The lit count comes from the same rounded percentage the label prints.
public struct SquareGrid: View {
    public let gauge: GaugeValue
    public var columns: Int
    public var rows: Int
    public var square: CGFloat
    public var spacing: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(gauge: GaugeValue, columns: Int = 7, rows: Int = 6, square: CGFloat = 14, spacing: CGFloat = 4) {
        self.gauge = gauge
        self.columns = columns
        self.rows = rows
        self.square = square
        self.spacing = spacing
    }

    public var body: some View {
        let total = self.columns * self.rows
        let lit = self.gauge.litSquares(total: total)
        VStack(spacing: self.spacing) {
            ForEach(0..<self.rows, id: \.self) { row in
                HStack(spacing: self.spacing) {
                    ForEach(0..<self.columns, id: \.self) { column in
                        // Index counted from the bottom-left square.
                        let index = (self.rows - 1 - row) * self.columns + column
                        RoundedRectangle(cornerRadius: self.square * 0.28, style: .continuous)
                            .fill(index < lit ? KazooTheme.mint : KazooTheme.dimSquare)
                            .frame(width: self.square, height: self.square)
                    }
                }
            }
        }
        .animation(self.reduceMotion ? nil : .easeOut(duration: 0.35), value: lit)
        .accessibilityHidden(true)
    }
}

/// The stepped green strip: a lower band on the left rising to a taller tab on the right.
public struct SteppedStripShape: Shape {
    public var stepFraction: CGFloat = 0.72
    public var stepHeight: CGFloat = 10

    public func path(in rect: CGRect) -> Path {
        let r = rect.height / 2
        let lowTop = rect.minY + self.stepHeight
        let stepX = rect.minX + rect.width * self.stepFraction
        let curve: CGFloat = 26
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(-90), clockwise: true)
        p.addLine(to: CGPoint(x: stepX, y: rect.minY))
        p.addCurve(to: CGPoint(x: stepX - curve, y: lowTop),
                   control1: CGPoint(x: stepX - curve * 0.5, y: rect.minY),
                   control2: CGPoint(x: stepX - curve * 0.5, y: lowTop))
        let lowR = (rect.maxY - lowTop) / 2
        p.addLine(to: CGPoint(x: rect.minX + lowR, y: lowTop))
        p.addArc(center: CGPoint(x: rect.minX + lowR, y: lowTop + lowR), radius: lowR,
                 startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// Label on the lower band, value on the raised tab.
public struct SteppedStrip: View {
    public let label: String
    public let value: String
    public var action: (() -> Void)?

    public init(label: String, value: String, action: (() -> Void)? = nil) {
        self.label = label
        self.value = value
        self.action = action
    }

    public var body: some View {
        let content = ZStack {
            SteppedStripShape()
                .fill(KazooTheme.lime)
            HStack(alignment: .bottom) {
                Text(self.label)
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.bottom, 9)
                Spacer(minLength: 12)
                Text(self.value)
                    .font(.system(size: 19, weight: .bold))
                    .monospacedDigit()
                    .padding(.bottom, 14)
            }
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 20)
        }
        .frame(height: 50)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(self.label) \(self.value)")

        if let action {
            Button(action: action) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
}

/// Full-width rounded green action pill, e.g. "All 7 providers ›".
public struct GreenPill: View {
    public let title: String
    public let action: () -> Void

    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: self.action) {
            HStack {
                Text(self.title).font(.system(size: 18, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 22)
            .frame(height: 46)
            .background(Capsule().fill(KazooTheme.lime))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
