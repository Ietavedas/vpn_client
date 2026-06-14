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

private final class PortCheckGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func complete(_ continuation: CheckedContinuation<Bool, Never>, value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation.resume(returning: value)
    }
}

final class NaiveProcessManager: @unchecked Sendable {
    private let stateLock = NSLock()
    private var process: Process?
    private var stderrBuffer = ""
    private var lastLogLine: String?
    private var isRunning = false
    private let queue = DispatchQueue(label: "NaiveProcessManager")

    func start(configURL: URL) async throws {
        let binaryURL = try preparedBinaryURL()

        if await isPortOpen(host: "127.0.0.1", port: ConfigWriter.listenPort) {
            throw NaiveProcessError.portAlreadyInUse(ConfigWriter.listenPort)
        }

        await stop()
        clearLog()

        try await Task.detached(priority: .userInitiated) {
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
                self?.appendLog(chunk)
            }

            do {
                try proc.run()
            } catch {
                throw NaiveProcessError.failedToStart(error.localizedDescription)
            }

            self.setProcess(proc)

            let ready = await self.waitForReady(process: proc, timeout: 8)
            guard ready else {
                let log = self.lastMeaningfulLog()
                let exitCode = proc.isRunning ? nil : proc.terminationStatus
                await self.stop()

                if let exitCode {
                    throw NaiveProcessError.processExited(exitCode, log)
                }
                throw NaiveProcessError.portNotReady(log)
            }

            self.setRunning(true)
        }.value
    }

    func stop() async {
        await Task.detached(priority: .userInitiated) {
            self.stopSync()
        }.value
    }

    func stopSync() {
        stateLock.lock()
        let runningProcess = process
        process = nil
        isRunning = false
        stateLock.unlock()

        if let runningProcess, runningProcess.isRunning {
            runningProcess.terminate()
            runningProcess.waitUntilExit()
        }
    }

    private func preparedBinaryURL() throws -> URL {
        guard let bundled = Bundle.main.url(forResource: "naive", withExtension: nil) else {
            throw NaiveProcessError.binaryNotFound
        }

        try ConfigWriter.ensureSupportDirectory()
        let destination = ConfigWriter.supportDirectory.appendingPathComponent("naive")

        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.copyItem(at: bundled, to: destination)
        }

        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: destination.path
        )
        removeQuarantine(from: destination)
        return destination
    }

    private func removeQuarantine(from url: URL) {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            removexattr(path, "com.apple.quarantine", 0)
        }
    }

    private func setProcess(_ process: Process) {
        stateLock.lock()
        self.process = process
        stateLock.unlock()
    }

    private func setRunning(_ running: Bool) {
        stateLock.lock()
        isRunning = running
        stateLock.unlock()
    }

    private func clearLog() {
        stateLock.lock()
        stderrBuffer = ""
        lastLogLine = nil
        stateLock.unlock()
    }

    private func appendLog(_ chunk: String) {
        stateLock.lock()
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
        stateLock.unlock()
    }

    private func lastMeaningfulLog() -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }
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
            let gate = PortCheckGate()
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: UInt16(port)),
                using: .tcp
            )
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.cancel()
                    gate.complete(continuation, value: true)
                case .failed, .cancelled:
                    gate.complete(continuation, value: false)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }
}
