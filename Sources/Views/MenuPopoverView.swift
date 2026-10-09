import AppKit
import SwiftUI

/// The menu-bar panel — "Liquid Glass": clear glass, battery pills that fill
/// like liquid, a stretching mode bar, a fill slider for ANC strength and round
/// quick toggles. Detailed controls live in the settings window.
struct MenuPopoverView: View {
    @Bindable var bluetooth: BluetoothManager
    let openDetail: (DashboardSection) -> Void

    private var status: BudsStatus { bluetooth.status }
    private var model: BudsModel? { bluetooth.connectedModel }
    private var deviceName: String {
        bluetooth.connectedName ?? model?.rawValue ?? "Galaxy Buds"
    }

    var body: some View {
        VStack(spacing: 14) {
            if bluetooth.isConnected {
                connected
            } else if bluetooth.handedOffToPhone {
                handedOff
            } else {
                disconnected
            }
            footer
        }
        .padding(14)
        .frame(width: 300)
        .liquidSurface(cornerRadius: 30)
        .animation(.glass, value: bluetooth.isConnected)
        .focusEffectDisabled() // no focus ring on the auto-focused default button
    }

    // MARK: - Connected

    private var connected: some View {
        VStack(spacing: 14) {
            header
            batteries
            if model?.supportsANC == true {
                LiquidModeBar(
                    modes: model?.listenModes ?? [],
                    selection: status.noiseControlMode
                ) { bluetooth.setNoiseControl($0) }
                strength
            }
            quickActions
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private var header: some View {
        HStack(spacing: 12) {
            BudsArt(size: 44)
                .frame(width: 58, height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: deviceName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(Color.batteryGreen).frame(width: 6, height: 6)
                        .shadow(color: Color.batteryGreen, radius: 4)
                    Text("Connected").font(.system(size: 12)).foregroundStyle(.white.opacity(0.62))
                }
            }
            Spacer(minLength: 0)
            LiquidIconButton(icon: "ellipsis", help: "Settings…", size: 30) { openDetail(.overview) }
        }
    }

    /// Left, right and — when the model reports it — the case. The case only
    /// reports while the buds sit in it, so it reads "—" the rest of the time.
    private var batteries: some View {
        HStack(spacing: 6) {
            BatteryPill(label: "L", level: status.batteryLeft,
                        present: status.batteryLeft > 0, charging: status.isLeftCharging)
            BatteryPill(label: "R", level: status.batteryRight,
                        present: status.batteryRight > 0, charging: status.isRightCharging)
            if model?.supportsCaseBattery == true {
                BatteryPill(label: "Case", level: status.batteryCase,
                            present: status.batteryCase > 0)
            }
        }
    }

    /// Strength only means anything while ANC is the active mode, so it's
    /// dimmed — not hidden — to keep the panel from resizing under the pointer.
    private var strength: some View {
        let ancActive = status.noiseControlMode == .anc
        let count = model?.ancLevelCount ?? 2
        let level = max(0, min(count - 1, status.ancLevel))
        return VStack(spacing: 8) {
            HStack {
                Text("Noise cancelling strength")
                Spacer()
                Text(verbatim: "\(level + 1) / \(count)").monospacedDigit()
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.62))
            .padding(.horizontal, 4)

            LiquidStrengthSlider(level: status.ancLevel, count: count) {
                bluetooth.setAncLevel($0)
            }
        }
        .disabled(!ancActive)
        .opacity(ancActive ? 1 : 0.35)
        .animation(.glass, value: ancActive)
    }

    private var quickActions: some View {
        let presets: [EqualizerPreset] = model?.supportsCustomEqualizer == true
            ? EqualizerPreset.allCases
            : EqualizerPreset.allCases.filter { $0 != .custom }
        let current = status.equalizerPreset
        return HStack(spacing: 6) {
            if model?.supportsDetectConversations == true {
                let on = status.detectConversations
                LiquidRoundButton(icon: "bubble.left.and.text.bubble.right",
                                  title: Text("Conversation"), active: on) {
                    bluetooth.setDetectConversations(!on)
                }
                .help(Text(on ? "Auto switch to ambient sound: On" : "Auto switch to ambient sound: Off"))
            }
            // Click cycles through the presets; right-click lists them all.
            LiquidRoundButton(icon: "slider.vertical.3",
                              title: Text(LocalizedStringKey(current.displayName))) {
                let index = presets.firstIndex(of: current) ?? -1
                bluetooth.setEqualizer(presets[(index + 1) % presets.count])
            }
            .contextMenu {
                ForEach(presets) { preset in
                    Button { bluetooth.setEqualizer(preset) } label: {
                        Text(LocalizedStringKey(preset.displayName))
                    }
                }
            }
            .help("Equalizer — click for the next preset, right-click to choose")
            LiquidRoundButton(icon: "bell.badge", title: Text("Find")) {
                openDetail(.findEarbuds)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            HStack(spacing: 6) {
                if bluetooth.isConnected {
                    Button { openDetail(.overview) } label: {
                        Text("Galaxy Buds Settings…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.pressable)
                }
                Spacer()
                if bluetooth.isConnected && !bluetooth.handedOffToPhone {
                    LiquidIconButton(icon: "iphone", help: "Send audio to phone") {
                        bluetooth.handOffToPhone()
                    }
                }
                LiquidIconButton(icon: "power", help: "Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Other states

    /// Shown while the buds are intentionally handed off to the phone.
    private var handedOff: some View {
        VStack(spacing: 14) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.variableColor.iterative, options: .repeating)
            VStack(spacing: 3) {
                Text(verbatim: deviceName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Audio on phone").font(.system(size: 12)).foregroundStyle(.white.opacity(0.62))
            }
            primaryButton(title: "Connect on Mac", icon: "laptopcomputer") {
                bluetooth.reclaimFromPhone()
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }

    private var disconnected: some View {
        VStack(spacing: 12) {
            BudsArt(size: 64).opacity(0.6)
            VStack(spacing: 3) {
                Text("No Buds Connected")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Connect your Galaxy Buds to get started.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
            }
            primaryButton(title: "Connect", icon: nil) { openDetail(.overview) }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }

    private func primaryButton(title: LocalizedStringKey, icon: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(Capsule().fill(Color.accentColor.gradient))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
            .shadow(color: Color.accentColor.opacity(0.4), radius: 8, y: 4)
        }
        .buttonStyle(.pressable)
    }
}
