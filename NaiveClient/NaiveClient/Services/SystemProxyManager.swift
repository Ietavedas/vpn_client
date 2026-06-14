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

final class SystemProxyManager {
    static let shared = SystemProxyManager()
    private var enabledServices: [String] = []

    func enable(port: Int = ConfigWriter.listenPort) throws {
        let services = try activeNetworkServices()
        guard !services.isEmpty else { throw SystemProxyError.noNetworkService }

        enabledServices = []
        for service in services {
            try runNetworkSetup(["-setsocksfirewallproxy", service, "127.0.0.1", "\(port)"])
            try runNetworkSetup(["-setsocksfirewallproxystate", service, "on"])
            enabledServices.append(service)
        }
    }

    func disable() {
        for service in enabledServices {
            _ = try? runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
        }
        enabledServices = []
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
