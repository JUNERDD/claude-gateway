import Foundation
import GatewayProxyCore

// MARK: - 代理配置

struct ProxyDiskSettings: Codable {
    var host: String
    var port: Int
    var providers: [GatewayProvider]
    var defaultProviderID: String
    var defaultRoute: GatewayRouteTarget
    var modelRoutes: [GatewayModelRoute]
    var visionProvider: String
    var visionProviderModel: String
    var visionProviderBaseURL: String

    static let defaultModelRoutes = GatewayConfigurationDefaults.modelRoutes

    static let defaults = ProxyDiskSettings(
        host: "127.0.0.1",
        port: 4000,
        providers: [GatewayConfigurationDefaults.provider],
        defaultProviderID: GatewayConfigurationDefaults.providerID,
        defaultRoute: GatewayConfigurationDefaults.routeTarget,
        modelRoutes: defaultModelRoutes,
        visionProvider: "auto",
        visionProviderModel: "",
        visionProviderBaseURL: ""
    )

    static let supportedVisionProviders = [
        "auto",
        "dashscope",
        "gemini",
        "openai-compatible",
    ]

    var advertisedModels: [String] {
        uniqueNonEmpty(modelRoutes.map(\.alias))
    }

    private enum CodingKeys: String, CodingKey {
        case host
        case port
        case providers
        case defaultProviderID
        case defaultRoute
        case modelRoutes
        case visionProvider
        case visionProviderModel
        case visionProviderBaseURL
    }

    init(
        host: String,
        port: Int,
        providers: [GatewayProvider],
        defaultProviderID: String,
        defaultRoute: GatewayRouteTarget,
        modelRoutes: [GatewayModelRoute],
        visionProvider: String,
        visionProviderModel: String,
        visionProviderBaseURL: String
    ) {
        self.host = host
        self.port = port
        self.providers = providers
        self.defaultProviderID = defaultProviderID
        self.defaultRoute = defaultRoute
        self.modelRoutes = modelRoutes
        self.visionProvider = Self.normalizedVisionProvider(visionProvider)
        self.visionProviderModel = visionProviderModel
        self.visionProviderBaseURL = visionProviderBaseURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? Self.defaults.host
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? Self.defaults.port
        let decodedProviders = try container.decodeIfPresent([GatewayProvider].self, forKey: .providers) ?? Self.defaults.providers
        providers = decodedProviders.isEmpty ? Self.defaults.providers : decodedProviders
        defaultProviderID = try container.decodeIfPresent(String.self, forKey: .defaultProviderID) ?? Self.defaults.defaultProviderID
        defaultRoute = try container.decodeIfPresent(GatewayRouteTarget.self, forKey: .defaultRoute) ?? Self.defaults.defaultRoute
        let decodedRoutes = try container.decodeIfPresent([GatewayModelRoute].self, forKey: .modelRoutes) ?? Self.defaultModelRoutes
        modelRoutes = decodedRoutes.isEmpty ? Self.defaultModelRoutes : decodedRoutes
        let decodedVisionProvider = try container.decodeIfPresent(String.self, forKey: .visionProvider) ?? Self.defaults.visionProvider
        visionProvider = Self.normalizedVisionProvider(decodedVisionProvider)
        visionProviderModel = try container.decodeIfPresent(String.self, forKey: .visionProviderModel)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? Self.defaults.visionProviderModel
        visionProviderBaseURL = try container.decodeIfPresent(String.self, forKey: .visionProviderBaseURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? Self.defaults.visionProviderBaseURL
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(providers, forKey: .providers)
        try container.encode(defaultProviderID, forKey: .defaultProviderID)
        try container.encode(defaultRoute, forKey: .defaultRoute)
        try container.encode(modelRoutes, forKey: .modelRoutes)
        try container.encode(visionProvider, forKey: .visionProvider)
        try container.encode(visionProviderModel, forKey: .visionProviderModel)
        try container.encode(visionProviderBaseURL, forKey: .visionProviderBaseURL)
    }

    func provider(id: String) -> GatewayProvider? {
        providers.first { $0.id == id }
    }

    static func normalizedVisionProvider(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return supportedVisionProviders.contains(cleaned) ? cleaned : "auto"
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

enum ProxySettingsError: LocalizedError {
    case invalidPort
    case emptyField(String)
    case invalidURL(String)
    case invalidProviderID(String)
    case invalidProviderAuth(String)
    case invalidProviderHeader(String)
    case invalidVisionProvider
    case invalidVisionProviderBaseURL
    case emptyModels

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            return "端口必须是 1 到 65535 的数字。"
        case .emptyField(let name):
            return "\(name) 不能为空。"
        case .invalidURL(let name):
            return "\(name) 必须是有效的 http 或 https URL。"
        case .invalidProviderID(let id):
            return "Provider ID 无效：\(id)。"
        case .invalidProviderAuth(let provider):
            return "\(provider) 的鉴权方式必须是 x-api-key、bearer、none 或 custom-header。"
        case .invalidProviderHeader(let provider):
            return "\(provider) 的默认 headers 不能覆盖 gateway 管理的 headers。"
        case .invalidVisionProvider:
            return "Vision Provider 必须是 auto、dashscope、gemini 或 openai-compatible。"
        case .invalidVisionProviderBaseURL:
            return "Vision Provider Base URL 必须为空，或是有效的 http/https URL。"
        case .emptyModels:
            return "至少需要配置一个 Claude Desktop 可见模型名。"
        }
    }
}
