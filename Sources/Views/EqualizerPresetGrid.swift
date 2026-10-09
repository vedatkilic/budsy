import SwiftUI

/// Grid of equalizer preset chips. Shared by the panel and the window.
struct EqualizerPresetGrid: View {
    let presets: [EqualizerPreset]
    let selection: EqualizerPreset
    var columns: Int = 3
    var compact: Bool = true
    let onSelect: (EqualizerPreset) -> Void

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: compact ? 6 : 10), count: columns),
            spacing: compact ? 6 : 10
        ) {
            ForEach(presets) { preset in
                chip(preset)
            }
        }
        .animation(.glass, value: selection)
    }

    private func chip(_ preset: EqualizerPreset) -> some View {
        let selected = preset == selection
        return Button { onSelect(preset) } label: {
            Group {
                if compact {
                    Text(LocalizedStringKey(preset.displayName))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: preset.iconName)
                            .font(.system(size: 14, weight: .semibold))
                        Text(LocalizedStringKey(preset.displayName))
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: compact ? 8 : 16, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.glassTrack))
                    .shadow(color: selected ? Color.accentColor.opacity(0.35) : .clear, radius: 6, y: 3)
            )
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
