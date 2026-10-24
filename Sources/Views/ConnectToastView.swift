import SwiftUI

/// The small card that drops in under the menu-bar icon when the buds connect,
/// AirPods-style: the device, "Connected" and its battery line — the panel's
/// own header on its own. It dismisses itself after a few seconds; clicking it
/// opens the full panel.
struct ConnectToastView: View {
    @Bindable var bluetooth: BluetoothManager
    let onOpen: () -> Void

    private var status: BudsStatus { bluetooth.status }

    var body: some View {
        let model = bluetooth.connectedModel
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: "airpodspro")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.accentColor))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: bluetooth.connectedName ?? model?.rawValue ?? "Galaxy Buds")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text("Connected")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        BatteryGlyphLine(status: status, showsCase: model?.supportsCaseBattery == true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 300)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(PanelChrome())
        .focusEffectDisabled()
    }
}
