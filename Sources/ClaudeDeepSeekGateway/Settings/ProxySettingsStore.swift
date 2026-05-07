import Foundation
import SwiftUI

final class ProxySettingsStore: ObservableObject {
    @Published var host: String = ProxyDiskSettings.defaults.host
    @Published var portText: String = String(ProxyDiskSettings.defaults.port)
    @Published var anthropicBaseURL: String = ProxyDiskSettings.defaults.anthropicBaseURL
    @Published var haikuTargetModel: String = ProxyDiskSettings.defaults.haikuTargetModel
    @Published var nonHaikuTargetModel: String = ProxyDiskSettings.defaults.nonHaikuTargetModel
    @Published var advertisedModelsText: String = ProxyDiskSettings.defaultAdvertisedModels.joined(separator: "\n")
    @Published var deepSeekAPIKey: String = ""
    @Published var localGatewayKey: String = ""
    @Published var statusMessage: String = ""
    @Published var statusIsError: Bool = false
    @Published var runtimeStatusMessage: String = ""
    @Published var runtimeStatusIsError: Bool = false
    @Published var claudeSyncStatusMessage: String = ""
    @Published var claudeSyncStatusIsError: Bool = false

    private let configURL: URL
    private let secretsURL: URL

    init() {
        configURL = BundledRuntimeInstaller.settingsURL
        secretsURL = BundledRuntimeInstaller.secretsURL
        installBundledRuntime()
        load()
    }

    var configPathForDisplay: String {
        abbreviateHome(configURL.path)
    }

    var secretsPathForDisplay: String {
        abbreviateHome(secretsURL.path)
    }

    var advertisedModels: [String] {
        uniqueNonEmptyLines(advertisedModelsText)
    }

    var claudeConfigSnippet: String {
        let payload: [String: Any] = [
            "inferenceProvider": "gateway",
            "inferenceGatewayBaseUrl": "http://\(hostTrimmed):\(portText.trimmingCharacters(in: .whitespacesAndNewlines))",
            "inferenceGatewayAuthScheme": "bearer",
            "inferenceGatewayApiKey": localGatewayKey,
            "inferenceModels": advertisedModels,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }

    func load() {
        let disk = readDiskSettings()
        host = disk.host
        portText = String(disk.port)
        anthropicBaseURL = disk.anthropicBaseURL
        haikuTargetModel = disk.haikuTargetModel
        nonHaikuTargetModel = disk.nonHaikuTargetModel
        advertisedModelsText = disk.advertisedModels.joined(separator: "\n")

        let secrets = readSecrets()
        let deepSeekKey = secrets["DEEPSEEK_API_KEY"] ?? ""
        deepSeekAPIKey = deepSeekKey == "replace_me" ? "" : deepSeekKey
        localGatewayKey = secrets["LOCAL_GATEWAY_KEY"] ?? BundledRuntimeInstaller.generateLocalGatewayKey()
        statusMessage = ""
        statusIsError = false
        claudeSyncStatusMessage = ""
        claudeSyncStatusIsError = false
    }

    func save() {
        persistSettingsAndSync(successPrefix: "已保存。")
    }

    func syncClaudeDesktopConfig() {
        persistSettingsAndSync(successPrefix: "已同步 Claude Desktop 配置。")
    }

    func dismissStatusMessage() {
        statusMessage = ""
        statusIsError = false
    }

    private func persistSettingsAndSync(successPrefix: String) {
        do {
            if localGatewayKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                localGatewayKey = BundledRuntimeInstaller.generateLocalGatewayKey()
            }
            guard !deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProxySettingsError.emptyField("DeepSeek API Key")
            }
            let settings = try validatedDiskSettings()
            try ensureConfigDirectory()

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: configURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)

            let secrets = """
            # Claude DeepSeek Gateway secrets.
            export DEEPSEEK_API_KEY="\(Self.shellDoubleQuoted(deepSeekAPIKey))"
            export LOCAL_GATEWAY_KEY="\(Self.shellDoubleQuoted(localGatewayKey))"

            """
            try Data(secrets.utf8).write(to: secretsURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretsURL.path)

            let syncReport = ClaudeDesktopConfigSync.sync(settings: settings, localGatewayKey: localGatewayKey)
            let serviceMessage = try LaunchAgentManager.start()
            statusMessage = "\(successPrefix)\(syncReport.userMessage) \(serviceMessage)"
            statusIsError = false
            claudeSyncStatusMessage = "\(syncReport.detailMessage)\nLaunchAgent:\n  \(serviceMessage)"
            claudeSyncStatusIsError = !syncReport.warnings.isEmpty
        } catch {
            statusMessage = "操作失败：\(error.localizedDescription)"
            statusIsError = true
            claudeSyncStatusMessage = statusMessage
            claudeSyncStatusIsError = true
        }
    }

    func installBundledRuntime() {
        do {
            let report = try BundledRuntimeInstaller.installOrRepair()
            runtimeStatusMessage = report.userMessage
            runtimeStatusIsError = !report.warnings.isEmpty
        } catch {
            runtimeStatusMessage = "运行时安装失败：\(error.localizedDescription)"
            runtimeStatusIsError = true
        }
    }

    func resetModelDefaults() {
        advertisedModelsText = ProxyDiskSettings.defaultAdvertisedModels.joined(separator: "\n")
        haikuTargetModel = ProxyDiskSettings.defaults.haikuTargetModel
        nonHaikuTargetModel = ProxyDiskSettings.defaults.nonHaikuTargetModel
    }

    func generateLocalGatewayKey() {
        localGatewayKey = BundledRuntimeInstaller.generateLocalGatewayKey()
    }

    private var hostTrimmed: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validatedDiskSettings() throws -> ProxyDiskSettings {
        let cleanHost = hostTrimmed
        guard !cleanHost.isEmpty else { throw ProxySettingsError.emptyField("监听地址") }

        let cleanBaseURL = anthropicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleanBaseURL.isEmpty else { throw ProxySettingsError.emptyField("DeepSeek Anthropic endpoint") }
        guard let url = URL(string: cleanBaseURL),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            url.host != nil
        else {
            throw ProxySettingsError.invalidURL
        }

        guard let port = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)),
            (1...65535).contains(port)
        else {
            throw ProxySettingsError.invalidPort
        }

        let haikuTarget = haikuTargetModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let otherTarget = nonHaikuTargetModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !haikuTarget.isEmpty else { throw ProxySettingsError.emptyField("Haiku 目标模型") }
        guard !otherTarget.isEmpty else { throw ProxySettingsError.emptyField("非 Haiku 目标模型") }

        let models = advertisedModels
        guard !models.isEmpty else { throw ProxySettingsError.emptyModels }

        return ProxyDiskSettings(
            host: cleanHost,
            port: port,
            anthropicBaseURL: cleanBaseURL,
            haikuTargetModel: haikuTarget,
            nonHaikuTargetModel: otherTarget,
            advertisedModels: models
        )
    }

    private func readDiskSettings() -> ProxyDiskSettings {
        guard let data = try? Data(contentsOf: configURL),
            let decoded = try? JSONDecoder().decode(ProxyDiskSettings.self, from: data)
        else {
            return .defaults
        }
        return ProxyDiskSettings(
            host: decoded.host.isEmpty ? ProxyDiskSettings.defaults.host : decoded.host,
            port: decoded.port,
            anthropicBaseURL: decoded.anthropicBaseURL.isEmpty ? ProxyDiskSettings.defaults.anthropicBaseURL : decoded.anthropicBaseURL,
            haikuTargetModel: decoded.haikuTargetModel.isEmpty ? ProxyDiskSettings.defaults.haikuTargetModel : decoded.haikuTargetModel,
            nonHaikuTargetModel: decoded.nonHaikuTargetModel.isEmpty ? ProxyDiskSettings.defaults.nonHaikuTargetModel : decoded.nonHaikuTargetModel,
            advertisedModels: decoded.advertisedModels.isEmpty ? ProxyDiskSettings.defaultAdvertisedModels : decoded.advertisedModels
        )
    }

    private func readSecrets() -> [String: String] {
        guard let text = try? String(contentsOf: secretsURL, encoding: .utf8) else {
            return [:]
        }
        var values: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            guard let (key, value) = Self.parseExportLine(String(rawLine)) else { continue }
            values[key] = value
        }
        return values
    }

    private func ensureConfigDirectory() throws {
        let dir = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700,
        ])
    }

    private func uniqueNonEmptyLines(_ text: String) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private func abbreviateHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    private static func parseExportLine(_ line: String) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("export ") else { return nil }
        let rest = trimmed.dropFirst("export ".count)
        guard let equals = rest.firstIndex(of: "=") else { return nil }
        let key = String(rest[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
        var value = String(rest[rest.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
            value = unescapeDoubleQuoted(value)
        } else if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return key.isEmpty ? nil : (key, value)
    }

    private static func unescapeDoubleQuoted(_ value: String) -> String {
        var result = ""
        var escaping = false
        for ch in value {
            if escaping {
                result.append(ch)
                escaping = false
            } else if ch == "\\" {
                escaping = true
            } else {
                result.append(ch)
            }
        }
        if escaping {
            result.append("\\")
        }
        return result
    }

    private static func shellDoubleQuoted(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "\n", with: "")
    }
}
