import Foundation
import Network

enum NaiveProcessError: LocalizedError {
    case binaryNotFound
    case portAlreadyInUse(Int)
    case processExited(Int32, String?)
    case failedToStart(String)
    case portNotReady(String?)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "naive binary not found in the app bundle. Reinstall NaiveClient."
        case .portAlreadyInUse(let port):
            return "Local port \(port) is already in use. Close other proxy apps and try again."
        case .processExited(let code, let log):
            if let log, !log.isEmpty {
                return "naive exited with code \(code): \(log)"
            }
            return "naive exited unexpectedly with code \(code)."
        case .failedToStart(let message):
            return "Failed to start naive: \(message)"
        case .portNotReady(let log):
            if let log, !log.isEmpty {
                return "naive did not open local port \(ConfigWriter.listenPort) in time: \(log)"
            }
            return "naive did not open local port \(ConfigWriter.listenPort) in time."
        }
    }
}

final class NaiveProcessManager: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastLogLine: String?

    private var process: Process?
    private var stderrBuffer = ""
    private let queue = DispatchQueue(label: "NaiveProcessManager")

    var binaryURL: URL? {
        Bundle.main.url(forResource: "naive", withExtension: nil)
    }

    func start(configURL: URL) async throws {
        guard let binaryURL else { throw NaiveProcessError.binaryNotFound }

        if await isPortOpen(host: "127.0.0.1", port: ConfigWriter.listenPort) {
            throw NaiveProcessError.portAlreadyInUse(ConfigWriter.listenPort)
        }

        try await stop()
        stderrBuffer = ""

        let proc = Process()
        proc.executableURL = binaryURL
        proc.arguments = [configURL.path]
        proc.currentDirectoryURL = configURL.deletingLastPathComponent()

        let stderrPipe = Pipe()
        proc.standardOutput = Pipe()
        proc.standardError = stderrPipe

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendLog(chunk)
            }
        }

        do {
            try proc.run()
        } catch {
            throw NaiveProcessError.failedToStart(error.localizedDescription)
        }

        process = proc

        let ready = await waitForReady(process: proc, timeout: 8)
        guard ready else {
            let log = lastMeaningfulLog()
            let exitCode = proc.isRunning ? nil : proc.terminationStatus
            await stop()

            if let exitCode {
                throw NaiveProcessError.processExited(exitCode, log)
            }
            throw NaiveProcessError.portNotReady(log)
        }

        await MainActor.run {
            isRunning = true
        }
    }

    func stop() async {
        stopSync()
    }

    func stopSync() {
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        process = nil
        isRunning = false
    }

    private func appendLog(_ chunk: String) {
        stderrBuffer.append(chunk)
        let lines = stderrBuffer.split(separator: "\n", omittingEmptySubsequences: false)
        if let last = lines.last {
            if chunk.hasSuffix("\n") {
                stderrBuffer = ""
            } else {
                stderrBuffer = String(last)
            }
            lastLogLine = String(last).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func lastMeaningfulLog() -> String? {
        let line = lastLogLine?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let line, !line.isEmpty else { return nil }
        return line
    }

    private func waitForReady(process: Process, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !process.isRunning {
                return false
            }
            if await isPortOpen(host: "127.0.0.1", port: ConfigWriter.listenPort) {
                return true
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return false
    }

    private func isPortOpen(host: String, port: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            var resumed = false
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: UInt16(port)),
                using: .tcp
            )
            connection.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    connection.cancel()
                    continuation.resume(returning: true)
                case .failed, .cancelled:
                    resumed = true
                    continuation.resume(returning: false)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }
}
