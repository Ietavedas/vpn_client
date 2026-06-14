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

        let proto = protocolForScheme(scheme)
        return try parseManual(trimmed, proto: proto)
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

    private static func parseManual(_ raw: String, proto: String) throws -> NaiveProfile {
        guard let bodyStart = raw.range(of: "://") else {
            throw NaiveURLError.invalidURL
        }

        var body = String(raw[bodyStart.upperBound...])
        var name = "naive"

        if let hashIndex = body.firstIndex(of: "#") {
            let fragment = String(body[body.index(after: hashIndex)...])
            let decodedName = fragment.removingPercentEncoding?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let decodedName, !decodedName.isEmpty {
                name = decodedName
            }
            body = String(body[..<hashIndex])
        }

        guard let atIndex = body.lastIndex(of: "@") else {
            throw NaiveURLError.missingCredentials
        }

        let authPart = String(body[..<atIndex])
        let hostPart = String(body[body.index(after: atIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard let colonIndex = authPart.firstIndex(of: ":") else {
            throw NaiveURLError.missingCredentials
        }

        let username = String(authPart[..<colonIndex]).removingPercentEncoding
        let password = String(authPart[authPart.index(after: colonIndex)...]).removingPercentEncoding

        if username?.isEmpty != false || password?.isEmpty != false {
            throw NaiveURLError.missingCredentials
        }

        let hostPort = splitHostPort(hostPart)
        guard let host = hostPort.host, !host.isEmpty else {
            throw NaiveURLError.missingHost
        }

        let port = hostPort.port ?? defaultPort(for: proto)
        guard (1...65535).contains(port) else {
            throw NaiveURLError.invalidPort(port)
        }

        return NaiveProfile(
            name: name,
            username: username,
            password: password,
            host: host,
            port: port,
            proto: proto
        )
    }

    private static func splitHostPort(_ value: String) -> (host: String?, port: Int?) {
        if value.hasPrefix("[") {
            if let end = value.firstIndex(of: "]") {
                let host = String(value[value.index(after: value.startIndex)..<end])
                let remainder = value[value.index(after: end)...]
                if remainder.hasPrefix(":"), let port = Int(remainder.dropFirst()) {
                    return (host, port)
                }
                return (host, nil)
            }
        }

        if let colon = value.lastIndex(of: ":"),
           value[colon...].dropFirst().allSatisfy(\.isNumber),
           let port = Int(value[value.index(after: colon)...]) {
            let host = String(value[..<colon])
            return (host, port)
        }

        return (value, nil)
    }

    private static func extractScheme(from raw: String) -> String {
        guard let range = raw.range(of: "://") else { return "" }
        return String(raw[..<range.lowerBound]).lowercased()
    }

    private static func protocolForScheme(_ scheme: String) -> String {
        switch scheme {
        case "naive+quic":
            return "quic"
        default:
            return "https"
        }
    }

    private static func defaultPort(for proto: String) -> Int {
        443
    }
}

private extension CharacterSet {
    static let urlUserAllowed: CharacterSet = {
        var set = CharacterSet.urlUserAllowed
        set.insert(charactersIn: ":")
        return set
    }()

    static let urlPasswordAllowed: CharacterSet = {
        var set = CharacterSet.urlPasswordAllowed
        set.insert(charactersIn: ":@")
        return set
    }()
}
