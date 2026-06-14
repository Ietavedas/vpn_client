import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var manager: ConnectionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("NaiveClient")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Import link")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("naive://user:pass@host:8443#name", text: $manager.importURLText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .font(.system(.caption, design: .monospaced))

                Button("Import") {
                    manager.importURL()
                }
            }

            if let profile = manager.profile {
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("Name", value: profile.name)
                        LabeledContent("Server", value: profile.displayAddress)
                        LabeledContent("Protocol", value: profile.proto.uppercased())
                    }
                    .font(.caption)
                }
            }

            if let importError = manager.lastImportError {
                Label(importError, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            statusView

            HStack {
                Button(manager.isConnected ? "Disconnect" : "Connect") {
                    manager.toggleConnection()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(isConnectDisabled)

                Spacer()

                Button("Quit") {
                    manager.disconnectImmediately()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(16)
        .frame(width: 360)
        .onOpenURL { url in
            manager.handleIncomingURL(url)
        }
    }

    private var isConnectDisabled: Bool {
        if case .connecting = manager.state { return true }
        if manager.profile == nil { return true }
        return false
    }

    @ViewBuilder
    private var statusView: some View {
        switch manager.state {
        case .disconnected:
            Label("Disconnected", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .connecting:
            Label("Connecting...", systemImage: "hourglass")
                .foregroundStyle(.orange)
        case .connected:
            Label("Connected via SOCKS 127.0.0.1:1080", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label("Connection failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption.weight(.semibold))
                Text(message)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(ConnectionManager())
}
