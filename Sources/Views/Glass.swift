import AppKit
import SwiftUI

// MARK: - Glass palette

/// Translucent fills that adapt to light and dark appearance. They sit on top
/// of a behind-window vibrancy view, so the desktop tints through every card
/// the way Control Center's modules do.
extension Color {
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    /// Fill for a card/module sitting on the glass.
    static let glassCard = dynamic(light: NSColor.white.withAlphaComponent(0.55),
                                   dark: NSColor.white.withAlphaComponent(0.07))
    /// Hairline edge around cards — catches the light like a glass bevel.
    static let glassEdge = dynamic(light: NSColor.white.withAlphaComponent(0.75),
                                   dark: NSColor.white.withAlphaComponent(0.10))
    /// Recessed track behind segmented controls, rings and level bars.
    static let glassTrack = dynamic(light: NSColor.black.withAlphaComponent(0.07),
                                    dark: NSColor.white.withAlphaComponent(0.10))
    /// The raised "thumb" of a segmented control.
    static let glassThumb = dynamic(light: NSColor.white,
                                    dark: NSColor.white.withAlphaComponent(0.22))
    /// Selected row in the window sidebar.
    static let glassSelection = dynamic(light: NSColor.black.withAlphaComponent(0.07),
                                        dark: NSColor.white.withAlphaComponent(0.12))
    /// Text/icon colour on the selected segment: accent in light, white in dark.
    static let glassOnThumb = dynamic(light: NSColor.controlAccentColor, dark: NSColor.white)

    static let batteryGreen = Color(red: 0.19, green: 0.82, blue: 0.35)
}

// MARK: - Vibrancy

/// A behind-window `NSVisualEffectView`. `cornerRadius` masks the blur itself,
/// which a SwiftUI `clipShape` can't do for a borderless panel.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.isEmphasized = true
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.maskImage = cornerRadius > 0 ? Self.mask(radius: cornerRadius) : nil
    }

    static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

// MARK: - Cards

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 18
    var padding: CGFloat? = 12

    func body(content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.glassCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.glassEdge, lineWidth: 0.5)
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18, padding: CGFloat? = 12) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

/// Small uppercase caption with an optional trailing value, used as the title
/// line of each glass module.
struct GlassSectionHeader: View {
    let title: LocalizedStringKey
    var value: LocalizedStringKey? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.4)
            Spacer()
            if let value {
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.opacity)
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Press feedback

/// A springy press: the control dips slightly while held and bounces back.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// The standard spring the whole UI moves with.
extension Animation {
    static let glass = Animation.spring(response: 0.42, dampingFraction: 0.78)
}
