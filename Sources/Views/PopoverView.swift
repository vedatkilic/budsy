import SwiftUI

/// Root of the settings window. Shows the connect wizard until a device is
/// connected, then the sidebar dashboard. (The menu-bar panel handles the
/// compact quick view separately.)
struct PopoverView: View {
    @Bindable var bluetooth: BluetoothManager
    @Bindable var navigation: DetailNavigation

    var body: some View {
        ZStack {
            if bluetooth.isConnected {
                DashboardView(bluetooth: bluetooth, navigation: navigation)
                    .transition(.opacity)
            } else {
                ZStack {
                    VisualEffectBackground(material: .underWindowBackground)
                    WizardView(bluetooth: bluetooth) {}
                        .glassCard(cornerRadius: 22, padding: 0)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.glass, value: bluetooth.isConnected)
        .focusEffectDisabled() // no focus ring on auto-focused default buttons
    }
}
