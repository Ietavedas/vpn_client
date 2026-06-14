import Foundation

enum NaiveURLError: LocalizedError {
    case emptyInput
    case invalidURL
    case unsupportedScheme(String)
    case missingHost
    case invalidPort(Int)
    case missingCredentials
    case unsupportedProtocol(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Paste a naive:// link first."
        case .invalidURL:
            return "Invalid naive:// URL. Example: naive://user:pass@host:8443#name"
        case .unsupportedScheme(let scheme):
            return "Unsupported scheme \"\(scheme)\". Use naive://, naive+https:// or naive+quic://."
        case .missingHost:
            return "Host is missing in the URL."
        case .invalidPort(let port):
            return "Invalid port \(port). Use a value between 1 and 65535."
        case .missingCredentials:
            return "Username and password are required in the URL."
        case .unsupportedProtocol(let proto):
            return "Unsupported protocol \"\(proto)\". Only https and quic are supported."
        }
    }
}

enum NaiveURLParser {
    private static let supportedSchemes = ["naive", "naive+https", "naive+quic"]
    private static let supportedProtocols = ["https", "quic"]

    static func parse(_ raw: String) throws -> NaiveProfile {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NaiveURLError.emptyInput }

        let scheme = extractScheme(from: trimmed)
        guard supportedSchemes.contains(scheme) else {
            throw NaiveURLError.unsupportedScheme(scheme.isEmpty ? "unknown" : scheme)
        }

        let normalized = normalizeScheme(trimmed)
        guard let components = URLComponents(string: normalized) else {
            throw NaiveURLError.invalidURL
        }

        guard let host = components.host, !host.isEmpty else {
            throw NaiveURLError.missingHost
        }

        let proto = components.scheme ?? "https"
        guard supportedProtocols.contains(proto) else {
            throw NaiveURLError.unsupportedProtocol(proto)
        }

        let port = components.port ?? defaultPort(for: proto)
        guard (1...65535).contains(port) else {
            throw NaiveURLError.invalidPort(port)
        }

        let username = components.user?.removingPercentEncoding
        let password = components.password?.removingPercentEncoding
        if username?.isEmpty != false || password?.isEmpty != false {
            throw NaiveURLError.missingCredentials
        }

        let name = components.fragment?.removingPercentEncoding ?? "naive"

        return NaiveProfile(
            name: name,
            username: username,
            password: password,
            host: host,
            port: port,
            proto: proto
        )
    }

    static func validate(_ profile: NaiveProfile) throws {
        guard !profile.host.isEmpty else { throw NaiveURLError.missingHost }
        guard (1...65535).contains(profile.port) else {
            throw NaiveURLError.invalidPort(profile.port)
        }
        guard supportedProtocols.contains(profile.proto) else {
            throw NaiveURLError.unsupportedProtocol(profile.proto)
        }
        if profile.username?.isEmpty != false || profile.password?.isEmpty != false {
            throw NaiveURLError.missingCredentials
        }
    }

    static func toURLString(from profile: NaiveProfile) -> String {
        var auth = ""
        if let username = profile.username, let password = profile.password {
            let user = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? username
            let pass = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password
            auth = "\(user):\(pass)@"
        }

        let fragment = profile.name.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? profile.name
        return "naive://\(auth)\(profile.host):\(profile.port)#\(fragment)"
    }

    private static func extractScheme(from raw: String) -> String {
        guard let range = raw.range(of: "://") else { return "" }
        return String(raw[..<range.lowerBound]).lowercased()
    }

    private static func normalizeScheme(_ raw: String) -> String {
        if raw.hasPrefix("naive+https://") {
            return raw.replacingOccurrences(of: "naive+https://", with: "https://")
        }
        if raw.hasPrefix("naive+quic://") {
            return raw.replacingOccurrences(of: "naive+quic://", with: "quic://")
        }
        if raw.hasPrefix("naive://") {
            return raw.replacingOccurrences(of: "naive://", with: "https://")
        }
        return raw
    }

    private static func defaultPort(for proto: String) -> Int {
        443
    }
}
