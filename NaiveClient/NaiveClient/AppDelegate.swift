import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var connectionManager: ConnectionManager?

    func applicationWillTerminate(_ notification: Notification) {
        connectionManager?.disconnectImmediately()
    }
}
