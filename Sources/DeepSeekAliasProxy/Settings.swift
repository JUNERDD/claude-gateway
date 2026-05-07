import Darwin
import Foundation

struct ProxySettings {
    var host: String = "127.0.0.1"
    var port: Int = 4000
    var anthropicBaseURL: String = "https://api.deepseek.com/anthropic"
    var haikuTargetModel: String = "deepseek-v4-flash"
    var nonHaikuTargetModel: String = "deepseek-v4-pro[1m]"
    var advertisedModels: [String] = [
        "claude-opus-4-7",
        "claude-sonnet-4-6",
        "claude-haiku-4-5",
    ]
}

final class SettingsLoader {
    static let shared = SettingsLoader()

    private let lock = NSLock()
    private var cached: ProxySettings?
    private var cachedMTime: timespec?

    func load() -> ProxySettings {
        lock.lock()
        defer { lock.unlock() }

        let path = settingsPath()
        var statBuffer = stat()
        let exists = stat(path, &statBuffer) == 0
        let mtime = exists ? statBuffer.st_mtimespec : nil

        if let cached, sameMTime(cachedMTime, mtime) {
            return cached
        }

        var settings = ProxySettings()
        if exists,
            let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            if let value = cleanString(object["host"]) {
                settings.host = value
            }
            if let value = object["port"] as? Int {
                settings.port = value
            }
            if let value = cleanString(object["anthropicBaseURL"]) {
                settings.anthropicBaseURL = value
            }
            if let value = cleanString(object["haikuTargetModel"]) {
                settings.haikuTargetModel = value
            }
            if let value = cleanString(object["nonHaikuTargetModel"]) {
                settings.nonHaikuTargetModel = value
            }
            if let models = object["advertisedModels"] as? [String] {
                let cleaned = uniqueNonEmpty(models)
                if !cleaned.isEmpty {
                    settings.advertisedModels = cleaned
                }
            }
        }

        if let override = ProcessInfo.processInfo.environment["DEEPSEEK_ANTHROPIC_BASE_URL"],
            !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            settings.anthropicBaseURL = override.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        cached = settings
        cachedMTime = mtime
        return settings
    }

    private func settingsPath() -> String {
        if let configured = ProcessInfo.processInfo.environment["ALIAS_PROXY_SETTINGS_PATH"], !configured.isEmpty {
            return NSString(string: configured).expandingTildeInPath
        }
        return "\(NSHomeDirectory())/.config/claude-deepseek-gateway/proxy_settings.json"
    }

    private func cleanString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, !seen.contains(cleaned) else { continue }
            seen.insert(cleaned)
            result.append(cleaned)
        }
        return result
    }

    private func sameMTime(_ lhs: timespec?, _ rhs: timespec?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (l?, r?):
            return l.tv_sec == r.tv_sec && l.tv_nsec == r.tv_nsec
        default:
            return false
        }
    }
}
