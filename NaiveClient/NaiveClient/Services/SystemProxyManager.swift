import Foundation

enum SystemProxyError: LocalizedError {
    case noNetworkService
    case adminRequired
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noNetworkService:
            return "No active network service found (Wi-Fi or Ethernet)."
        case .adminRequired:
            return "Permission denied while changing system proxy. Allow NaiveClient in System Settings."
        case .commandFailed(let message):
            return "Failed to configure system proxy: \(message)"
        }
    }
}

final class SystemProxyManager: @unchecked Sendable {
    static let shared = SystemProxyManager()
    private let lock = NSLock()
    private var enabledServices: [String] = []

    func enable(port: Int = ConfigWriter.listenPort) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await Task.detached(priority: .userInitiated) {
                    try self.enableSync(port: port)
                }.value
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 15_000_000_000)
                throw SystemProxyError.commandFailed("networksetup timed out after 15 seconds")
            }

            try await group.next()
            group.cancelAll()
        }
    }

    func disable() async {
        await Task.detached(priority: .userInitiated) {
            self.disableSync()
        }.value
    }

    func disableSync() {
        lock.lock()
        let services = enabledServices
        enabledServices = []
        lock.unlock()

        for service in services {
            _ = try? runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
        }
    }

    private func enableSync(port: Int) throws {
        let services = try activeNetworkServices()
        guard !services.isEmpty else { throw SystemProxyError.noNetworkService }

        lock.lock()
        enabledServices = []
        lock.unlock()

        var applied: [String] = []
        for service in services {
            try runNetworkSetup(["-setsocksfirewallproxy", service, "127.0.0.1", "\(port)"])
            try runNetworkSetup(["-setsocksfirewallproxystate", service, "on"])
            applied.append(service)
        }

        lock.lock()
        enabledServices = applied
        lock.unlock()
    }

    private func activeNetworkServices() throws -> [String] {
        let output = try runNetworkSetup(["-listallnetworkservices"])
        let blocked = Set([
            "An asterisk (*) denotes that a network service is disabled.",
            "Bluetooth PAN",
            "Thunderbolt Bridge",
        ])

        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !blocked.contains($0) && !$0.hasPrefix("*") }
    }

    @discardableResult
    private func runNetworkSetup(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw SystemProxyError.commandFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.localizedCaseInsensitiveContains("not authorized")
                || message.localizedCaseInsensitiveContains("denied") {
                throw SystemProxyError.adminRequired
            }
            throw SystemProxyError.commandFailed(message.isEmpty ? "networksetup exited with code \(process.terminationStatus)" : message)
        }

        return output
    }
}
