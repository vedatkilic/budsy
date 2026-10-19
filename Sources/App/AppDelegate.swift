import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let showPanelNotification = Notification.Name("com.nivorbit.budsy.showPanel")
    /// The identifiers used before 1.3.0 and before the Budsy rename. A copy
    /// of either build may still be running (a stale login item, say), and it
    /// holds the one RFCOMM channel to the buds — so it counts as "already
    /// running" for the single-instance check even though its bundle id no
    /// longer matches ours.
    private static let legacyBundleIdentifiers = ["com.nivorbit.budsapp", "com.nivorbit.galaxybuds"]

    private var statusBarController: StatusBarController?
    private let bluetooth = BluetoothManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Headless render for design iteration; must run before the
        // single-instance hand-off or a running copy would swallow it.
        if PreviewRenderer.renderIfRequested() {
            NSApp.terminate(nil)
            return
        }
        // Single instance: if another copy is already running, hand off to it
        // and quit. Two instances would fight over the one RFCOMM channel to
        // the buds and show duplicate menu-bar icons.
        let me = NSRunningApplication.current
        let identifiers = [me.bundleIdentifier].compactMap { $0 } + Self.legacyBundleIdentifiers
        let others = identifiers
            .flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            .filter { $0 != me }
        if let existing = others.first {
            // Tell the already-running copy to surface its panel, then quit.
            existing.activate(options: [])
            DistributedNotificationCenter.default().postNotificationName(
                Self.showPanelNotification, object: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        // Let a re-launch (which hands off here and quits) re-open our panel.
        DistributedNotificationCenter.default().addObserver(
            forName: Self.showPanelNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.statusBarController?.showPanel() }
        }
        // An accessory app has no menu bar of its own, so install a minimal main
        // menu purely to wire up the standard ⌘Q quit key equivalent.
        setupMainMenu()
        let controller = StatusBarController(bluetooth: bluetooth)
        statusBarController = controller
        // Pop the panel up when the buds connect while we're running — an
        // AirPods-like appearance.
        bluetooth.onAutoConnected = { [weak controller] in controller?.showPanel() }
        bluetooth.onYieldedToOtherDevice = { [weak controller] in controller?.showSwitchedPill() }
        // Prime permission and auto-connect to an already-connected Galaxy Buds.
        bluetooth.startAutoConnect()
        // Defer the launch panel so the status item is laid out first; otherwise
        // it anchors to a not-yet-positioned button and appears detached.
        // `--settings` opens straight onto the dashboard; used to screenshot
        // and iterate on the detail view without clicking through the panel.
        let openSettings = ProcessInfo.processInfo.arguments.contains("--settings")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.statusBarController?.showPanel()
            if openSettings { self?.statusBarController?.openDetailWindow() }
        }
        startObservingStatus()
        observeSleepAndWake()
        LaunchAtLogin.restoreIfNeeded()
    }

    private func observeSleepAndWake() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.bluetooth.prepareForSleep() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.bluetooth.resumeAfterWake() }
        }
    }

    /// `budsy://demo` puts the app in demo mode: a stand-in connected device
    /// so every screen can be seen without Galaxy Buds — App Review has none.
    /// Disconnecting leaves demo mode.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "budsy" && $0.host == "demo" }) else { return }
        bluetooth.enterDemoMode()
        statusBarController?.showPanel()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        statusBarController?.showPanel()
        return true
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: String(localized: "Quit Budsy"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    private func startObservingStatus() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.bluetooth.pollAutoConnect()
                self.statusBarController?.updateIcon(
                    connected: self.bluetooth.isConnected,
                    batteryLeft: self.bluetooth.status.batteryLeft,
                    batteryRight: self.bluetooth.status.batteryRight
                )
            }
        }
    }
}
