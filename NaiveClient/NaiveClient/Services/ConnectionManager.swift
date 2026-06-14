import Foundation

enum ConnectionManagerError: LocalizedError {
    case noProfile
    case invalidProfile(String)

    var errorDescription: String? {
        switch self {
        case .noProfile:
            return "Import a naive:// link before connecting."
        case .invalidProfile(let reason):
            return "Profile is invalid: \(reason)"
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

    private let processManager = NaiveProcessManager()
    private let proxyManager = SystemProxyManager.shared

    private enum StorageKey {
        static let profile = "savedProfile"
        static let importURL = "savedImportURL"
    }

    init() {
        loadSavedProfile()
    }

    var isConnected: Bool {
        if case .connected = state { return true }
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
        guard let profile else {
            setConnectionError(ConnectionManagerError.noProfile)
            return
        }

        do {
            try NaiveURLParser.validate(profile)
        } catch {
            setConnectionError(ConnectionManagerError.invalidProfile(error.localizedDescription))
            return
        }

        state = .connecting
        lastConnectionError = nil

        Task {
            do {
                let configURL = try ConfigWriter.write(profile: profile)
                try await processManager.start(configURL: configURL)
                try proxyManager.enable()
                state = .connected
                lastConnectionError = nil
            } catch {
                await processManager.stop()
                proxyManager.disable()
                setConnectionError(error)
            }
        }
    }

    func disconnect() {
        Task {
            await disconnectInternal()
        }
    }

    func disconnectImmediately() {
        processManager.stopSync()
        proxyManager.disable()
        state = .disconnected
        lastConnectionError = nil
    }

    private func disconnectInternal() async {
        await processManager.stop()
        proxyManager.disable()
        state = .disconnected
        lastConnectionError = nil
    }

    func toggleConnection() {
        isConnected ? disconnect() : connect()
    }

    func handleIncomingURL(_ url: URL) {
        importURLText = url.absoluteString
        importURL(url.absoluteString)
    }

    private func setConnectionError(_ error: Error) {
        let message = error.localizedDescription
        lastConnectionError = message
        state = .error(message)
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
