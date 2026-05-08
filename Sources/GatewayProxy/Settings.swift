import Darwin
import Foundation
import GatewayProxyCore

struct ProxySettings {
    var host: String = "127.0.0.1"
    var port: Int = 4000
    var providers: [GatewayProvider] = [GatewayConfigurationDefaults.provider]
    var defaultProviderID: String = GatewayConfigurationDefaults.providerID
    var defaultRoute: GatewayRouteTarget = GatewayConfigurationDefaults.routeTarget
    var modelRoutes: [GatewayModelRoute] = GatewayConfigurationDefaults.modelRoutes
    var visionProvider: String = "auto"
    var visionProviderModel: String = ""
    var visionProviderBaseURL: String = ""

    var advertisedModels: [String] {
        uniqueNonEmpty(modelRoutes.map(\.alias))
    }

    func provider(id: String) -> GatewayProvider? {
        providers.first { $0.id == id }
    }

    func route(for alias: String?) -> GatewayRouteTarget {
        guard let alias = alias?.trimmingCharacters(in: .whitespacesAndNewlines),
            !alias.isEmpty
        else {
            return defaultRoute
        }
        return modelRoutes.first { $0.alias == alias }?.target ?? defaultRoute
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
}

final class SettingsLoader {
    static let shared = SettingsLoader()

    private struct DiskSettings: Decodable {
        var host: String?
        var port: Int?
        var providers: [GatewayProvider]?
        var defaultProviderID: String?
        var defaultRoute: GatewayRouteTarget?
        var modelRoutes: [GatewayModelRoute]?
        var visionProvider: String?
        var visionProviderModel: String?
        var visionProviderBaseURL: String?
    }

    private let lock = NSLock()
    private var cachedSettings: ProxySettings?
    private var cachedSettingsPath: String?
    private var cachedSettingsMTime: timespec?
    private var cachedSecrets: GatewaySecrets?
    private var cachedSecretsPath: String?
    private var cachedSecretsMTime: timespec?

    func load() -> ProxySettings {
        lock.lock()
        defer { lock.unlock() }

        let path = settingsPath()
        let mtime = fileMTime(path)
        if let cachedSettings, cachedSettingsPath == path, sameMTime(cachedSettingsMTime, mtime) {
            return cachedSettings
        }

        var settings = ProxySettings()
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let decoded = try? JSONDecoder().decode(DiskSettings.self, from: data)
        {
            if let value = cleanString(decoded.host) {
                settings.host = value
            }
            if let value = decoded.port {
                settings.port = value
            }
            if let providers = decoded.providers, !providers.isEmpty {
                settings.providers = providers
            }
            if let value = cleanString(decoded.defaultProviderID) {
                settings.defaultProviderID = value
            }
            if let value = decoded.defaultRoute {
                settings.defaultRoute = value
            }
            if let modelRoutes = decoded.modelRoutes, !modelRoutes.isEmpty {
                settings.modelRoutes = modelRoutes
            }
            if let value = cleanString(decoded.visionProvider) {
                settings.visionProvider = value
            }
            if let value = decoded.visionProviderModel {
                settings.visionProviderModel = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let value = decoded.visionProviderBaseURL {
                settings.visionProviderBaseURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let override = ProcessInfo.processInfo.environment["GATEWAY_PROVIDER_BASE_URL"],
            let providerIndex = settings.providers.firstIndex(where: { $0.id == settings.defaultProviderID }),
            !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            settings.providers[providerIndex].baseURL = override.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let override = ProcessInfo.processInfo.environment["VISION_PROVIDER"],
            !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            settings.visionProvider = override.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let override = ProcessInfo.processInfo.environment["VISION_PROVIDER_MODEL"] {
            settings.visionProviderModel = override.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let override = ProcessInfo.processInfo.environment["VISION_PROVIDER_BASE_URL"] {
            settings.visionProviderBaseURL = override.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        cachedSettings = settings
        cachedSettingsPath = path
        cachedSettingsMTime = mtime
        return settings
    }

    func loadSecrets() -> GatewaySecrets {
        lock.lock()
        defer { lock.unlock() }

        let path = secretsPath()
        let mtime = fileMTime(path)
        if let cachedSecrets, cachedSecretsPath == path, sameMTime(cachedSecretsMTime, mtime) {
            return cachedSecrets
        }

        var secrets = GatewaySecrets()
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let decoded = try? JSONDecoder().decode(GatewaySecrets.self, from: data)
        {
            secrets = decoded
        }

        let environment = ProcessInfo.processInfo.environment
        if let localKey = environment["LOCAL_GATEWAY_KEY"], !localKey.isEmpty {
            secrets.localGatewayKey = localKey
        }
        if let apiKey = environment["GATEWAY_PROVIDER_API_KEY"], !apiKey.isEmpty {
            secrets.providerSecrets[GatewayConfigurationDefaults.providerID] = GatewayProviderSecret(apiKey: apiKey)
        }
        if let visionKey = environment["VISION_PROVIDER_API_KEY"], !visionKey.isEmpty {
            secrets.visionProviderAPIKey = visionKey
        }

        cachedSecrets = secrets
        cachedSecretsPath = path
        cachedSecretsMTime = mtime
        return secrets
    }

    private func settingsPath() -> String {
        if let configured = ProcessInfo.processInfo.environment["GATEWAY_SETTINGS_PATH"], !configured.isEmpty {
            return NSString(string: configured).expandingTildeInPath
        }
        return "\(NSHomeDirectory())/.config/claude-gateway/proxy_settings.json"
    }

    private func secretsPath() -> String {
        if let configured = ProcessInfo.processInfo.environment["GATEWAY_SECRETS_PATH"], !configured.isEmpty {
            return NSString(string: configured).expandingTildeInPath
        }
        return "\(NSHomeDirectory())/.config/claude-gateway/secrets.json"
    }

    private func fileMTime(_ path: String) -> timespec? {
        var statBuffer = stat()
        return stat(path, &statBuffer) == 0 ? statBuffer.st_mtimespec : nil
    }

    private func cleanString(_ value: String?) -> String? {
        guard let string = value else { return nil }
        let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
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
