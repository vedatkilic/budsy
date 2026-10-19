import AppKit
import SwiftUI

/// The panel shown from the menu-bar icon, in the shape of Control Center's
/// Sound panel when AirPods are connected: the device with its battery line,
/// then titled sections of menu-style rows with a checkmark on the current
/// choice, and the "Settings…" row at the bottom that swaps the panel to the
/// full dashboard.
struct MenuPopoverView: View {
    @Bindable var bluetooth: BluetoothManager
    let openDetail: () -> Void

    private var tint: Color { .accentColor }
    private var status: BudsStatus { bluetooth.status }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if bluetooth.isConnected {
                connected
            } else if bluetooth.isReclaiming {
                reclaiming
            } else if bluetooth.handedOffToPhone {
                elsewhere(icon: "iphone.radiowaves.left.and.right", subtitle: "Audio on phone")
            } else if bluetooth.yieldedToOtherDevice {
                elsewhere(icon: "arrow.left.arrow.right", subtitle: "Switched to another device")
            } else {
                disconnected
            }
            footer
        }
        .padding(.vertical, 8)
        .frame(width: 320)
        .modifier(PanelChrome())
        .focusEffectDisabled() // no focus ring on the auto-focused default button
    }

    // MARK: - Connected

    @ViewBuilder
    private var connected: some View {
        let model = bluetooth.connectedModel
        HStack(spacing: 10) {
            Image(systemName: "airpodspro")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: bluetooth.connectedName ?? model?.rawValue ?? "Galaxy Buds")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                BatteryGlyphLine(status: status, showsCase: model?.supportsCaseBattery == true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)

        if model?.supportsANC == true {
            sectionDivider
            sectionTitle("Listening Mode")
            ForEach(model?.listenModes ?? []) { mode in
                MenuRow(
                    title: LocalizedStringKey(mode.displayName), icon: mode.iconName,
                    checked: status.noiseControlMode == mode
                ) { bluetooth.setNoiseControl(mode) }
            }
            if model?.supportsAncStrength == true {
                let active = status.noiseControlMode == .anc
                HStack(spacing: 10) {
                    Text("ANC strength").font(.system(size: 13))
                    Spacer()
                    AncStrengthStepper(
                        level: status.ancLevel, count: model?.ancLevelCount ?? 2, tint: tint
                    ) { bluetooth.setAncLevel($0) }
                    .frame(width: 150)
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 2)
                .disabled(!active)
                .opacity(active ? 1 : 0.4)
            }
        }

        if model?.supportsDetectConversations == true {
            sectionDivider
            sectionTitle("Auto switch to ambient sound")
            MenuRow(title: "Off", icon: "person.wave.2", checked: !status.detectConversations) {
                bluetooth.setDetectConversations(false)
            }
            MenuRow(title: "On", icon: "person.wave.2.fill", checked: status.detectConversations) {
                bluetooth.setDetectConversations(true)
            }
        }

        sectionDivider
        equalizerRow
    }

    private var equalizerRow: some View {
        // Models with the full custom EQ UI expose the .custom preset here; older
        // models only see the fixed presets (Normal/Bass Boost/…/Treble Boost).
        let supportsCustom = bluetooth.connectedModel?.supportsCustomEqualizer == true
        let presets: [EqualizerPreset] = supportsCustom
            ? EqualizerPreset.allCases
            : EqualizerPreset.allCases.filter { $0 != .custom }
        return HStack(spacing: 8) {
            Text("Equalizer").font(.system(size: 13))
            Spacer()
            Menu {
                ForEach(presets) { preset in
                    Button { bluetooth.setEqualizer(preset) } label: {
                        Text(LocalizedStringKey(preset.displayName))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(status.equalizerPreset.displayName))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10))
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        sectionDivider
        if bluetooth.isConnected {
            MenuRow(title: "Settings…", icon: "gearshape", checked: nil, action: openDetail)
            if !bluetooth.handedOffToPhone {
                MenuRow(title: "To phone", icon: "iphone", checked: nil) { bluetooth.handOffToPhone() }
                    .help("Send audio to phone")
            }
        }
        MenuRow(title: "Quit", icon: "power", checked: nil) { NSApplication.shared.terminate(nil) }
    }

    // MARK: - Other states

    /// Shown while the buds are with another host, either handed off to the
    /// phone on purpose or switched away by the buds themselves: audio +
    /// control are both down, and auto-reconnect is suppressed.
    private func elsewhere(icon: String, subtitle: LocalizedStringKey) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(tint)
            VStack(spacing: 3) {
                Text(verbatim: bluetooth.connectedName
                     ?? bluetooth.connectedModel?.rawValue ?? "Galaxy Buds")
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                bluetooth.reclaimFromPhone()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "laptopcomputer")
                    Text("Connect on Mac")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    /// Shown after "Connect on Mac" while the buds come back, in place of the
    /// disconnected screen the panel would otherwise fall to meanwhile.
    private var reclaiming: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Connecting to \(bluetooth.connectedName ?? bluetooth.connectedModel?.rawValue ?? "Galaxy Buds")...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 24)
    }

    private var disconnected: some View {
        VStack(spacing: 12) {
            Image(systemName: "airpodspro")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Buds Connected").font(.headline)
            Text("Connect your Galaxy Buds to get started.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: openDetail) {
                Text("Connect").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Building blocks

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private var sectionDivider: some View {
        Divider().padding(.horizontal, 10).padding(.vertical, 5)
    }
}

/// A menu-item row with the hover highlight an NSMenu item gets. `checked`
/// is nil for plain actions, which drop the checkmark column so they line up
/// with the section titles; a Bool reserves the column and ticks it.
private struct MenuRow: View {
    let title: LocalizedStringKey
    let icon: String?
    let checked: Bool?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 14)
                        .opacity(checked ? 1 : 0)
                }
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .frame(width: 18)
                        .foregroundStyle(.secondary)
                }
                Text(title).font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(checked == true ? [.isButton, .isSelected] : .isButton)
    }
}
