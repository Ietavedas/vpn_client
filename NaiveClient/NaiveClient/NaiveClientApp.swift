import SwiftUI

@main
struct NaiveClientApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            Text("NaiveClient runs from the menu bar and Dock.")
                .padding()
        }
    }
}
