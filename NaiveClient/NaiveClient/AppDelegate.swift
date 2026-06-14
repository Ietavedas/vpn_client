import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var connectionManager: ConnectionManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
