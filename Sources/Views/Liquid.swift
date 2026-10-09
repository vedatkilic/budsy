import SwiftUI

// Building blocks for the "Liquid Glass" menu-bar panel and connect card.

// MARK: - Surface

/// The bevel, tint and specular sheen drawn over the panel's glass. The blur
/// itself is the window's content view (see `StatusBarController`).
struct LiquidSurface: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(shape.fill(Color.black.opacity(0.08)))
            .overlay(alignment: .top) {
                LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 110)
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.32), Color.white.opacity(0.08)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            )
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func liquidSurface(cornerRadius: CGFloat) -> some View {
        modifier(LiquidSurface(cornerRadius: cornerRadius))
    }
}

// MARK: - Earbuds illustration

/// A pair of earbuds drawn with shapes, so it stays crisp at any size.
struct BudsArt: View {
    var size: CGFloat = 46

    var body: some View {
        HStack(spacing: -2) {
            bud
            bud.scaleEffect(x: -1, y: 1)
        }
        .frame(width: 48, height: 40)
        .scaleEffect(size / 48)
        .frame(width: size, height: size * 40 / 48)
    }

    private var shell: LinearGradient {
        LinearGradient(colors: [.white, Color(white: 0.74)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var bud: some View {
        ZStack(alignment: .topLeading) {
            Capsule().fill(shell)
                .frame(width: 6, height: 21)
                .offset(x: 13, y: 16)
            Ellipse().fill(shell)
                .frame(width: 20, height: 18)
                .offset(x: 3, y: 4)
            Circle().fill(Color(white: 0.17))
                .frame(width: 7, height: 7)
                .offset(x: 6, y: 9.5)
        }
        .frame(width: 25, height: 40, alignment: .topLeading)
        .rotationEffect(.degrees(-10))
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

// MARK: - Battery pill

/// A capsule that fills like liquid to the battery level.
struct BatteryPill: View {
    let label: LocalizedStringKey
    let level: Int
    var present: Bool = true
    var charging: Bool = false
    var height: CGFloat = 38

    private var fraction: CGFloat { present ? CGFloat(max(0, min(100, level))) / 100 : 0 }

    private var fill: Color {
        switch level {
        case 0..<15: return Color.red.opacity(0.6)
        case 15..<30: return Color.orange.opacity(0.55)
        default: return Color.batteryGreen.opacity(0.5)
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.08))
            GeometryReader { geo in
                Capsule()
                    .fill(fill)
                    .frame(width: max(fraction > 0 ? height : 0, geo.size.width * fraction))
            }
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 2)
                if present && charging {
                    Image(systemName: "bolt.fill").font(.system(size: 8, weight: .bold))
                }
                Text(verbatim: present ? "\(level)%" : "—")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
        }
        .frame(height: height)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .animation(.spring(response: 0.7, dampingFraction: 0.8), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(verbatim: present ? "\(level)%" : "—"))
    }
}

// MARK: - Mode bar

/// Icon-only capsule segments; the chosen one stretches open to show its name.
struct LiquidModeBar: View {
    let modes: [NoiseControlMode]
    let selection: NoiseControlMode
    let onSelect: (NoiseControlMode) -> Void

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(modes) { mode in
                segment(mode)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.black.opacity(0.24)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: selection)
    }

    private func segment(_ mode: NoiseControlMode) -> some View {
        let selected = mode == selection
        return Button { onSelect(mode) } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolEffect(.bounce, value: selected)
                if selected {
                    Text(LocalizedStringKey(mode.shortName))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.62))
            .frame(maxWidth: selected ? .infinity : 44)
            .frame(height: 38)
            .background {
                if selected {
                    Capsule()
                        .fill(Color.accentColor.gradient)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
                        .shadow(color: Color.accentColor.opacity(0.45), radius: 9, y: 4)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .help(Text(LocalizedStringKey(mode.displayName)))
        .accessibilityLabel(Text(LocalizedStringKey(mode.displayName)))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Strength slider

/// A stepped fill slider: click or drag along the track to pick a level.
struct LiquidStrengthSlider: View {
    let level: Int
    let count: Int
    let onChange: (Int) -> Void

    private var clamped: Int { max(0, min(count - 1, level)) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = CGFloat(clamped + 1) / CGFloat(max(1, count))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.24))
                HStack(spacing: 0) {
                    ForEach(1..<max(1, count), id: \.self) { _ in
                        Spacer()
                        Circle().fill(Color.white.opacity(0.25)).frame(width: 3, height: 3)
                    }
                    Spacer()
                }
                Capsule()
                    .fill(LinearGradient(colors: [.white, Color(white: 0.88)], startPoint: .top, endPoint: .bottom))
                    .frame(width: max(26, width * fraction))
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let step = Int((value.location.x / max(1, width)) * CGFloat(count))
                        let next = max(0, min(count - 1, step))
                        if next != clamped { onChange(next) }
                    }
            )
        }
        .frame(height: 26)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: clamped)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("ANC strength"))
        .accessibilityValue(Text(verbatim: "\(clamped + 1)/\(count)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if clamped < count - 1 { onChange(clamped + 1) }
            case .decrement: if clamped > 0 { onChange(clamped - 1) }
            @unknown default: break
            }
        }
    }
}

// MARK: - Round button

/// A round glass button with a caption, like Control Center's toggles.
struct LiquidRoundButton: View {
    let icon: String
    let title: Text
    var active: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(active ? Color.accentColor : Color.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(active ? Color.white.opacity(0.94) : Color.white.opacity(0.10)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    .shadow(color: active ? Color.white.opacity(0.25) : .clear, radius: 8)
                title
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.9))
        .animation(.glass, value: active)
    }
}

/// Small round icon button used in the panel footer and header.
struct LiquidIconButton: View {
    let icon: String
    let help: LocalizedStringKey
    var size: CGFloat = 28
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.pressable)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}
