import SwiftUI

/// The dashboard shown in the menu-bar panel behind "Settings…". Everything
/// sits straight on the panel's glass, the way the system's own menu-bar
/// panels do: the device and its batteries, a titled Listening Mode section
/// with the pill picker, the two noise settings as rows, the sub-pages as
/// rows with a coloured glyph, and the app-level actions at the bottom —
/// sections separated by hairlines, nothing boxed. The panel is exactly as
/// tall as this content.
struct DashboardView: View {
    @Bindable var bluetooth: BluetoothManager
    @State private var showSoundAnc = false
    @State private var showEarbudControls = false
    @State private var showEqualizer = false
    @State private var showFindMyEarbuds = false
    @State private var showAbout = false
    @State private var showFirmware = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var menuBarDisplay = MenuBarPreferences.display
    @State private var hidesWhenDisconnected = MenuBarPreferences.hidesWhenDisconnected

    private var status: BudsStatus { bluetooth.status }
    private var tint: Color { .accentColor }
    private var supportsAnc: Bool { bluetooth.connectedModel?.supportsANC == true }

    var body: some View {
        if showSoundAnc {
            SoundAncView(bluetooth: bluetooth) { showSoundAnc = false }
        } else if showEarbudControls {
            EarbudControlsView(bluetooth: bluetooth) { showEarbudControls = false }
        } else if showEqualizer {
            EqualizerView(bluetooth: bluetooth) { showEqualizer = false }
        } else if showFindMyEarbuds {
            FindMyEarbudsView(bluetooth: bluetooth) { showFindMyEarbuds = false }
        } else if showAbout {
            AboutView(bluetooth: bluetooth) { showAbout = false }
        } else if showFirmware {
            #if APPSTORE
            EmptyView()
            #else
            FirmwareUpdateView(bluetooth: bluetooth) { showFirmware = false }
            #endif
        } else {
            VStack(alignment: .leading, spacing: 0) {
                header
                if supportsAnc {
                    sectionDivider
                    listeningSection
                    noiseRows
                }
                sectionDivider
                pageRows
                sectionDivider
                appRows
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .frame(width: DetailLayout.width)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "airpodspro")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: bluetooth.connectedName
                     ?? bluetooth.connectedModel?.rawValue ?? "Galaxy Buds")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                BatteryGlyphLine(
                    status: status,
                    showsCase: bluetooth.connectedModel?.supportsCaseBattery == true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    // MARK: - Listening mode

    private var listeningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Listening Mode")
            ListenModePicker(
                modes: bluetooth.connectedModel?.listenModes ?? [],
                selection: status.noiseControlMode,
                tint: tint
            ) { bluetooth.setNoiseControl($0) }
            .padding(.horizontal, 10)
        }
        .padding(.bottom, 8)
    }

    /// ANC strength and conversation detection as plain rows, each gated per
    /// model. Strength is dimmed unless ANC is the active mode — it has no
    /// effect in ambient, off or adaptive.
    @ViewBuilder
    private var noiseRows: some View {
        if bluetooth.connectedModel?.supportsAncStrength == true {
            let active = status.noiseControlMode == .anc
            row("ANC strength") {
                AncStrengthStepper(
                    level: status.ancLevel,
                    count: bluetooth.connectedModel?.ancLevelCount ?? 2,
                    tint: tint
                ) { bluetooth.setAncLevel($0) }
                .frame(width: 200)
            }
            .disabled(!active)
            .opacity(active ? 1 : 0.45)
        }
        if bluetooth.connectedModel?.supportsDetectConversations == true {
            row("Auto switch to ambient sound", subtitle: "During conversations") {
                Toggle("", isOn: Binding(
                    get: { status.detectConversations },
                    set: { bluetooth.setDetectConversations($0) }
                ))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
        }
    }

    // MARK: - Pages

    /// One row per sub-page. Models without the custom equalizer page pick a
    /// preset from the row's menu instead.
    @ViewBuilder
    private var pageRows: some View {
        if supportsAnc {
            pageRow("Sound & ANC", icon: "ear.badge.waveform", color: .blue) { showSoundAnc = true }
            pageRow("Earbud controls", icon: "hand.tap.fill", color: .gray) { showEarbudControls = true }
        }
        if bluetooth.connectedModel?.supportsCustomEqualizer == true {
            pageRow("Equalizer", icon: "slider.vertical.3", color: .orange) { showEqualizer = true }
        } else {
            row("Equalizer", icon: "slider.horizontal.3", color: .orange) {
                Menu {
                    ForEach(EqualizerPreset.allCases.filter { $0 != .custom }) { preset in
                        Button { bluetooth.setEqualizer(preset) } label: {
                            Text(LocalizedStringKey(preset.displayName))
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(LocalizedStringKey(status.equalizerPreset.displayName))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
        }
        pageRow("Find earbuds", icon: "bell.badge.fill", color: .green) { showFindMyEarbuds = true }
        // Firmware comes from a community archive of Samsung's builds, which
        // the App Store build leaves out; the direct download keeps it.
        #if !APPSTORE
        pageRow("Firmware", icon: "arrow.down.circle.fill", color: .indigo) { showFirmware = true }
        #endif
        pageRow("About", icon: "info", color: .gray) { showAbout = true }
    }

    // MARK: - App

    @ViewBuilder
    private var appRows: some View {
        row("Menu bar shows", icon: "menubar.rectangle", color: .gray) {
            Menu {
                ForEach(MenuBarDisplay.allCases) { option in
                    Button {
                        menuBarDisplay = option
                        MenuBarPreferences.display = option
                    } label: {
                        Text(LocalizedStringKey(option.title))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(menuBarDisplay.title))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        row("Hide icon while disconnected", icon: "eye.slash", color: .gray) {
            Toggle("", isOn: Binding(
                get: { hidesWhenDisconnected },
                set: { hidesWhenDisconnected = $0; MenuBarPreferences.hidesWhenDisconnected = $0 }
            ))
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        row("Launch at login", icon: "power", color: .gray) {
            Toggle("", isOn: Binding(
                get: { launchAtLogin },
                set: { launchAtLogin = $0; LaunchAtLogin.set($0) }
            ))
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        Button { bluetooth.disconnect() } label: {
            HStack(spacing: 10) {
                glyph("xmark", color: .gray)
                Text("Disconnect").font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
        }
        .buttonStyle(GlassRowButtonStyle())
    }

    // MARK: - Building blocks

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 2)
    }

    private var sectionDivider: some View {
        Divider().padding(.horizontal, 4).padding(.vertical, 7)
    }

    private func row<Trailing: View>(
        _ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil,
        icon: String? = nil, color: Color = .gray,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            if let icon { glyph(icon, color: color) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
    }

    private func pageRow(
        _ title: LocalizedStringKey, icon: String, color: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            row(title, icon: icon, color: color) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(GlassRowButtonStyle())
    }

    /// The coloured disc the system's Bluetooth panel puts before a device.
    private func glyph(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(color))
    }
}
