import SwiftUI

/// The sections of the settings window's sidebar.
enum DashboardSection: String, CaseIterable, Identifiable, Hashable {
    case overview, soundAnc, equalizer, earbudControls, findEarbuds, firmware, about

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .soundAnc: "Sound & ANC"
        case .equalizer: "Equalizer"
        case .earbudControls: "Earbud controls"
        case .findEarbuds: "Find earbuds"
        case .firmware: "Firmware"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .overview: "earbuds"
        case .soundAnc: "ear.badge.waveform"
        case .equalizer: "slider.vertical.3"
        case .earbudControls: "hand.tap"
        case .findEarbuds: "bell.badge"
        case .firmware: "arrow.down.circle"
        case .about: "info.circle"
        }
    }

    /// System Settings–style coloured icon tile.
    var color: Color {
        switch self {
        case .overview: .blue
        case .soundAnc: .indigo
        case .equalizer: .pink
        case .earbudControls: .orange
        case .findEarbuds: .green
        case .firmware, .about: .gray
        }
    }
}

/// Which section the settings window shows. Owned by the status-bar
/// controller so the menu-bar panel can open the window straight to a page.
@MainActor
@Observable
final class DetailNavigation {
    var section: DashboardSection = .overview
}

/// The settings window when connected: a vibrant sidebar of sections next to a
/// glass content pane, in the manner of System Settings.
struct DashboardView: View {
    @Bindable var bluetooth: BluetoothManager
    @Bindable var navigation: DetailNavigation
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    private var status: BudsStatus { bluetooth.status }
    private var model: BudsModel? { bluetooth.connectedModel }
    private var supportsAnc: Bool { model?.supportsANC == true }
    private var deviceName: String { bluetooth.connectedName ?? model?.rawValue ?? "Galaxy Buds" }

    private var sections: [DashboardSection] {
        DashboardSection.allCases.filter { section in
            switch section {
            case .soundAnc, .earbudControls: supportsAnc
            default: true
            }
        }
    }

    private var current: DashboardSection {
        sections.contains(navigation.section) ? navigation.section : .overview
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 240)
                .background(VisualEffectBackground(material: .sidebar))
            Rectangle().fill(Color.glassEdge).frame(width: 0.5)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VisualEffectBackground(material: .underWindowBackground))
        }
        .ignoresSafeArea()
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Room for the window's traffic lights, which float over the sidebar.
            Color.clear.frame(height: 28)

            deviceCard

            VStack(spacing: 2) {
                ForEach(sections) { section in
                    sidebarRow(section)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { launchAtLogin },
                    set: { launchAtLogin = $0; LaunchAtLogin.set($0) }
                )) {
                    Text("Launch at login").font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Divider()

                Button { bluetooth.disconnect() } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.pressable)
            }
            .glassCard(cornerRadius: 14, padding: 10)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }

    private var deviceCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "earbuds")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: deviceName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(verbatim: batterySummary)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .glassCard(cornerRadius: 14, padding: 10)
    }

    private var batterySummary: String {
        func pct(_ v: Int) -> String { v > 0 ? "\(v)%" : "—" }
        var parts = ["L \(pct(status.batteryLeft))", "R \(pct(status.batteryRight))"]
        if model?.supportsCaseBattery == true && status.batteryCase > 0 {
            parts.append("\(String(localized: "Case")) \(pct(status.batteryCase))")
        }
        return parts.joined(separator: " · ")
    }

    private func sidebarRow(_ section: DashboardSection) -> some View {
        let selected = section == current
        return Button {
            withAnimation(.glass) { navigation.section = section }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(section.color.gradient))
                Text(section.title)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.glassSelection : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(current.title)
                .font(.system(size: 22, weight: .bold))
                .padding(.horizontal, 24)
                .padding(.top, 30)
                .padding(.bottom, 4)

            page
                .id(current)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 8)),
                    removal: .opacity))
        }
        .animation(.glass, value: current)
    }

    @ViewBuilder
    private var page: some View {
        switch current {
        case .overview:
            ScrollView { overview.padding(.horizontal, 24).padding(.vertical, 14) }
        case .soundAnc:
            SoundAncView(bluetooth: bluetooth, onBack: goHome, showsHeader: false)
        case .equalizer:
            if model?.supportsCustomEqualizer == true {
                EqualizerView(bluetooth: bluetooth, onBack: goHome, showsHeader: false)
            } else {
                ScrollView { presetPage.padding(.horizontal, 24).padding(.vertical, 14) }
            }
        case .earbudControls:
            EarbudControlsView(bluetooth: bluetooth, onBack: goHome, showsHeader: false)
        case .findEarbuds:
            FindMyEarbudsView(bluetooth: bluetooth, onBack: goHome, showsHeader: false)
        case .firmware:
            FirmwareUpdateView(bluetooth: bluetooth, onBack: goHome, showsHeader: false)
        case .about:
            AboutView(bluetooth: bluetooth, onBack: goHome, showsHeader: false)
        }
    }

    private func goHome() { navigation.section = .overview }

    // MARK: - Overview

    private var overview: some View {
        VStack(spacing: 16) {
            hero
            if supportsAnc { noiseCard }
            HStack(spacing: 16) {
                equalizerShortcut
                findShortcut
            }
        }
    }

    private var hero: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "earbuds")
                    .font(.system(size: 58, weight: .regular))
                    .foregroundStyle(Color.accentColor.gradient)
                    .symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: deviceName)
                        .font(.system(size: 19, weight: .bold))
                        .lineLimit(1)
                    if bluetooth.connectedName != nil, let raw = model?.rawValue {
                        Text(verbatim: raw).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(Color.batteryGreen).frame(width: 7, height: 7)
                        Text("Connected").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minWidth: 170, alignment: .leading)

            HStack(spacing: 0) {
                CircularBatteryGauge(
                    level: status.batteryLeft, label: "Left",
                    present: status.batteryLeft > 0, charging: status.isLeftCharging,
                    diameter: 84, style: .large)
                    .frame(maxWidth: .infinity)
                CircularBatteryGauge(
                    level: status.batteryRight, label: "Right",
                    present: status.batteryRight > 0, charging: status.isRightCharging,
                    diameter: 84, style: .large)
                    .frame(maxWidth: .infinity)
                if model?.supportsCaseBattery == true {
                    CircularBatteryGauge(
                        level: status.batteryCase, label: "Case",
                        present: status.batteryCase > 0,
                        diameter: 84, kind: .budsCase, style: .large)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .glassCard(cornerRadius: 22, padding: 22)
    }

    private var noiseCard: some View {
        let ancActive = status.noiseControlMode == .anc
        let count = model?.ancLevelCount ?? 2
        return VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Noise control").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(LocalizedStringKey(status.noiseControlMode.displayName))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            ListenModePicker(
                modes: model?.listenModes ?? [],
                selection: status.noiseControlMode,
                height: 62
            ) { bluetooth.setNoiseControl($0) }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ANC strength").font(.system(size: 13, weight: .medium))
                    Text(verbatim: "\(min(count, max(1, status.ancLevel + 1)))/\(count)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .frame(width: 140, alignment: .leading)
                AncStrengthStepper(level: status.ancLevel, count: count, height: 30) {
                    bluetooth.setAncLevel($0)
                }
            }
            .disabled(!ancActive)
            .opacity(ancActive ? 1 : 0.35)
            .animation(.glass, value: ancActive)

            if model?.supportsDetectConversations == true {
                Divider()
                Toggle(isOn: Binding(
                    get: { status.detectConversations },
                    set: { bluetooth.setDetectConversations($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto switch to ambient sound").font(.system(size: 13, weight: .medium))
                        Text("During conversations").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
            }
        }
        .glassCard(cornerRadius: 22, padding: 18)
    }

    private var equalizerShortcut: some View {
        Button { withAnimation(.glass) { navigation.section = .equalizer } } label: {
            VStack(alignment: .leading, spacing: 14) {
                shortcutTitle("Equalizer",
                              value: LocalizedStringKey(status.equalizerPreset.displayName))
                MiniEqualizerCurve(bands: displayBands)
                    .frame(height: 44)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 22, padding: 18)
        }
        .buttonStyle(.pressable)
    }

    private var findShortcut: some View {
        Button { withAnimation(.glass) { navigation.section = .findEarbuds } } label: {
            VStack(alignment: .leading, spacing: 14) {
                shortcutTitle("Find earbuds", value: "Open")
                HStack(spacing: 12) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.green.gradient))
                    Text("Ring your earbuds to locate them.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(height: 44)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 22, padding: 18)
        }
        .buttonStyle(.pressable)
    }

    private func shortcutTitle(_ title: LocalizedStringKey, value: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 2) {
                Text(value)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.accentColor)
        }
    }

    /// The curve the earbuds report for the active preset, or the user's own
    /// for Custom; flat until the device has reported.
    private var displayBands: [Int] {
        let bands: [Int]
        if status.equalizerPreset == .custom {
            bands = status.customEqualizerBands
        } else {
            let idx = status.equalizerPreset.rawValue
            bands = idx < status.presetEqualizerCurves.count ? status.presetEqualizerCurves[idx] : []
        }
        return (0..<9).map { bands.indices.contains($0) ? bands[$0] : 0 }
    }

    /// Preset picker for models without the per-band custom equalizer.
    private var presetPage: some View {
        EqualizerPresetGrid(
            presets: EqualizerPreset.allCases.filter { $0 != .custom },
            selection: status.equalizerPreset,
            columns: 3, compact: false
        ) { bluetooth.setEqualizer($0) }
        .glassCard(cornerRadius: 22, padding: 18)
    }
}

/// A tiny read-only graph of an equalizer curve: capsules rising above or
/// dropping below a centre line, so a flat curve reads as a calm row of dots.
struct MiniEqualizerCurve: View {
    let bands: [Int]

    var body: some View {
        let peak = CGFloat(max(6, bands.map { abs($0) }.max() ?? 6))
        GeometryReader { geo in
            let half = geo.size.height / 2
            ZStack {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: 1)
                HStack(spacing: 0) {
                    ForEach(Array(bands.enumerated()), id: \.offset) { _, value in
                        let length = 6 + (half - 3) * CGFloat(abs(value)) / peak
                        Capsule()
                            .fill(Color.accentColor.gradient)
                            .frame(width: 6, height: length)
                            .offset(y: value >= 0 ? -(length / 2 - 3) : (length / 2 - 3))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.glass, value: bands)
    }
}
