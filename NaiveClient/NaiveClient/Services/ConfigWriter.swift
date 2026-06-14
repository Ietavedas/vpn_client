import Foundation

enum ConfigWriterError: LocalizedError {
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let reason):
            return "Failed to save connection profile: \(reason)"
        }
    }
}

enum ConfigWriter {
    static let appSupportFolder = "NaiveClient"
    static let configFileName = "config.json"
    static let listenPort = 1080

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appSupportFolder, isDirectory: true)
    }

    static var configURL: URL {
        supportDirectory.appendingPathComponent(configFileName)
    }

    static func ensureSupportDirectory() throws {
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        } catch {
            throw ConfigWriterError.writeFailed(error.localizedDescription)
        }
    }

    @discardableResult
    static func write(profile: NaiveProfile) throws -> URL {
        try ensureSupportDirectory()

        let payload = profile.configDictionary(listenPort: listenPort)
        let data: Data
        do {
            data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            )
        } catch {
            throw ConfigWriterError.writeFailed(error.localizedDescription)
        }

        do {
            try data.write(to: configURL, options: .atomic)
        } catch {
            throw ConfigWriterError.writeFailed(error.localizedDescription)
        }

        return configURL
    }
}
