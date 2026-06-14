import Darwin
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
    private var stdoutBuffer = ""
    private var stderrBuffer = ""
    private var emittedLogLines: [String] = []
    private var lastLogLine: String?
    private var isRunning = false
    private var logHandler: (@Sendable (String) -> Void)?
    private let queue = DispatchQueue(label: "NaiveProcessManager")

    func setLogHandler(_ handler: (@Sendable (String) -> Void)?) {
        stateLock.lock()
        logHandler = handler
        stateLock.unlock()
    }

    func start(
        configURL: URL,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws {
        onProgress?("Preparing naive binary…")
        let binaryURL = try preparedBinaryURL()
        onProgress?("Binary ready: \(binaryURL.path)")

        onProgress?("Checking local port \(ConfigWriter.listenPort)…")
        if await isPortOpen(host: "127.0.0.1", port: ConfigWriter.listenPort, timeout: 2) {
            throw NaiveProcessError.portAlreadyInUse(ConfigWriter.listenPort)
        }
        onProgress?("Port \(ConfigWriter.listenPort) is free")

        onProgress?("Stopping previous naive process…")
        stopSync()
        clearLog()
        onProgress?("Ready to launch naive")

        try await Task.detached(priority: .userInitiated) {
            onProgress?("Running naive with config \(configURL.lastPathComponent)")

            let proc = Process()
            proc.executableURL = binaryURL
            proc.arguments = [configURL.path]
            proc.currentDirectoryURL = configURL.deletingLastPathComponent()

            let stderrPipe = Pipe()
            let stdoutPipe = Pipe()
            proc.standardOutput = stdoutPipe
            proc.standardError = stderrPipe

            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                self?.appendLog(chunk, stream: "stderr")
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                self?.appendLog(chunk, stream: "stdout")
            }

            proc.terminationHandler = { finished in
                onProgress?("naive process exited with code \(finished.terminationStatus)")
            }

            do {
                try proc.run()
            } catch {
                throw NaiveProcessError.failedToStart(error.localizedDescription)
            }

            self.setProcess(proc)
            onProgress?("naive process started (pid \(proc.processIdentifier))")

            let ready = await self.waitForReady(process: proc, timeout: 15, onProgress: onProgress)
            guard ready else {
                let log = self.combinedLogTail()
                let exitCode = proc.isRunning ? nil : proc.terminationStatus
                self.stopSync()

                if let exitCode {
                    throw NaiveProcessError.processExited(exitCode, log)
                }
                throw NaiveProcessError.portNotReady(log)
            }

            self.setRunning(true)
            onProgress?("Local SOCKS port \(ConfigWriter.listenPort) is open")
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
        logHandler = nil
        stateLock.unlock()

        guard let runningProcess, runningProcess.isRunning else { return }

        let pid = runningProcess.processIdentifier
        runningProcess.terminate()

        let deadline = Date().addingTimeInterval(2)
        while runningProcess.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if runningProcess.isRunning {
            kill(pid, SIGKILL)
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func preparedBinaryURL() throws -> URL {
        guard let bundled = Bundle.main.url(forResource: "naive", withExtension: nil) else {
            throw NaiveProcessError.binaryNotFound
        }

        try ConfigWriter.ensureSupportDirectory()
        let destination = ConfigWriter.supportDirectory.appendingPathComponent("naive")

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: bundled, to: destination)

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
        stdoutBuffer = ""
        stderrBuffer = ""
        emittedLogLines = []
        lastLogLine = nil
        stateLock.unlock()
    }

    private func appendLog(_ chunk: String, stream: String) {
        stateLock.lock()
        var linesToEmit: [String] = []
        if stream == "stdout" {
            drainBuffer(&stdoutBuffer, chunk: chunk, stream: stream, into: &linesToEmit)
        } else {
            drainBuffer(&stderrBuffer, chunk: chunk, stream: stream, into: &linesToEmit)
        }
        let handler = logHandler
        stateLock.unlock()

        for line in linesToEmit {
            recordEmittedLine(line)
            handler?(line)
        }
    }

    private func drainBuffer(_ buffer: inout String, chunk: String, stream: String, into linesToEmit: inout [String]) {
        buffer.append(chunk)
        while let newlineIndex = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newlineIndex])
            buffer = String(buffer[buffer.index(after: newlineIndex)...])
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                linesToEmit.append("[\(stream)] \(trimmed)")
            }
        }
    }

    private func recordEmittedLine(_ line: String) {
        stateLock.lock()
        lastLogLine = line
        emittedLogLines.append(line)
        if emittedLogLines.count > 50 {
            emittedLogLines.removeFirst(emittedLogLines.count - 50)
        }
        stateLock.unlock()
    }

    private func combinedLogTail() -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        if !emittedLogLines.isEmpty {
            return emittedLogLines.suffix(3).joined(separator: " | ")
        }
        let line = lastLogLine?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let line, !line.isEmpty else { return nil }
        return line
    }

    private func waitForReady(
        process: Process,
        timeout: TimeInterval,
        onProgress: (@Sendable (String) -> Void)?
    ) async -> Bool {
        let started = Date()
        let deadline = started.addingTimeInterval(timeout)
        while Date() < deadline {
            if !process.isRunning {
                onProgress?("naive process exited before port became ready")
                return false
            }

            let elapsed = Int(Date().timeIntervalSince(started))
            let logHint = combinedLogTail() ?? "no output from naive yet"
            onProgress?("Waiting for SOCKS :\(ConfigWriter.listenPort)… \(elapsed)s (\(logHint))")

            if await isPortOpen(host: "127.0.0.1", port: ConfigWriter.listenPort, timeout: 1) {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    private func isPortOpen(host: String, port: Int, timeout: TimeInterval) async -> Bool {
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
            queue.asyncAfter(deadline: .now() + timeout) {
                connection.cancel()
                gate.complete(continuation, value: false)
            }
        }
    }
}
