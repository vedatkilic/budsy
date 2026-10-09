import SwiftUI

/// ANC strength as a row of rising level bars — tap a bar to set that level.
/// Buds3/4 Pro expose five steps; older models two, and the same control
/// covers both.
struct AncStrengthStepper: View {
    let level: Int
    let count: Int
    var tint: Color = .accentColor
    var height: CGFloat = 26
    let onChange: (Int) -> Void

    private var clamped: Int { max(0, min(count - 1, level)) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(0..<count, id: \.self) { step in
                Button { onChange(step) } label: {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(step <= clamped ? tint : Color.glassTrack)
                        .frame(height: barHeight(step))
                        .frame(maxWidth: .infinity, maxHeight: height, alignment: .bottom)
                }
                .buttonStyle(.pressable)
            }
        }
        .frame(height: height)
        .animation(.glass, value: clamped)
        // One adjustable element rather than a row of unlabelled bars, which
        // VoiceOver would otherwise read as anonymous buttons.
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

    private func barHeight(_ step: Int) -> CGFloat {
        guard count > 1 else { return height }
        let minH = height * 0.38
        return minH + (height - minH) * CGFloat(step) / CGFloat(count - 1)
    }
}
