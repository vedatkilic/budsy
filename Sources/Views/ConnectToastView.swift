import SwiftUI

/// The glass pill that drops in when the buds connect, AirPods-style: device,
/// "Connected" and battery. Dismisses itself after a few seconds; clicking it
/// opens the full panel.
struct ConnectToastView: View {
    @Bindable var bluetooth: BluetoothManager
    let onTap: () -> Void

    private var status: BudsStatus { bluetooth.status }
    private var model: BudsModel? { bluetooth.connectedModel }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                BudsArt(size: 36)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.white.opacity(0.08)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: bluetooth.connectedName ?? model?.rawValue ?? "Galaxy Buds")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("Connected")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 5) {
                    budsPills
                    if model?.supportsCaseBattery == true && status.batteryCase > 0 {
                        pill(icon: "earbuds.case", level: status.batteryCase, charging: false)
                    }
                }
                .fixedSize()
                .layoutPriority(1)
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(width: 340, height: 64)
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .liquidSurface(cornerRadius: 32)
        .focusEffectDisabled()
    }

    /// One pill when both buds read the same, otherwise one per side.
    @ViewBuilder
    private var budsPills: some View {
        let left = status.batteryLeft
        let right = status.batteryRight
        if left > 0 && right > 0 && abs(left - right) <= 2 {
            pill(icon: "earbuds", level: min(left, right),
                 charging: status.isLeftCharging || status.isRightCharging)
        } else {
            if left > 0 { pill(text: "L", level: left, charging: status.isLeftCharging) }
            if right > 0 { pill(text: "R", level: right, charging: status.isRightCharging) }
        }
    }

    private func pill(icon: String? = nil, text: String? = nil, level: Int, charging: Bool) -> some View {
        HStack(spacing: 3) {
            if charging {
                Image(systemName: "bolt.fill").font(.system(size: 8, weight: .bold))
            } else if let icon {
                Image(systemName: icon).font(.system(size: 9, weight: .semibold)).opacity(0.85)
            }
            if let text { Text(verbatim: text).font(.system(size: 11, weight: .medium)).opacity(0.75) }
            Text(verbatim: "\(level)%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(color(for: level)))
    }

    private func color(for level: Int) -> Color {
        switch level {
        case 0..<15: return Color.red.opacity(0.5)
        case 15..<30: return Color.orange.opacity(0.45)
        default: return Color.batteryGreen.opacity(0.4)
        }
    }
}
