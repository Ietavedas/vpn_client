import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var connectionManager: ConnectionManager?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }

        let otherInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }

        if let existing = otherInstances.first {
            existing.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)

        if !UserDefaults.standard.bool(forKey: Self.hasShownWelcomeKey) {
            UserDefaults.standard.set(true, forKey: Self.hasShownWelcomeKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                Self.showMenuBarHintAlert()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        Self.showMenuBarHintAlert()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let connectionManager else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await connectionManager.disconnectImmediately()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 3)
    }

    private static let hasShownWelcomeKey = "hasShownMenuBarWelcome.v2"

    private static func showMenuBarHintAlert() {
        let alert = NSAlert()
        alert.messageText = "NaiveClient is running"
        alert.informativeText = """
        This app lives in the menu bar (top-right, near Wi-Fi and the clock).

        1. Click the network icon in the menu bar.
        2. Paste your naive:// link and click Import.
        3. Click Connect.

        If you do not see the icon, click the «…» or «>>» control on the right side of the menu bar.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
