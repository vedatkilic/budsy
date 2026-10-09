import SwiftUI

/// A battery ring in the style of the macOS Batteries widget.
///
/// `.compact` puts an earbud/case glyph inside the ring with the percentage and
/// label below it (menu-bar panel). `.large` puts the percentage inside the ring
/// with the label below (settings window).
struct CircularBatteryGauge: View {
    enum Style { case compact, large }
    enum Kind { case bud, budsCase }

    let level: Int
    let label: LocalizedStringKey
    var present: Bool = true
    var charging: Bool = false
    var diameter: CGFloat = 60
    var kind: Kind = .bud
    var style: Style = .compact

    private var fraction: CGFloat { present ? CGFloat(max(0, min(100, level))) / 100 : 0 }
    private var lineWidth: CGFloat { max(4, diameter * 0.09) }

    private var color: Color {
        guard present else { return .secondary.opacity(0.4) }
        switch level {
        case 0..<15: return .red
        case 15..<30: return .orange
        default: return .batteryGreen
        }
    }

    private var percentText: String { present ? "\(level)%" : "—" }

    var body: some View {
        VStack(spacing: style == .compact ? 5 : 9) {
            ZStack {
                Circle()
                    .stroke(Color.glassTrack, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.35), radius: 4)

                switch style {
                case .compact:
                    Image(systemName: kind == .bud ? "earbuds" : "earbuds.case")
                        .font(.system(size: diameter * 0.32, weight: .medium))
                        .foregroundStyle(.secondary)
                case .large:
                    Text(percentText)
                        .font(.system(size: diameter * 0.23, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, lineWidth)
                }
            }
            .frame(width: diameter, height: diameter)
            .overlay(alignment: .bottomTrailing) {
                if present && charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: diameter * 0.16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: diameter * 0.34, height: diameter * 0.34)
                        .background(Circle().fill(Color.batteryGreen))
                        .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                        .offset(x: 2, y: 2)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            VStack(spacing: 1) {
                if style == .compact {
                    Text(percentText)
                        .font(.system(size: max(11, diameter * 0.26), weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Text(label)
                    .font(.system(size: style == .compact ? 10 : 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.easeOut(duration: 0.8), value: fraction)
        .animation(.glass, value: charging)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(verbatim: percentText))
    }
}
