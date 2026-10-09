import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let showPanelNotification = Notification.Name("com.nivorbit.galaxybuds.showPanel")
    /// The identifier used before 1.3.0. A copy of that build may still be
    /// running (a stale login item, say), and it holds the one RFCOMM channel
    /// to the buds — so it counts as "already running" for the single-instance
    /// check even though its bundle id no longer matches ours.
    private static let legacyBundleIdentifier = "com.nivorbit.budsapp"

    private var statusBarController: StatusBarController?
    private let bluetooth = BluetoothManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance: if another copy is already running, hand off to it
        // and quit. Two instances would fight over the one RFCOMM channel to
        // the buds and show duplicate menu-bar icons.
        let me = NSRunningApplication.current
        let identifiers = [me.bundleIdentifier, Self.legacyBundleIdentifier].compactMap { $0 }
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
        // When the buds connect, drop in the small AirPods-style card rather
        // than the full panel; clicking it (or the menu-bar icon) opens the panel.
        bluetooth.onAutoConnected = { [weak controller] in controller?.showConnectToast() }
        // Prime permission and auto-connect to an already-connected Galaxy Buds.
        bluetooth.startAutoConnect()
        // No panel on launch: the connect card appears once the buds connect,
        // and the menu-bar icon opens the full panel.
        startObservingStatus()
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
            withTitle: String(localized: "Quit Galaxy Buds"),
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
