import AppKit
import Foundation

enum ConnectionManagerError: LocalizedError {
    case noProfile
    case invalidProfile(String)
    case socksProbeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noProfile:
            return "Import a naive:// link before connecting."
        case .invalidProfile(let reason):
            return "Profile is invalid: \(reason)"
        case .socksProbeFailed(let reason):
            return "SOCKS probe failed: \(reason)"
        }
    }
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

@MainActor
final class ConnectionManager: ObservableObject {
    @Published var state: ConnectionState = .disconnected
    @Published var profile: NaiveProfile?
    @Published var importURLText = ""
    @Published private(set) var lastImportError: String?
    @Published private(set) var lastConnectionError: String?
    @Published private(set) var connectionSteps: [ConnectionStepItem] = []
    @Published private(set) var activityLog: [String] = []
    @Published private(set) var currentStepTitle: String?

    private let processManager = NaiveProcessManager()
    private let proxyManager = SystemProxyManager.shared

    private enum StorageKey {
        static let profile = "savedProfile"
        static let importURL = "savedImportURL"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    init() {
        loadSavedProfile()
    }

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    var isConnecting: Bool {
        if case .connecting = state { return true }
        return false
    }

    func importURL(_ raw: String? = nil) {
        let value = (raw ?? importURLText).trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let parsed = try NaiveURLParser.parse(value)
            try NaiveURLParser.validate(parsed)

            profile = parsed
            importURLText = NaiveURLParser.toURLString(from: parsed)
            lastImportError = nil
            saveProfile()

            if !isConnected {
                state = .disconnected
            }
        } catch {
            lastImportError = error.localizedDescription
            if !isConnected {
                state = .error(error.localizedDescription)
            }
        }
    }

    func connect() {
        guard let currentProfile = profile else {
            setConnectionError(ConnectionManagerError.noProfile)
            return
        }

        resetConnectionProgress()
        appendActivity("Connect requested → \(currentProfile.displayAddress) (\(currentProfile.proto))")
        state = .connecting
        lastConnectionError = nil

        Task { [currentProfile] in
            var profile = currentProfile
            if let latest = self.profile {
                profile = latest
            }

            do {
                try await runStep("validate") {
                    try NaiveURLParser.validate(profile)
                    appendActivity("Profile validated (\(profile.proto.uppercased()))")
                }

                let configURL = try await runStep("config") {
                    appendActivity("Upstream proxy: \(profile.redactedProxyURLString())")
                    let url = try ConfigWriter.write(profile: profile)
                    appendActivity("Config saved: \(url.path)")
                    return url
                }

                processManager.setLogHandler { line in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.appendActivity("naive: \(line)")
                        self.updateStepDetail("naive", detail: line)
                    }
                }

                beginStep("naive")
                do {
                    try await processManager.start(configURL: configURL) { progress in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.appendActivity(progress)
                            self.updateStepDetail("naive", detail: progress)
                            if progress.contains("Waiting for SOCKS") || progress.contains("process started") {
                                if self.connectionSteps.first(where: { $0.id == "socks" })?.status == .pending {
                                    self.beginStep("socks")
                                }
                                self.updateStepDetail("socks", detail: progress)
                            }
                        }
                    }
                    finishStep("naive", success: true, detail: "naive running")
                    finishStep("socks", success: true, detail: "Port \(ConfigWriter.listenPort) open")
                } catch {
                    finishStep("naive", success: false, detail: error.localizedDescription)
                    finishStep("socks", success: false, detail: error.localizedDescription)
                    throw error
                }

                let probeMessage = try await runStep("probe") {
                    appendActivity("Testing SOCKS handshake on 127.0.0.1:\(ConfigWriter.listenPort)…")
                    let message = await ConnectionDiagnostics.verifySOCKSProxy()
                    appendActivity(message)
                    guard message.contains("OK") else {
                        throw ConnectionManagerError.socksProbeFailed(message)
                    }
                    return message
                }

                try await runStep("proxy") {
                    appendActivity("Enabling macOS system SOCKS proxy…")
                    try await proxyManager.enable()
                    appendActivity("System proxy enabled for active network interfaces")
                }

                finishStep("proxy", success: true, detail: probeMessage)
                state = .connected
                lastConnectionError = nil
                appendActivity("Connected successfully")
            } catch {
                await processManager.stop()
                await proxyManager.disable()
                setConnectionError(error)
            }
        }
    }

    func disconnect() {
        Task {
            await disconnectInternal()
        }
    }

    func disconnectImmediately() async {
        await processManager.stop()
        await proxyManager.disable()
        state = .disconnected
        lastConnectionError = nil
        currentStepTitle = nil
        appendActivity("Disconnected")
    }

    private func disconnectInternal() async {
        await processManager.stop()
        await proxyManager.disable()
        state = .disconnected
        lastConnectionError = nil
        currentStepTitle = nil
        appendActivity("Disconnected")
    }

    func toggleConnection() {
        isConnected ? disconnect() : connect()
    }

    func handleIncomingURL(_ url: URL) {
        importURLText = url.absoluteString
        importURL(url.absoluteString)
    }

    func setProtocol(_ proto: String) {
        guard var profile, ["https", "quic"].contains(proto) else { return }
        profile.proto = proto
        self.profile = profile
        importURLText = NaiveURLParser.toURLString(from: profile)
        saveProfile()
        appendActivity("Protocol set to \(proto.uppercased())")
    }

    private func resetConnectionProgress() {
        connectionSteps = [
            ConnectionStepItem(id: "validate", title: "Validate profile"),
            ConnectionStepItem(id: "config", title: "Write config.json"),
            ConnectionStepItem(id: "naive", title: "Launch naive process"),
            ConnectionStepItem(id: "socks", title: "Wait for local SOCKS :1080"),
            ConnectionStepItem(id: "probe", title: "Test SOCKS response"),
            ConnectionStepItem(id: "proxy", title: "Enable system proxy"),
        ]
        activityLog = []
        currentStepTitle = nil
    }

    private func appendActivity(_ message: String) {
        let line = "[\(Self.timeFormatter.string(from: Date()))] \(message)"
        activityLog.append(line)
        if activityLog.count > 200 {
            activityLog.removeFirst(activityLog.count - 200)
        }
    }

    private func beginStep(_ id: String) {
        guard let index = connectionSteps.firstIndex(where: { $0.id == id }) else { return }
        connectionSteps[index].status = .running
        currentStepTitle = connectionSteps[index].title
    }

    private func finishStep(_ id: String, success: Bool, detail: String? = nil) {
        guard let index = connectionSteps.firstIndex(where: { $0.id == id }) else { return }
        connectionSteps[index].status = success ? .success : .failed
        if let detail {
            connectionSteps[index].detail = detail
        }
    }

    private func updateStepDetail(_ id: String, detail: String) {
        guard let index = connectionSteps.firstIndex(where: { $0.id == id }) else { return }
        connectionSteps[index].detail = detail
    }

    private func runStep(_ id: String, _ work: () async throws -> Void) async rethrows {
        beginStep(id)
        do {
            try await work()
            finishStep(id, success: true)
        } catch {
            finishStep(id, success: false, detail: error.localizedDescription)
            throw error
        }
    }

    private func runStep<T>(_ id: String, _ work: () async throws -> T) async rethrows -> T {
        beginStep(id)
        do {
            let value = try await work()
            finishStep(id, success: true)
            return value
        } catch {
            finishStep(id, success: false, detail: error.localizedDescription)
            throw error
        }
    }

    private func setConnectionError(_ error: Error) {
        let message = error.localizedDescription
        lastConnectionError = message
        state = .error(message)
        appendActivity("ERROR: \(message)")
        showErrorAlert(message)
    }

    private func showErrorAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Connection failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func loadSavedProfile() {
        if let data = UserDefaults.standard.data(forKey: StorageKey.profile) {
            do {
                let saved = try JSONDecoder().decode(NaiveProfile.self, from: data)
                try NaiveURLParser.validate(saved)
                profile = saved
                importURLText = NaiveURLParser.toURLString(from: saved)
                return
            } catch {
                let message = "Saved profile is invalid: \(error.localizedDescription)"
                lastImportError = message
                state = .error(message)
            }
        }

        if let savedURL = UserDefaults.standard.string(forKey: StorageKey.importURL) {
            importURLText = savedURL
            importURL(savedURL)
        }
    }

    private func saveProfile() {
        guard let profile else { return }
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: StorageKey.profile)
        }
        UserDefaults.standard.set(importURLText, forKey: StorageKey.importURL)
    }
}
