import Foundation

// MARK: - 代理配置

struct ProxyDiskSettings: Codable {
    var host: String
    var port: Int
    var anthropicBaseURL: String
    var haikuTargetModel: String
    var nonHaikuTargetModel: String
    var visionProvider: String
    var visionProviderModel: String
    var visionProviderBaseURL: String
    var advertisedModels: [String]

    static let defaultAdvertisedModels = [
        "claude-opus-4-7",
        "claude-sonnet-4-6",
        "claude-haiku-4-5",
    ]

    static let defaults = ProxyDiskSettings(
        host: "127.0.0.1",
        port: 4000,
        anthropicBaseURL: "https://api.deepseek.com/anthropic",
        haikuTargetModel: "deepseek-v4-flash",
        nonHaikuTargetModel: "deepseek-v4-pro[1m]",
        visionProvider: "auto",
        visionProviderModel: "",
        visionProviderBaseURL: "",
        advertisedModels: defaultAdvertisedModels
    )

    static let supportedVisionProviders = [
        "auto",
        "dashscope",
        "gemini",
        "openai-compatible",
    ]

    init(
        host: String,
        port: Int,
        anthropicBaseURL: String,
        haikuTargetModel: String,
        nonHaikuTargetModel: String,
        visionProvider: String,
        visionProviderModel: String,
        visionProviderBaseURL: String,
        advertisedModels: [String]
    ) {
        self.host = host
        self.port = port
        self.anthropicBaseURL = anthropicBaseURL
        self.haikuTargetModel = haikuTargetModel
        self.nonHaikuTargetModel = nonHaikuTargetModel
        self.visionProvider = Self.normalizedVisionProvider(visionProvider)
        self.visionProviderModel = visionProviderModel
        self.visionProviderBaseURL = visionProviderBaseURL
        self.advertisedModels = advertisedModels
    }

    private enum CodingKeys: String, CodingKey {
        case host
        case port
        case anthropicBaseURL
        case haikuTargetModel
        case nonHaikuTargetModel
        case visionProvider
        case visionProviderModel
        case visionProviderBaseURL
        case advertisedModels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? Self.defaults.host
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? Self.defaults.port
        anthropicBaseURL = try container.decodeIfPresent(String.self, forKey: .anthropicBaseURL) ?? Self.defaults.anthropicBaseURL
        haikuTargetModel = try container.decodeIfPresent(String.self, forKey: .haikuTargetModel) ?? Self.defaults.haikuTargetModel
        nonHaikuTargetModel = try container.decodeIfPresent(String.self, forKey: .nonHaikuTargetModel) ?? Self.defaults.nonHaikuTargetModel
        let decodedProvider = try container.decodeIfPresent(String.self, forKey: .visionProvider) ?? Self.defaults.visionProvider
        visionProvider = Self.normalizedVisionProvider(decodedProvider)
        visionProviderModel = try container.decodeIfPresent(String.self, forKey: .visionProviderModel)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? Self.defaults.visionProviderModel
        visionProviderBaseURL = try container.decodeIfPresent(String.self, forKey: .visionProviderBaseURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? Self.defaults.visionProviderBaseURL
        advertisedModels = try container.decodeIfPresent([String].self, forKey: .advertisedModels) ?? Self.defaultAdvertisedModels
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(anthropicBaseURL, forKey: .anthropicBaseURL)
        try container.encode(haikuTargetModel, forKey: .haikuTargetModel)
        try container.encode(nonHaikuTargetModel, forKey: .nonHaikuTargetModel)
        try container.encode(visionProvider, forKey: .visionProvider)
        try container.encode(visionProviderModel, forKey: .visionProviderModel)
        try container.encode(visionProviderBaseURL, forKey: .visionProviderBaseURL)
        try container.encode(advertisedModels, forKey: .advertisedModels)
    }

    static func normalizedVisionProvider(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return supportedVisionProviders.contains(cleaned) ? cleaned : "auto"
    }
}

enum ProxySettingsError: LocalizedError {
    case invalidPort
    case emptyField(String)
    case invalidURL
    case invalidVisionProvider
    case invalidVisionProviderBaseURL
    case emptyModels

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            return "端口必须是 1 到 65535 的数字。"
        case .emptyField(let name):
            return "\(name) 不能为空。"
        case .invalidURL:
            return "DeepSeek Anthropic endpoint 必须是有效的 http 或 https URL。"
        case .invalidVisionProvider:
            return "Vision Provider 必须是 auto、dashscope、gemini 或 openai-compatible。"
        case .invalidVisionProviderBaseURL:
            return "Vision Provider Base URL 必须为空，或是有效的 http/https URL。"
        case .emptyModels:
            return "至少需要配置一个 Claude Desktop 可见模型名。"
        }
    }
}
