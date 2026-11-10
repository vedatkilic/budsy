import AppKit
import SwiftUI

/// Developer aid: `Budsy --preview <dir>` renders the panel views to PNGs
/// against a stand-in connected device and exits, without touching Bluetooth
/// or the screen. Lets layout changes be checked in both appearances from a
/// script instead of by screenshotting a live panel that closes on the first
/// stray click.
@MainActor
enum PreviewRenderer {
    /// Renders and returns true when the flag is present; false otherwise.
    static func renderIfRequested() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "--preview"), flag + 1 < args.count else { return false }
        let directory = URL(fileURLWithPath: args[flag + 1])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let bluetooth = BluetoothManager()
        bluetooth.enterDemoMode()

        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            render(MenuPopoverView(bluetooth: bluetooth) {},
                   name: "quick-\(suffix)", appearance: appearance, into: directory)
            render(DashboardView(bluetooth: bluetooth).modifier(PanelChrome()),
                   name: "dashboard-\(suffix)", appearance: appearance, into: directory)
            render(ConnectToastView(bluetooth: bluetooth) {},
                   name: "connect-card-\(suffix)", appearance: appearance, into: directory)
            let pages: [(String, AnyView)] = [
                ("sound-anc", AnyView(SoundAncView(bluetooth: bluetooth) {})),
                ("earbud-controls", AnyView(EarbudControlsView(bluetooth: bluetooth) {})),
                ("equalizer", AnyView(EqualizerView(bluetooth: bluetooth) {})),
                ("find", AnyView(FindMyEarbudsView(bluetooth: bluetooth) {})),
                ("about", AnyView(AboutView(bluetooth: bluetooth) {})),
                ("wizard", AnyView(WizardView(bluetooth: bluetooth) {})),
            ]
            for (name, page) in pages {
                render(page.modifier(PanelChrome()),
                       name: "\(name)-\(suffix)", appearance: appearance, into: directory)
            }
        }
        return true
    }

    /// Draws `view` at 2× into `<dir>/<name>.png` via an offscreen window, so
    /// AppKit-backed controls (toggles, sliders, menus) render too — which
    /// `ImageRenderer` alone would leave blank.
    private static func render<V: View>(
        _ view: V, name: String, appearance: NSAppearance.Name, into directory: URL
    ) {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: appearance)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let url = directory.appendingPathComponent("\(name).png")
        do {
            try data.write(to: url)
            print("wrote \(url.path) (\(Int(size.width))×\(Int(size.height)))")
        } catch {
            print("preview: \(error)")
        }
    }
}
