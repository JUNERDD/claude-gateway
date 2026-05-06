import AppKit
import Darwin
import SwiftUI

// MARK: - 磁盘日志（完整历史仅在文件；界面只保留尾部以控内存）

final class PersistentLogStore {
    let fileURL: URL
    private let queue = DispatchQueue(label: "local.zen.ClaudeDeepSeekGateway.log")
    private var writeHandle: FileHandle?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent("ClaudeDeepSeekGateway", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700,
        ])
        fileURL = dir.appendingPathComponent("proxy.log")
    }

    var pathForDisplay: String {
        let home = NSHomeDirectory()
        let p = fileURL.path
        if p.hasPrefix(home) {
            return "~" + String(p.dropFirst(home.count))
        }
        return p
    }

    /// 追加写入磁盘（全量持久化）
    func append(_ string: String) {
        guard let data = string.data(using: .utf8), !data.isEmpty else { return }
        queue.async { [self] in
            do {
                try self.ensureWriteHandle()
                try self.writeHandle?.seekToEnd()
                try self.writeHandle?.write(contentsOf: data)
            } catch {
                // 写入失败时避免拖垮主流程，仅忽略（可后续加 OSLog）
            }
        }
    }

    /// 删除日志文件并关闭写句柄（「清空」与之一致）
    func clearPersistentLog(completion: @escaping () -> Void) {
        queue.async { [self] in
            do {
                try self.writeHandle?.close()
            } catch {}
            self.writeHandle = nil
            try? FileManager.default.removeItem(at: self.fileURL)
            DispatchQueue.main.async(execute: completion)
        }
    }

    /// 启动时把文件尾部载入界面（仅展示，不全读大文件）
    func readTail(maxBytes: Int = 512_000, completion: @escaping (String) -> Void) {
        queue.async { [self] in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: self.fileURL.path),
                let size = attrs[.size] as? NSNumber, size.intValue > 0
            else {
                DispatchQueue.main.async { completion("") }
                return
            }
            guard let fh = try? FileHandle(forReadingFrom: self.fileURL) else {
                DispatchQueue.main.async { completion("") }
                return
            }
            defer { try? fh.close() }
            let len = size.intValue
            let readLen = min(len, maxBytes)
            do {
                try fh.seek(toOffset: UInt64(len - readLen))
                let data = try fh.read(upToCount: readLen) ?? Data()
                let s = String(decoding: data, as: UTF8.self)
                DispatchQueue.main.async { completion(s) }
            } catch {
                DispatchQueue.main.async { completion("") }
            }
        }
    }

    private func ensureWriteHandle() throws {
        if writeHandle != nil { return }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        writeHandle = try FileHandle(forWritingTo: fileURL)
        try writeHandle?.seekToEnd()
    }
}

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

struct RuntimeInstallReport {
    var installed: [String] = []
    var created: [String] = []
    var warnings: [String] = []

    var userMessage: String {
        if installed.isEmpty, created.isEmpty, warnings.isEmpty {
            return "运行时已就绪。"
        }

        var parts: [String] = []
        if !installed.isEmpty {
            parts.append("已安装/更新 \(installed.count) 个运行时文件。")
        }
        if !created.isEmpty {
            parts.append("已创建 \(created.count) 个配置文件。")
        }
        if !warnings.isEmpty {
            parts.append("警告：\(warnings.joined(separator: "；"))")
        }
        return parts.joined(separator: " ")
    }
}

enum BundledRuntimeInstaller {
    static var configDirURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-deepseek-gateway", isDirectory: true)
    }

    static var binDirURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("bin", isDirectory: true)
    }

    static var settingsURL: URL {
        configDirURL.appendingPathComponent("proxy_settings.json")
    }

    static var secretsURL: URL {
        configDirURL.appendingPathComponent("secrets.env")
    }

    static var startScriptURL: URL {
        binDirURL.appendingPathComponent("claude-deepseek-gateway-start.sh")
    }

    static func installOrRepair() throws -> RuntimeInstallReport {
        let fm = FileManager.default
        var report = RuntimeInstallReport()

        try fm.createDirectory(at: configDirURL, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700,
        ])
        try fm.createDirectory(at: binDirURL, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o755,
        ])

        guard let runtimeURL = Bundle.main.resourceURL?.appendingPathComponent("Runtime", isDirectory: true),
            fm.fileExists(atPath: runtimeURL.path)
        else {
            report.warnings.append("app bundle 内没有 Runtime 资源；将沿用当前用户目录中的脚本")
            try ensureDefaultSettings(report: &report)
            try ensureSecrets(report: &report)
            return report
        }

        let files: [(String, URL, UInt16)] = [
            ("claude-deepseek-gateway-start.sh", binDirURL.appendingPathComponent("claude-deepseek-gateway-start.sh"), 0o755),
            ("claude-deepseek-gateway-proxy.sh", binDirURL.appendingPathComponent("claude-deepseek-gateway-proxy.sh"), 0o755),
            ("claude-deepseek-gateway-doctor.sh", binDirURL.appendingPathComponent("claude-deepseek-gateway-doctor.sh"), 0o755),
            ("deepseek_anthropic_alias_proxy", configDirURL.appendingPathComponent("deepseek_anthropic_alias_proxy"), 0o755),
        ]

        for (name, destination, permissions) in files {
            let source = runtimeURL.appendingPathComponent(name)
            guard fm.fileExists(atPath: source.path) else {
                report.warnings.append("缺少内置资源 \(name)")
                continue
            }

            if shouldCopy(source: source, destination: destination) {
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: source, to: destination)
                report.installed.append(name)
            }
            try? fm.setAttributes([.posixPermissions: NSNumber(value: permissions)], ofItemAtPath: destination.path)
        }

        try ensureDefaultSettings(report: &report, runtimeURL: runtimeURL)
        try ensureSecrets(report: &report)
        return report
    }

    static func generateLocalGatewayKey() -> String {
        "sk-local-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
    }

    static func hasUsableDeepSeekAPIKey() -> Bool {
        guard let text = try? String(contentsOf: secretsURL, encoding: .utf8) else {
            return false
        }
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("export DEEPSEEK_API_KEY="),
                let equals = line.firstIndex(of: "=")
            else {
                continue
            }
            var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            } else if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            return !value.isEmpty && value != "replace_me"
        }
        return false
    }

    private static func shouldCopy(source: URL, destination: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: destination.path),
            let sourceData = try? Data(contentsOf: source),
            let destinationData = try? Data(contentsOf: destination)
        else {
            return true
        }
        return sourceData != destinationData
    }

    private static func ensureDefaultSettings(report: inout RuntimeInstallReport, runtimeURL: URL? = nil) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: settingsURL.path) else {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
            return
        }

        if let source = runtimeURL?.appendingPathComponent("proxy_settings.default.json"),
            fm.fileExists(atPath: source.path)
        {
            try fm.copyItem(at: source, to: settingsURL)
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(ProxyDiskSettings.defaults)
            try data.write(to: settingsURL, options: .atomic)
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
        report.created.append("proxy_settings.json")
    }

    private static func ensureSecrets(report: inout RuntimeInstallReport) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: secretsURL.path) {
            let contents = """
            # Claude DeepSeek Gateway secrets.
            export DEEPSEEK_API_KEY=""
            export LOCAL_GATEWAY_KEY="\(generateLocalGatewayKey())"

            """
            try Data(contents.utf8).write(to: secretsURL, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretsURL.path)
            report.created.append("secrets.env")
            return
        }

        var text = (try? String(contentsOf: secretsURL, encoding: .utf8)) ?? ""
        var changed = false
        if !text.contains("DEEPSEEK_API_KEY=") {
            text += "\nexport DEEPSEEK_API_KEY=\"\"\n"
            changed = true
        }
        if !text.contains("LOCAL_GATEWAY_KEY=") {
            text += "\nexport LOCAL_GATEWAY_KEY=\"\(generateLocalGatewayKey())\"\n"
            changed = true
        }
        if changed {
            try Data(text.utf8).write(to: secretsURL, options: .atomic)
            report.installed.append("secrets.env")
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretsURL.path)
    }
}

struct ClaudeConfigSyncReport {
    var updated: [String] = []
    var created: [String] = []
    var refreshedCaches: [String] = []
    var warnings: [String] = []

    var userMessage: String {
        var parts: [String] = []
        if !updated.isEmpty {
            parts.append("已同步 \(updated.count) 个 Claude Desktop 配置。")
        }
        if !created.isEmpty {
            parts.append("已创建 \(created.count) 个 Claude configLibrary 配置。")
        }
        if !refreshedCaches.isEmpty {
            parts.append("已刷新 gateway 模型缓存。")
        }
        if !warnings.isEmpty {
            parts.append("警告：\(warnings.joined(separator: "；"))")
        }
        if parts.isEmpty {
            return "未找到可同步的 Claude Desktop 配置。"
        }
        return parts.joined(separator: " ")
    }
}

enum ClaudeDesktopConfigSync {
    private struct ConfigLibraryLocation {
        var appName: String
        var libraryURL: URL
        var canCreate: Bool
    }

    static func syncCurrentDiskConfig() -> ClaudeConfigSyncReport {
        let settings = readDiskSettings()
        let secrets = readSecrets()
        return sync(settings: settings, localGatewayKey: secrets["LOCAL_GATEWAY_KEY"] ?? "")
    }

    static func sync(settings: ProxyDiskSettings, localGatewayKey: String) -> ClaudeConfigSyncReport {
        var report = ClaudeConfigSyncReport()
        let key = localGatewayKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            report.warnings.append("LOCAL_GATEWAY_KEY 为空，无法同步 Claude Desktop 鉴权")
            return report
        }

        let gatewayFields: [String: Any] = [
            "inferenceProvider": "gateway",
            "inferenceGatewayBaseUrl": "http://\(settings.host):\(settings.port)",
            "inferenceGatewayAuthScheme": "bearer",
            "inferenceGatewayApiKey": key,
            "inferenceModels": settings.advertisedModels,
        ]

        for url in targetConfigURLs(report: &report) {
            do {
                try updateJSONConfig(at: url, gatewayFields: gatewayFields)
                report.updated.append(url.path)
            } catch {
                report.warnings.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        refreshGatewayModelCache(report: &report)

        if report.updated.isEmpty, report.created.isEmpty {
            report.warnings.append("没有发现可同步的 Claude configLibrary 配置文件")
        }
        return report
    }

    private static func targetConfigURLs(report: inout ClaudeConfigSyncReport) -> [URL] {
        var result: [URL] = []
        var seen = Set<String>()

        for location in configLibraryLocations() {
            var urls = discoverConfigURLs(in: location.libraryURL)
            if urls.isEmpty, location.canCreate {
                do {
                    let created = try createDefaultConfig(in: location.libraryURL)
                    report.created.append(created.path)
                    urls = [created]
                } catch {
                    report.warnings.append("\(location.appName) configLibrary 创建失败：\(error.localizedDescription)")
                }
            }

            for url in urls {
                let key = url.standardizedFileURL.path
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                result.append(url)
            }
        }

        return result
    }

    private static func configLibraryLocations() -> [ConfigLibraryLocation] {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return [
            ConfigLibraryLocation(
                appName: "Claude-3p",
                libraryURL: appSupport.appendingPathComponent("Claude-3p/configLibrary", isDirectory: true),
                canCreate: true
            ),
            ConfigLibraryLocation(
                appName: "Claude",
                libraryURL: appSupport.appendingPathComponent("Claude/configLibrary", isDirectory: true),
                canCreate: false
            ),
        ]
    }

    private static func discoverConfigURLs(in library: URL) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        func append(_ url: URL) {
            let key = url.standardizedFileURL.path
            guard !seen.contains(key) else { return }
            seen.insert(key)
            urls.append(url)
        }

        let metaURL = library.appendingPathComponent("_meta.json")
        if let meta = readJSONObject(at: metaURL) {
            if let appliedId = safeConfigID(meta["appliedId"] as? String) {
                append(library.appendingPathComponent("\(appliedId).json"))
            }

            if let entries = meta["entries"] as? [[String: Any]] {
                for entry in entries {
                    guard let id = safeConfigID(entry["id"] as? String) else { continue }
                    append(library.appendingPathComponent("\(id).json"))
                }
            }
        }

        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(
            at: library,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for url in files {
            guard isConfigJSONCandidate(url), readJSONObject(at: url) != nil else { continue }
            append(url)
        }

        return urls
    }

    private static func createDefaultConfig(in library: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: library, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700,
        ])

        let metaURL = library.appendingPathComponent("_meta.json")
        var meta = readJSONObject(at: metaURL) ?? [:]
        let id = safeConfigID(meta["appliedId"] as? String)
            ?? UUID().uuidString.lowercased()

        meta["appliedId"] = id
        var entries = meta["entries"] as? [[String: Any]] ?? []
        if !entries.contains(where: { ($0["id"] as? String) == id }) {
            entries.append(["id": id, "name": "Default"])
        }
        meta["entries"] = entries

        try writeJSONObject(meta, to: metaURL)
        return library.appendingPathComponent("\(id).json")
    }

    private static func updateJSONConfig(at url: URL, gatewayFields: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var object: [String: Any] = [:]
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "ClaudeDesktopConfigSync", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "不是 JSON object",
                ])
            }
            object = decoded
        }

        for (key, value) in gatewayFields {
            object[key] = value
        }

        try writeJSONObject(object, to: url)
    }

    private static func refreshGatewayModelCache(report: inout ClaudeConfigSyncReport) {
        let cacheURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/cache/gateway-models.json")
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }

        let backupURL = cacheURL.deletingLastPathComponent()
            .appendingPathComponent("gateway-models.json.bak-\(Int(Date().timeIntervalSince1970))")
        do {
            try FileManager.default.moveItem(at: cacheURL, to: backupURL)
            report.refreshedCaches.append(backupURL.path)
        } catch {
            report.warnings.append("gateway 模型缓存刷新失败：\(error.localizedDescription)")
        }
    }

    private static func readJSONObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func isConfigJSONCandidate(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard url.pathExtension == "json",
            name != "_meta.json",
            !name.hasPrefix("."),
            !name.hasSuffix(".tmp"),
            !name.contains(".bak")
        else {
            return false
        }
        return true
    }

    private static func safeConfigID(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
            !cleaned.contains("/"),
            !cleaned.contains(":"),
            !cleaned.contains("\0")
        else {
            return nil
        }
        return cleaned
    }

    private static func readDiskSettings() -> ProxyDiskSettings {
        guard let data = try? Data(contentsOf: BundledRuntimeInstaller.settingsURL),
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

    private static func readSecrets() -> [String: String] {
        guard let text = try? String(contentsOf: BundledRuntimeInstaller.secretsURL, encoding: .utf8) else {
            return [:]
        }

        var values: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            guard let (key, value) = parseExportLine(String(rawLine)) else { continue }
            values[key] = value
        }
        return values
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
}

enum LaunchAgentManager {
    static let label = "local.zen.ClaudeDeepSeekGateway.proxy"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    private static var domain: String {
        "gui/\(getuid())"
    }

    private static var serviceTarget: String {
        "\(domain)/\(label)"
    }

    private static var logURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("ClaudeDeepSeekGateway/proxy.log")
    }

    static func start() throws -> String {
        try writePlist()
        _ = runLaunchctl(["bootout", serviceTarget])

        let bootstrap = runLaunchctl(["bootstrap", domain, plistURL.path])
        guard bootstrap.exitCode == 0 else {
            throw NSError(domain: "LaunchAgentManager", code: Int(bootstrap.exitCode), userInfo: [
                NSLocalizedDescriptionKey: bootstrap.output.isEmpty ? "launchctl bootstrap 失败" : bootstrap.output,
            ])
        }

        let kickstart = runLaunchctl(["kickstart", "-k", serviceTarget])
        guard kickstart.exitCode == 0 else {
            throw NSError(domain: "LaunchAgentManager", code: Int(kickstart.exitCode), userInfo: [
                NSLocalizedDescriptionKey: kickstart.output.isEmpty ? "launchctl kickstart 失败" : kickstart.output,
            ])
        }

        Thread.sleep(forTimeInterval: 0.6)
        if let pid = runningPID() {
            return "常驻服务已启动 (PID \(pid))。"
        }
        return "常驻服务已交给 launchd 启动。"
    }

    static func stop() -> String {
        let result = runLaunchctl(["bootout", serviceTarget])
        if result.exitCode == 0 {
            return "常驻服务已停止。"
        }
        if result.output.localizedCaseInsensitiveContains("No such process")
            || result.output.localizedCaseInsensitiveContains("not found")
        {
            return "常驻服务未运行。"
        }
        return "停止常驻服务失败：\(result.output)"
    }

    static func runningPID() -> Int32? {
        let result = runLaunchctl(["print", serviceTarget])
        guard result.exitCode == 0 else { return nil }
        for rawLine in result.output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("pid = ") else { continue }
            let value = line.dropFirst("pid = ".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return Int32(value)
        }
        return nil
    }

    private static func writePlist() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700,
        ])

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                "/bin/zsh",
                "-lc",
                "exec \"$HOME/bin/claude-deepseek-gateway-proxy.sh\"",
            ],
            "RunAtLoad": true,
            "KeepAlive": [
                "SuccessfulExit": false,
            ],
            "ThrottleInterval": 10,
            "WorkingDirectory": home,
            "StandardOutPath": logURL.path,
            "StandardErrorPath": logURL.path,
            "EnvironmentVariables": [
                "HOME": home,
                "USER": NSUserName(),
                "PATH": "\(home)/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                "NO_COLOR": "1",
            ],
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plistURL.path)
    }

    private static func runLaunchctl(_ arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (1, error.localizedDescription)
        }

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outData + errData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus, output)
    }
}

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
    }

    func save() {
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
            statusMessage = "已保存。\(syncReport.userMessage) \(serviceMessage)"
            statusIsError = false
        } catch {
            statusMessage = "保存失败：\(error.localizedDescription)"
            statusIsError = true
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

// MARK: - 日志视图桥接

protocol LogViewSinking: AnyObject {
    func appendVisible(_ text: String)
    func clearVisible()
    func replaceVisible(_ text: String)
}

final class LogConsoleCoordinator: NSObject, LogViewSinking {
    weak var textView: NSTextView?
    /// 界面内保留的 UTF-16 长度上限，避免 NSTextStorage 撑爆内存
    private let maxVisibleUTF16 = 450_000

    private static var bodyAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]
    }

    func appendVisible(_ text: String) {
        guard let tv = textView, let storage = tv.textStorage, !text.isEmpty else { return }
        let atBottom = isScrolledNearBottom()
        storage.append(NSAttributedString(string: text, attributes: Self.bodyAttributes))
        trimStorageIfNeeded(storage)
        if atBottom {
            tv.scrollToEndOfDocument(nil)
        }
    }

    func clearVisible() {
        textView?.string = ""
    }

    func replaceVisible(_ text: String) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let attr = NSAttributedString(string: text, attributes: Self.bodyAttributes)
        storage.setAttributedString(attr)
        trimStorageIfNeeded(storage)
        tv.scrollToEndOfDocument(nil)
    }

    private func trimStorageIfNeeded(_ storage: NSTextStorage) {
        let over = storage.length - maxVisibleUTF16
        guard over > 0 else { return }
        storage.deleteCharacters(in: NSRange(location: 0, length: over))
    }

    private func isScrolledNearBottom() -> Bool {
        guard let scroll = textView?.enclosingScrollView,
            let docHeight = scroll.documentView?.bounds.height
        else { return true }
        let visible = scroll.contentView.bounds
        let bottomY = docHeight - visible.maxY
        return bottomY < 120
    }
}

struct LogConsoleView: NSViewRepresentable {
    @ObservedObject var runner: ProxyController

    func makeCoordinator() -> LogConsoleCoordinator {
        LogConsoleCoordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor.textBackgroundColor

        let tv = NSTextView(frame: .zero)
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.drawsBackground = true
        tv.backgroundColor = NSColor.textBackgroundColor
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.textColor = .labelColor
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)

        scroll.documentView = tv
        context.coordinator.textView = tv
        runner.attachLogSink(context.coordinator)

        runner.logStore.readTail { [weak coordinator = context.coordinator] tail in
            guard let c = coordinator else { return }
            if !tail.isEmpty {
                c.replaceVisible(tail)
            }
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        runner.attachLogSink(context.coordinator)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: LogConsoleCoordinator) {
        // sink 由下一次 make 重新绑定
    }
}

// MARK: - Gateway service controller

@MainActor
final class ProxyController: ObservableObject {
    @Published var isRunning: Bool = false

    let logStore = PersistentLogStore()

    private weak var logSink: LogViewSinking?

    func attachLogSink(_ sink: LogViewSinking) {
        logSink = sink
    }

    func clearLog() {
        logStore.clearPersistentLog { [weak self] in
            self?.logSink?.clearVisible()
        }
    }

    private func append(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        logStore.append(chunk)
        logSink?.appendVisible(chunk)
    }

    func refreshStatus() {
        isRunning = LaunchAgentManager.runningPID() != nil
    }

    func start() {
        refreshStatus()

        do {
            let report = try BundledRuntimeInstaller.installOrRepair()
            append("—— 运行时检查：\(report.userMessage) ——\n")
        } catch {
            append("运行时安装/修复失败: \(error.localizedDescription)\n")
        }

        guard BundledRuntimeInstaller.hasUsableDeepSeekAPIKey() else {
            append("错误：未配置 DeepSeek API Key。请打开设置，填入 DEEPSEEK_API_KEY 并保存后再启动。\n")
            return
        }

        do {
            let syncReport = ClaudeDesktopConfigSync.syncCurrentDiskConfig()
            append("—— Claude Desktop 配置：\(syncReport.userMessage) ——\n")
            guard !isRunning else {
                append("—— 常驻服务已在运行 ——\n")
                return
            }
            let message = try LaunchAgentManager.start()
            append("—— \(message) ——\n")
            refreshStatus()
        } catch {
            append("启动失败: \(error.localizedDescription)\n")
        }
    }

    func stop() {
        append("—— 正在停止常驻服务 ——\n")
        append("—— \(LaunchAgentManager.stop()) ——\n")
        refreshStatus()
    }
}

// MARK: - UI

struct ContentView: View {
    @StateObject private var runner = ProxyController()
    @Environment(\.openSettings) private var openSettings
    @State private var didAutoStart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(runner.isRunning ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 9, height: 9)
                        .accessibilityHidden(true)
                    Text(runner.isRunning ? "运行中" : "已停止")
                        .font(.headline)
                    Spacer()
                }

                HStack(spacing: 10) {
                    Button {
                        runner.start()
                    } label: {
                        Label("启动", systemImage: "play.fill")
                    }
                    .disabled(runner.isRunning)
                    .keyboardShortcut("r", modifiers: .command)

                    Button {
                        runner.stop()
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                    }
                    .disabled(!runner.isRunning)

                    Button(role: .destructive) {
                        runner.clearLog()
                    } label: {
                        Label("清空日志", systemImage: "trash")
                    }
                    .help("删除磁盘上的日志文件并清空当前窗口")

                    Spacer()

                    Button {
                        openSettings()
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                    .help("配置 DeepSeek endpoint、模型映射、Claude Desktop 可见模型和密钥")
                }
                .labelStyle(.titleAndIcon)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.regularMaterial)

            Divider()

            LogConsoleView(runner: runner)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            Text("持久化路径：\(runner.logStore.pathForDisplay)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 540)
        .onAppear {
            guard !didAutoStart else { return }
            didAutoStart = true
            runner.refreshStatus()
            if BundledRuntimeInstaller.hasUsableDeepSeekAPIKey() {
                runner.start()
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Runtime") {
                    HStack(spacing: 12) {
                        Image(systemName: settings.runtimeStatusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(settings.runtimeStatusIsError ? .yellow : .green)
                            .accessibilityHidden(true)
                        Text(settings.runtimeStatusMessage.isEmpty ? "运行时状态未知。" : settings.runtimeStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            settings.installBundledRuntime()
                            settings.load()
                        } label: {
                            Label("安装/修复运行时", systemImage: "wrench.and.screwdriver")
                        }
                    }
                    .padding(.vertical, 6)
                }

                GroupBox("Gateway") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Text("监听地址")
                                .gridColumnAlignment(.trailing)
                            TextField("127.0.0.1", text: $settings.host)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("端口")
                            TextField("4000", text: $settings.portText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }
                        GridRow {
                            Text("DeepSeek endpoint")
                            TextField("https://api.deepseek.com/anthropic", text: $settings.anthropicBaseURL)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.vertical, 6)
                }

                GroupBox("Authentication") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Text("DeepSeek API Key")
                                .gridColumnAlignment(.trailing)
                            SecureField("sk-...", text: $settings.deepSeekAPIKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("本地 Gateway Key")
                            HStack(spacing: 8) {
                                SecureField("Claude Desktop 使用这个 bearer key", text: $settings.localGatewayKey)
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    settings.generateLocalGatewayKey()
                                } label: {
                                    Label("生成", systemImage: "key.fill")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }

                GroupBox("Model Mapping") {
                    VStack(alignment: .leading, spacing: 10) {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Haiku 目标")
                                    .gridColumnAlignment(.trailing)
                                TextField("deepseek-v4-flash", text: $settings.haikuTargetModel)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("其他模型目标")
                                TextField("deepseek-v4-pro[1m]", text: $settings.nonHaikuTargetModel)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        Text("请求模型名只要包含 haiku 就转到 Haiku 目标；其他所有模型都转到其他模型目标。请求体其余字段保持透传。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                GroupBox("Claude Desktop Models") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("每行一个 Claude Desktop 可见模型名。这里决定 /v1/models 返回值，也就是菜单里能看到的 Models。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $settings.advertisedModelsText)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 110)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                        HStack {
                            Button {
                                settings.resetModelDefaults()
                            } label: {
                                Label("恢复默认模型", systemImage: "arrow.counterclockwise")
                            }
                            Spacer()
                        }
                    }
                    .padding(.vertical, 6)
                }

                GroupBox("Claude Desktop Config") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(settings.claudeConfigSnippet)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(settings.claudeConfigSnippet, forType: .string)
                        } label: {
                            Label("复制配置片段", systemImage: "doc.on.doc")
                        }
                    }
                    .padding(.vertical, 6)
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("配置：\(settings.configPathForDisplay)")
                        Text("密钥：\(settings.secretsPathForDisplay)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                    Spacer()

                    Button {
                        settings.load()
                    } label: {
                        Label("重新载入", systemImage: "arrow.clockwise")
                    }

                    Button {
                        settings.save()
                    } label: {
                        Label("保存配置", systemImage: "square.and.arrow.down")
                    }
                    .keyboardShortcut(.defaultAction)
                }

                if !settings.statusMessage.isEmpty {
                    Text(settings.statusMessage)
                        .font(.caption)
                        .foregroundStyle(settings.statusIsError ? .red : .secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(20)
        }
        .frame(width: 760, height: 720)
    }
}

@main
struct ClaudeDeepSeekGatewayApp: App {
    @StateObject private var proxySettings = ProxySettingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 880, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView(settings: proxySettings)
        }
    }
}
