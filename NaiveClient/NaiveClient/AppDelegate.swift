import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var connectionManager: ConnectionManager!
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        connectionManager = ConnectionManager()
        NSApp.setActivationPolicy(.regular)

        statusBarController = StatusBarController(connectionManager: connectionManager)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.statusBarController?.showPanel()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBarController?.showPanel()
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
}
