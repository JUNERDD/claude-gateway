import Foundation

// MARK: - 代理配置

struct ProxyDiskSettings: Codable {
    var host: String
    var port: Int
    var anthropicBaseURL: String
    var haikuTargetModel: String
    var nonHaikuTargetModel: String
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
        advertisedModels: defaultAdvertisedModels
    )
}

enum ProxySettingsError: LocalizedError {
    case invalidPort
    case emptyField(String)
    case invalidURL
    case emptyModels

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            return "端口必须是 1 到 65535 的数字。"
        case .emptyField(let name):
            return "\(name) 不能为空。"
        case .invalidURL:
            return "DeepSeek Anthropic endpoint 必须是有效的 http 或 https URL。"
        case .emptyModels:
            return "至少需要配置一个 Claude Desktop 可见模型名。"
        }
    }
}
