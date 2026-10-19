import SwiftUI

/// "About" / diagnostics page: software version, serial numbers, and the earbud
/// fit (seal) test, as titled runs of rows straight on the panel's glass with
/// a hairline between them. Requests the info on appear.
struct AboutView: View {
    @Bindable var bluetooth: BluetoothManager
    let onBack: () -> Void

    @State private var fitTestActive = false
    @State private var diagnosticsCopied = false

    private var status: BudsStatus { bluetooth.status }
    private var tint: Color { .accentColor }
    private var supportsFitTest: Bool { bluetooth.connectedModel?.supportsAdaptiveANC == true }

    var body: some View {
        DetailPage(title: "About", onBack: {
            if fitTestActive { bluetooth.setFitTest(active: false) }
            onBack()
        }) {
            infoSection
            if supportsFitTest {
                GlassDivider()
                fitTestSection
            }
            GlassDivider()
            diagnosticsSection
        }
        .onAppear { bluetooth.requestAboutInfo() }
        .onDisappear { if fitTestActive { bluetooth.setFitTest(active: false) } }
    }

    private var infoSection: some View {
        GlassSection(title: "Device") {
            infoRow("Model", value: bluetooth.connectedModel?.rawValue ?? "Galaxy Buds")
            infoRow("Software version", value: status.softwareVersion.isEmpty ? "—" : status.softwareVersion)
            infoRow("Left serial", value: status.serialLeft.isEmpty ? "—" : status.serialLeft)
            infoRow("Right serial", value: status.serialRight.isEmpty ? "—" : status.serialRight)
        }
    }

    private var fitTestSection: some View {
        GlassSection(title: "Earbud fit test") {
            GlassFootnote(text: "Put both earbuds in and start the test to check the seal.")

            HStack(spacing: 24) {
                fitResult("Left", result: status.fitLeft)
                fitResult("Right", result: status.fitRight)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            GlassActionButton(
                title: fitTestActive ? "Stop" : "Check earbud fit",
                tint: tint, prominent: !fitTestActive,
                action: toggleFitTest
            )
        }
    }

    /// Puts the connection log on the clipboard so it can be pasted straight
    /// into a bug report — the app keeps no log files, and connection problems
    /// are otherwise undiagnosable on hardware we can't reproduce.
    private var diagnosticsSection: some View {
        GlassSection(title: "Diagnostics") {
            GlassFootnote(text: "Copies the connection log, so you can paste it into a bug report on GitHub.")
            GlassActionButton(
                title: diagnosticsCopied ? "Copied" : "Copy diagnostics",
                prominent: false,
                action: copyDiagnostics
            )
        }
    }

    private func copyDiagnostics() {
        let summary = """
            Device: \(bluetooth.connectedName ?? "—") \
            (\(bluetooth.connectedModel?.rawValue ?? "—"))
            Firmware: \(status.softwareVersion.isEmpty ? "—" : status.softwareVersion)
            Connected: \(bluetooth.isConnected)
            Multipoint: \(bluetooth.multipoint.lastResult)
            """
        let report = DiagnosticsLog.shared.export(deviceSummary: summary)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)

        diagnosticsCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            diagnosticsCopied = false
        }
    }

    private func fitResult(_ label: LocalizedStringKey, result: BudsStatus.FitResult) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon(result))
                .font(.system(size: 26))
                .foregroundStyle(color(result))
            Text(text(result))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color(result))
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func toggleFitTest() {
        fitTestActive.toggle()
        bluetooth.setFitTest(active: fitTestActive)
    }

    private func icon(_ r: BudsStatus.FitResult) -> String {
        switch r {
        case .good: "checkmark.circle.fill"
        case .bad: "exclamationmark.triangle.fill"
        case .failed: "xmark.circle.fill"
        case .unknown: "circle.dashed"
        }
    }

    private func color(_ r: BudsStatus.FitResult) -> Color {
        switch r {
        case .good: .green
        case .bad: .orange
        case .failed: .red
        case .unknown: .secondary
        }
    }

    private func text(_ r: BudsStatus.FitResult) -> LocalizedStringKey {
        switch r {
        case .good: "Good seal"
        case .bad: "Adjust fit"
        case .failed: "Test failed"
        case .unknown: "—"
        }
    }

    // MARK: - Building blocks

    /// A label/value row; the value is monospaced so serials line up and can
    /// be selected for a bug report.
    private func infoRow(_ title: LocalizedStringKey, value: String) -> some View {
        GlassRow(title: title) {
            Text(verbatim: value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
