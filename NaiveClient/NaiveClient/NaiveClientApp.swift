import SwiftUI

@main
struct NaiveClientApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var connectionManager = ConnectionManager()

    init() {}

    var body: some Scene {
        MenuBarExtra("NaiveClient", systemImage: menuBarIcon) {
            MenuBarView()
                .environmentObject(connectionManager)
                .onAppear {
                    appDelegate.connectionManager = connectionManager
                }
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        switch connectionManager.state {
        case .connected:
            return "network"
        case .connecting:
            return "network.badge.shield.half.filled"
        case .error:
            return "exclamationmark.triangle"
        case .disconnected:
            return "network.slash"
        }
    }
}
