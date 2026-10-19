import AppKit
import SwiftUI

/// Owns the menu-bar status item and the panel under it. Clicking the icon
/// toggles a borderless panel that drops straight down from it (no popover
/// arrow, like the native AirPods menu). The panel opens on the compact quick
/// view; "Settings…" swaps the same panel to the full dashboard rather than
/// opening a separate window, so everything stays anchored to the icon.
/// Closing the panel returns it to the quick view for next time.
@MainActor
final class StatusBarController {
    /// Which of the two views the panel is showing. Observable so the hosted
    /// SwiftUI root re-renders when "Settings…" flips it.
    @Observable
    final class PanelState {
        var showsDetail = false
    }

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var pill: NSPanel?
    private var pillDismissal: Task<Void, Never>?
    private static let pillDuration: Duration = .seconds(4)
    private let panelState = PanelState()
    private var outsideClickMonitor: Any?
    private let bluetooth: BluetoothManager

    init(bluetooth: BluetoothManager) {
        self.bluetooth = bluetooth
        setupStatusItem()
    }

    private static let autosaveName = "GalaxyBudsStatusItem"

    private func setupStatusItem() {
        // Clear any remembered "hidden" state before the item reads it. Earlier
        // builds allowed the item to be removed from the menu bar, and macOS
        // persists that choice — which left the app with no entry point at all,
        // since the status item is the only one it has.
        clearRememberedHiddenState()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Deliberately not `.removalAllowed`: a stray ⌘-drag off the menu bar
        // would leave the user with no way back into the app.
        statusItem?.autosaveName = Self.autosaveName
        statusItem?.isVisible = true
        if let button = statusItem?.button {
            applyIcon(to: button)
            button.action = #selector(togglePanel)
            button.target = self
        }
        // On notched Macs the item is sometimes parked at the default far-right
        // slot instead of being given a real position; re-asserting visibility
        // on a later runloop forces a re-layout. Never toggle it off to do so —
        // that value is persisted, so being killed mid-toggle is one more way
        // the icon can disappear for good.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.statusItem?.isVisible = true
            self?.logStatusItemState()
        }
    }

    /// Removes the persisted visibility flags an earlier `.removalAllowed`
    /// build could leave set to 0. Position autosave lives under separate keys
    /// and is untouched.
    private func clearRememberedHiddenState() {
        let defaults = UserDefaults.standard
        for key in ["NSStatusItem Visible \(Self.autosaveName)",
                    "NSStatusItem VisibleCC \(Self.autosaveName)"]
        where defaults.object(forKey: key) != nil && !defaults.bool(forKey: key) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Records whether the item actually made it into the menu bar. An item
    /// that exists but is never placed leaves the app unreachable, and the
    /// difference is invisible from the outside — so it belongs in the log a
    /// bug report carries.
    private func logStatusItemState() {
        guard let item = statusItem else {
            DiagnosticsLog.shared.log("status item: missing")
            return
        }
        let button = item.button
        DiagnosticsLog.shared.log(
            "status item: visible=\(item.isVisible) "
            + "image=\(button?.image != nil) "
            + "buttonFrame=\(button.map { NSStringFromRect($0.frame) } ?? "nil") "
            + "window=\(button?.window.map { NSStringFromRect($0.frame) } ?? "nil")")
    }

    private func applyIcon(to button: NSStatusBarButton) {
        for name in ["airpodspro", "airpods", "headphones"] {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Budsy") {
                image.isTemplate = true
                button.image = image
                return
            }
        }
        button.title = "Buds"
    }

    // MARK: - Quick panel

    private func makePanel() -> NSPanel {
        let hosting = NSHostingController(
            rootView: PanelRootView(bluetooth: bluetooth, state: panelState) { [weak self] in
                self?.openDetailWindow()
            }
        )
        let panel = KeyablePanel(
            contentViewController: hosting
        )
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        // Movable as a safety net: the panel normally drops straight under the
        // menu-bar icon, but when the icon isn't where it should be the panel
        // has to stay reachable rather than stranded.
        panel.isMovableByWindowBackground = true
        // The hosted SwiftUI content resizes the window whenever it changes —
        // quick view to dashboard, dashboard to a sub-page — and AppKit grows a
        // window from its bottom-left corner, which pushes the top up under the
        // menu bar. Re-anchor under the icon after every resize.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self, let panel, panel.isVisible else { return }
                DiagnosticsLog.shared.log("panel: resized to \(NSStringFromSize(panel.frame.size))")
                self.anchorPanel(panel)
            }
        }
        return panel
    }

    /// Shown on launch / reopen so the user can find the app even if the
    /// menu-bar icon is hard to spot.
    func showPanel() {
        hidePill()
        guard panel?.isVisible != true else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        positionPanel(panel)
        // Key, not merely in front: controls in a window that isn't key draw
        // in their inactive look, so every switch stayed grey when on. A
        // non-activating panel can take key status without bringing the app
        // forward, the way Spotlight and Control Center do.
        panel.makeKeyAndOrderFront(nil)
        installOutsideClickMonitor()
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            closePanel()
        } else {
            showPanel()
        }
    }

    /// Positions the panel just under the menu-bar icon, but always clamped to be
    /// fully on-screen — so it's reachable even when the icon is hidden behind
    /// the notch or off the edge of a full menu bar.
    private func positionPanel(_ panel: NSPanel) {
        panel.layoutIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: 300, height: 360)
        panel.setContentSize(size)
        anchorPanel(panel)
    }

    /// Moves the panel (at its current size) to sit under the menu-bar icon,
    /// clamped to the visible screen.
    private func anchorPanel(_ panel: NSPanel) {
        let size = panel.frame.size
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var origin: NSPoint
        if let anchor = statusItemAnchor() {
            origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 2)
        } else {
            // No usable status button — fall back to top-centre of the screen.
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 8)
        }
        origin.x = min(max(frame.minX + 8, origin.x), frame.maxX - size.width - 8)
        // 2pt below the menu bar, where the system's own Bluetooth and Sound
        // panels sit.
        origin.y = min(max(frame.minY + 8, origin.y), frame.maxY - size.height - 2)
        panel.setFrameOrigin(origin)
        DiagnosticsLog.shared.log(
            "panel: anchored at \(NSStringFromRect(panel.frame)), gap below menu bar \(Int(frame.maxY - panel.frame.maxY))pt")
    }

    /// The status button's rect on screen, but only when it is genuinely sitting
    /// in a menu bar. An item macOS never placed still hands back a window, at
    /// an origin nowhere near the top of the screen — anchoring to that is what
    /// dropped the panel into a corner where it couldn't be moved.
    private func statusItemAnchor() -> NSRect? {
        guard statusItem?.isVisible == true,
              let button = statusItem?.button,
              let window = button.window
        else { return nil }

        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard rect.width > 0, rect.height > 0,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }),
              // The menu bar is the top ~40pt strip, taller on notched Macs.
              rect.minY >= screen.frame.maxY - 40
        else { return nil }
        return rect
    }

    private func closePanel() {
        panel?.orderOut(nil)
        removeOutsideClickMonitor()
        // Next open starts on the quick view again, like Control Center.
        panelState.showsDetail = false
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    // MARK: - Switched pill

    /// Briefly drops a pill under the icon saying the buds moved to another
    /// host; clicking it opens the panel, which offers to take them back.
    /// Skipped while the panel is open, since it already shows that state.
    func showSwitchedPill() {
        guard panel?.isVisible != true else { return }
        let pill = pill ?? makePill()
        self.pill = pill
        pill.layoutIfNeeded()
        pill.setContentSize(pill.contentView?.fittingSize ?? NSSize(width: 220, height: 30))
        anchorPanel(pill)
        pill.orderFrontRegardless()
        pillDismissal?.cancel()
        pillDismissal = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.pillDuration)
            guard !Task.isCancelled else { return }
            self?.hidePill()
        }
    }

    private func makePill() -> NSPanel {
        let hosting = NSHostingController(rootView: SwitchedPill { [weak self] in
            self?.showPanel()
        })
        let pill = KeyablePanel(contentViewController: hosting)
        pill.styleMask = [.borderless, .nonactivatingPanel]
        pill.isFloatingPanel = true
        pill.level = .popUpMenu
        pill.backgroundColor = .clear
        pill.isOpaque = false
        pill.hasShadow = true
        pill.hidesOnDeactivate = false
        return pill
    }

    private func hidePill() {
        pillDismissal?.cancel()
        pillDismissal = nil
        pill?.orderOut(nil)
    }

    // MARK: - Detail view

    /// Expands the panel in place to the full dashboard. The content resizes
    /// on the next layout pass, and a window grows from its bottom-left
    /// corner, so the panel is re-anchored under the icon once that happens.
    func openDetailWindow() {
        DiagnosticsLog.shared.log("panel: switching to dashboard (visible=\(panel?.isVisible ?? false))")
        panelState.showsDetail = true
    }

    func updateIcon(connected: Bool, batteryLeft: Int, batteryRight: Int) {
        guard let button = statusItem?.button else { return }
        let battery = connected ? "\(min(batteryLeft, batteryRight))%" : ""
        if button.image != nil {
            // The SF Symbol is always visible; show battery beside it when connected.
            button.title = battery.isEmpty ? "" : " \(battery)"
        } else {
            // No symbol available on this OS — keep a text label at all times so the
            // variable-length item never collapses to zero width and vanishes.
            button.title = battery.isEmpty ? "Buds" : "Buds \(battery)"
        }
    }

    deinit {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

/// A borderless panel that may become key. `NSPanel` refuses key status to a
/// borderless window by default, which left the panel's controls drawing in
/// their inactive state.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The pill dropped under the icon when the buds switch to another host.
private struct SwitchedPill: View {
    let action: () -> Void

    var body: some View {
        Label("Switched to another device", systemImage: "arrow.left.arrow.right")
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .contentShape(Capsule())
            .onTapGesture(perform: action)
            .fixedSize()
    }
}

/// Root of the menu-bar panel: the compact quick view, or the full dashboard
/// in its place. The dashboard gets the same backdrop and corner radius the
/// quick view draws for itself, since the panel window behind both is clear.
private struct PanelRootView: View {
    @Bindable var bluetooth: BluetoothManager
    var state: StatusBarController.PanelState
    let openDetail: () -> Void

    var body: some View {
        if state.showsDetail {
            PopoverView(bluetooth: bluetooth)
                .frame(width: DetailLayout.width)
                .modifier(PanelChrome())
        } else {
            MenuPopoverView(bluetooth: bluetooth, openDetail: openDetail)
        }
    }
}
