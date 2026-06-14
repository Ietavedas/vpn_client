import Foundation
import Network

private final class SOCKSProbeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func complete(connection: NWConnection, continuation: CheckedContinuation<String, Never>, message: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        connection.cancel()
        continuation.resume(returning: message)
    }
}

enum ConnectionDiagnostics {
    static func verifySOCKSProxy(
        host: String = "127.0.0.1",
        port: Int = ConfigWriter.listenPort,
        timeout: TimeInterval = 5
    ) async -> String {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "ConnectionDiagnostics.socks")
            let gate = SOCKSProbeGate()
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: UInt16(port)),
                using: .tcp
            )

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let greeting = Data([0x05, 0x01, 0x00])
                    connection.send(content: greeting, completion: .contentProcessed { error in
                        if let error {
                            gate.complete(connection: connection, continuation: continuation, message: "SOCKS write failed: \(error.localizedDescription)")
                            return
                        }

                        connection.receive(minimumIncompleteLength: 2, maximumLength: 64) { data, _, _, error in
                            if let error {
                                gate.complete(connection: connection, continuation: continuation, message: "SOCKS read failed: \(error.localizedDescription)")
                                return
                            }

                            guard let data, data.count >= 2 else {
                                gate.complete(connection: connection, continuation: continuation, message: "SOCKS returned empty response")
                                return
                            }

                            if data[0] == 0x05, data[1] == 0x00 {
                                gate.complete(connection: connection, continuation: continuation, message: "SOCKS5 proxy responded OK (no auth)")
                                return
                            }

                            let hex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
                            gate.complete(connection: connection, continuation: continuation, message: "SOCKS unexpected response: \(hex)")
                        }
                    })
                case .failed(let error):
                    gate.complete(connection: connection, continuation: continuation, message: "TCP to \(host):\(port) failed: \(error.localizedDescription)")
                case .cancelled:
                    gate.complete(connection: connection, continuation: continuation, message: "SOCKS check cancelled")
                default:
                    break
                }
            }

            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                gate.complete(connection: connection, continuation: continuation, message: "SOCKS check timed out after \(Int(timeout))s")
            }
        }
    }
}
