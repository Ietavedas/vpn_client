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

                TextField("naive+quic://user:pass@host:8443#name", text: $manager.importURLText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .font(.system(.caption, design: .monospaced))

                Button("Import") {
                    manager.importURL()
                }
            }

            if let profile = manager.profile {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Name", value: profile.name)
                        LabeledContent("Server", value: profile.displayAddress)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Protocol")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Protocol", selection: protocolBinding) {
                                Text("QUIC").tag("quic")
                                Text("HTTPS").tag("https")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
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

            if showProgressPanel {
                progressPanel
            }

            HStack {
                Button(manager.isConnected ? "Disconnect" : "Connect") {
                    manager.toggleConnection()
                }
                .disabled(isConnectDisabled)

                Spacer()

                Button("Quit") {
                    Task {
                        await manager.disconnectImmediately()
                        NSApplication.shared.terminate(nil)
                    }
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(16)
        .frame(width: 400)
        .onOpenURL { url in
            manager.handleIncomingURL(url)
        }
    }

    private var showProgressPanel: Bool {
        manager.isConnecting || !manager.connectionSteps.isEmpty || !manager.activityLog.isEmpty
    }

    private var isConnectDisabled: Bool {
        if manager.isConnecting { return true }
        if manager.profile == nil { return true }
        return false
    }

    private var protocolBinding: Binding<String> {
        Binding(
            get: { manager.profile?.proto ?? "https" },
            set: { manager.setProtocol($0) }
        )
    }

    @ViewBuilder
    private var statusView: some View {
        switch manager.state {
        case .disconnected:
            Label("Disconnected", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .connecting:
            Label(manager.currentStepTitle ?? "Connecting…", systemImage: "hourglass")
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

    private var progressPanel: some View {
        GroupBox("Connection progress") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(manager.connectionSteps) { step in
                    stepRow(step)
                }

                Divider()

                HStack {
                    Text("Activity log")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Copy all") {
                        manager.copyActivityLogToClipboard()
                    }
                    Button("Save…") {
                        manager.saveActivityLogToFile()
                    }
                    Button("Clear") {
                        manager.clearActivityLog()
                    }
                }
                .font(.caption)

                if let message = manager.logActionMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    Text(manager.activityLogDisplayText.isEmpty ? "No log lines yet." : manager.activityLogDisplayText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                }
                .frame(height: 160)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.25))
                }
            }
        }
    }

    private func stepRow(_ step: ConnectionStepItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: stepIcon(for: step.status))
                .foregroundStyle(stepColor(for: step.status))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.caption.weight(step.status == .running ? .semibold : .regular))
                if let detail = step.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func stepIcon(for status: ConnectionStepStatus) -> String {
        switch status {
        case .pending:
            return "circle"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private func stepColor(for status: ConnectionStepStatus) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .running:
            return .orange
        case .success:
            return .green
        case .failed:
            return .red
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(ConnectionManager())
}
