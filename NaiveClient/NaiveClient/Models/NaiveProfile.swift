import Foundation

struct NaiveProfile: Codable, Equatable {
    var name: String
    var username: String?
    var password: String?
    var host: String
    var port: Int
    var proto: String

    var displayAddress: String {
        "\(host):\(port)"
    }

    func proxyURLString() -> String {
        var auth = ""
        if let username, let password {
            let encodedUser = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? username
            let encodedPass = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password
            auth = "\(encodedUser):\(encodedPass)@"
        }
        return "\(proto)://\(auth)\(host):\(port)"
    }

    func configDictionary(listenPort: Int = 1080) -> [String: Any] {
        [
            "listen": "socks://127.0.0.1:\(listenPort)",
            "proxy": proxyURLString(),
            "log": "",
        ]
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
