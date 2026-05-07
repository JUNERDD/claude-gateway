import Foundation

struct ClaudeConfigSyncReport {
    var updated: [String] = []
    var created: [String] = []
    var unchanged: [String] = []
    var updatedClaudeCodeSettings: [String] = []
    var createdClaudeCodeSettings: [String] = []
    var unchangedClaudeCodeSettings: [String] = []
    var installedClaudeMCPServers: [String] = []
    var unchangedClaudeMCPServers: [String] = []
    var backups: [String] = []
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
        if !unchanged.isEmpty, updated.isEmpty, created.isEmpty {
            parts.append("\(unchanged.count) 个 Claude Desktop 配置已匹配。")
        }
        if !updatedClaudeCodeSettings.isEmpty || !createdClaudeCodeSettings.isEmpty {
            parts.append("已同步 Claude Code 配置。")
        } else if !unchangedClaudeCodeSettings.isEmpty, updated.isEmpty, created.isEmpty, refreshedCaches.isEmpty {
            parts.append("Claude Code 配置已匹配。")
        }
        if !installedClaudeMCPServers.isEmpty {
            parts.append("已同步 \(installedClaudeMCPServers.count) 个 Claude MCP Server。")
        } else if !unchangedClaudeMCPServers.isEmpty,
            updated.isEmpty,
            created.isEmpty,
            updatedClaudeCodeSettings.isEmpty,
            createdClaudeCodeSettings.isEmpty,
            refreshedCaches.isEmpty
        {
            parts.append("\(unchangedClaudeMCPServers.count) 个 Claude MCP Server 已匹配。")
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

    var detailMessage: String {
        var lines: [String] = []
        lines.append(userMessage)
        appendSection("已更新", updated, to: &lines)
        appendSection("已创建", created, to: &lines)
        appendSection("已匹配", unchanged, to: &lines)
        appendSection("Claude Code 已更新", updatedClaudeCodeSettings, to: &lines)
        appendSection("Claude Code 已创建", createdClaudeCodeSettings, to: &lines)
        appendSection("Claude Code 已匹配", unchangedClaudeCodeSettings, to: &lines)
        appendSection("Claude MCP Server 已同步", installedClaudeMCPServers, to: &lines)
        appendSection("Claude MCP Server 已匹配", unchangedClaudeMCPServers, to: &lines)
        appendSection("备份", backups, to: &lines)
        appendSection("缓存备份", refreshedCaches, to: &lines)
        appendSection("警告", warnings, to: &lines)
        return lines.joined(separator: "\n")
    }

    private func appendSection(_ title: String, _ values: [String], to lines: inout [String]) {
        guard !values.isEmpty else { return }
        lines.append("\(title):")
        for value in values {
            lines.append("  \(value)")
        }
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
        syncBundledClaudeMCPServers(report: &report)

        let key = localGatewayKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            report.warnings.append("LOCAL_GATEWAY_KEY 为空，无法同步 Claude 客户端鉴权")
            return report
        }

        let gatewayFields: [String: Any] = [
            "inferenceProvider": "gateway",
            "inferenceGatewayBaseUrl": "http://\(settings.host):\(settings.port)",
            "inferenceGatewayAuthScheme": "bearer",
            "inferenceGatewayApiKey": key,
            "inferenceModels": settings.advertisedModels,
        ]
        let mcpServerConfig = visionMCPServerConfig(settings: settings, localGatewayKey: key)

        let configURLs = targetConfigURLs(report: &report)
        if configURLs.isEmpty {
            report.warnings.append("没有发现可同步的 Claude configLibrary 配置文件")
        }

        for url in configURLs {
            do {
                try updateJSONConfig(
                    at: url,
                    gatewayFields: gatewayFields,
                    mcpServerConfig: mcpServerConfig,
                    report: &report
                )
            } catch {
                report.warnings.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        syncClaudeCodeSettings(settings: settings, localGatewayKey: key, report: &report)
        refreshGatewayModelCache(report: &report)
        return report
    }

    static func syncBundledClaudeMCPServers(report: inout ClaudeConfigSyncReport) {
        syncBundledClaudeMCPServers(
            sourceRoot: bundledClaudeMCPServersSourceURL(),
            destinationRoot: claudeMCPServersDestinationRoot(),
            report: &report
        )
    }

    static func syncBundledClaudeMCPServers(
        sourceRoot: URL?,
        destinationRoot: URL,
        report: inout ClaudeConfigSyncReport
    ) {
        let fm = FileManager.default
        guard let sourceRoot else {
            report.warnings.append("未找到内置 Claude MCP Servers 源目录")
            return
        }

        let serverSources: [URL]
        do {
            serverSources = try fm.contentsOfDirectory(
                at: sourceRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                guard values?.isDirectory == true else {
                    return false
                }
                return fm.fileExists(atPath: url.appendingPathComponent("server.py").path)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            report.warnings.append("Claude MCP Servers 源目录读取失败：\(error.localizedDescription)")
            return
        }

        guard !serverSources.isEmpty else {
            report.warnings.append("Claude MCP Servers 源目录没有可同步的 server.py：\(sourceRoot.path)")
            return
        }

        do {
            try fm.createDirectory(
                at: destinationRoot,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            report.warnings.append("Claude MCP Servers 目录创建失败：\(error.localizedDescription)")
            return
        }

        for sourceURL in serverSources {
            do {
                try syncClaudeMCPServer(sourceURL: sourceURL, destinationRoot: destinationRoot, report: &report)
            } catch {
                report.warnings.append("Claude MCP Server \(sourceURL.lastPathComponent) 同步失败：\(error.localizedDescription)")
            }
        }
    }

    private static func syncClaudeMCPServer(
        sourceURL: URL,
        destinationRoot: URL,
        report: inout ClaudeConfigSyncReport
    ) throws {
        let fm = FileManager.default
        let sourcePath = sourceURL.standardizedFileURL.path
        let destinationURL = destinationRoot.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)

        if let linkedPath = try? fm.destinationOfSymbolicLink(atPath: destinationURL.path) {
            let linkedURL = resolvedSymbolicLinkDestination(
                linkedPath,
                relativeTo: destinationURL.deletingLastPathComponent()
            )
            if linkedURL.standardizedFileURL.path == sourcePath {
                report.unchangedClaudeMCPServers.append("\(destinationURL.path) -> \(sourcePath)")
                return
            }
            try fm.removeItem(at: destinationURL)
        } else {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory) {
                let backupURL = backupURL(for: destinationURL)
                try fm.moveItem(at: destinationURL, to: backupURL)
                report.backups.append(backupURL.path)
            }
        }

        try fm.createSymbolicLink(atPath: destinationURL.path, withDestinationPath: sourcePath)
        report.installedClaudeMCPServers.append("\(destinationURL.path) -> \(sourcePath)")
    }

    private static func bundledClaudeMCPServersSourceURL() -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["CLAUDE_DEEPSEEK_GATEWAY_CLAUDE_MCP_SOURCE"],
            !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            candidates.append(URL(fileURLWithPath: expandTilde(override), isDirectory: true))
        }
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("ClaudeMCPServers", isDirectory: true))
        }
        candidates.append(
            URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("Resources/ClaudeMCPServers", isDirectory: true)
        )

        for candidate in candidates {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }

    private static func claudeMCPServersDestinationRoot() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["CLAUDE_DEEPSEEK_GATEWAY_CLAUDE_MCP_DESTINATION"],
            !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return URL(fileURLWithPath: expandTilde(override), isDirectory: true)
        }
        if let claudeHome = environment["CLAUDE_DEEPSEEK_GATEWAY_CLAUDE_HOME"],
            !claudeHome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return URL(fileURLWithPath: expandTilde(claudeHome), isDirectory: true)
                .appendingPathComponent("mcp", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/mcp", isDirectory: true)
    }

    private static func resolvedSymbolicLinkDestination(_ path: String, relativeTo directory: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return directory.appendingPathComponent(path)
    }

    private static func expandTilde(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
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

    private static func updateJSONConfig(
        at url: URL,
        gatewayFields: [String: Any],
        mcpServerConfig: [String: Any]?,
        report: inout ClaudeConfigSyncReport
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var object: [String: Any] = [:]
        var originalObject: [String: Any] = [:]
        let existed = FileManager.default.fileExists(atPath: url.path)
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "ClaudeDesktopConfigSync", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "不是 JSON object",
                ])
            }
            object = decoded
            originalObject = decoded
        }

        for (key, value) in gatewayFields {
            object[key] = value
        }
        if let mcpServerConfig {
            try mergeVisionMCPServerConfig(mcpServerConfig, into: &object)
        }

        if existed, try jsonData(object) == jsonData(originalObject) {
            report.unchanged.append(url.path)
            return
        }

        if existed {
            let backupURL = backupURL(for: url)
            try FileManager.default.copyItem(at: url, to: backupURL)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
            report.backups.append(backupURL.path)
        }

        try writeJSONObject(object, to: url)
        report.updated.append(url.path)
    }

    private static func mergeVisionMCPServerConfig(_ serverConfig: [String: Any], into object: inout [String: Any]) throws {
        guard object["mcpServers"] == nil || object["mcpServers"] is [String: Any] else {
            throw NSError(domain: "ClaudeDesktopConfigSync", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "mcpServers 不是 JSON object",
            ])
        }
        var mcpServers = object["mcpServers"] as? [String: Any] ?? [:]
        mcpServers["vision-provider"] = serverConfig
        object["mcpServers"] = mcpServers
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

    private static func visionMCPServerConfig(settings: ProxyDiskSettings, localGatewayKey: String) -> [String: Any]? {
        let serverURL = claudeMCPServersDestinationRoot()
            .appendingPathComponent("vision-provider", isDirectory: true)
            .appendingPathComponent("server.py")
        guard FileManager.default.fileExists(atPath: serverURL.path) else {
            return nil
        }
        return [
            "type": "stdio",
            "command": "python3",
            "args": [serverURL.path],
            "env": [
                "CLAUDE_DEEPSEEK_GATEWAY_URL": "http://\(settings.host):\(settings.port)",
                "LOCAL_GATEWAY_KEY": localGatewayKey,
            ],
        ]
    }

    private static func syncClaudeCodeSettings(settings: ProxyDiskSettings, localGatewayKey: String, report: inout ClaudeConfigSyncReport) {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        let existed = FileManager.default.fileExists(atPath: settingsURL.path)

        do {
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )

            var object: [String: Any] = [:]
            var originalObject: [String: Any] = [:]
            if existed, let data = try? Data(contentsOf: settingsURL), !data.isEmpty {
                guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    report.warnings.append("Claude Code settings.json 不是 JSON object")
                    return
                }
                object = decoded
                originalObject = decoded
            }

            guard object["env"] == nil || object["env"] is [String: Any] else {
                report.warnings.append("Claude Code settings.json 的 env 不是 JSON object")
                return
            }

            var env = object["env"] as? [String: Any] ?? [:]
            env["ANTHROPIC_BASE_URL"] = "http://\(settings.host):\(settings.port)"
            env["ANTHROPIC_AUTH_TOKEN"] = localGatewayKey
            if (env["API_TIMEOUT_MS"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                env["API_TIMEOUT_MS"] = "3000000"
            }
            object["env"] = env

            if let mcpServerConfig = visionMCPServerConfig(settings: settings, localGatewayKey: localGatewayKey) {
                try mergeVisionMCPServerConfig(mcpServerConfig, into: &object)
                try syncClaudeCodeUserMCPConfig(
                    at: claudeCodeUserConfigURL(),
                    mcpServerConfig: mcpServerConfig,
                    report: &report
                )
            }

            if let model = object["model"] as? String,
                let normalizedModel = normalizedClaudeCodeModel(model)
            {
                object["model"] = normalizedModel
            } else if (object["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                object["model"] = "opus"
            }

            if existed, try jsonData(object) == jsonData(originalObject) {
                report.unchangedClaudeCodeSettings.append(settingsURL.path)
                return
            }

            if existed {
                let backupURL = backupURL(for: settingsURL)
                try FileManager.default.copyItem(at: settingsURL, to: backupURL)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
                report.backups.append(backupURL.path)
            }

            try writeJSONObject(object, to: settingsURL)
            if existed {
                report.updatedClaudeCodeSettings.append(settingsURL.path)
            } else {
                report.createdClaudeCodeSettings.append(settingsURL.path)
            }
        } catch {
            report.warnings.append("Claude Code settings.json 同步失败：\(error.localizedDescription)")
        }
    }

    static func syncClaudeCodeUserMCPConfig(
        at url: URL,
        mcpServerConfig: [String: Any],
        report: inout ClaudeConfigSyncReport
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var object: [String: Any] = [:]
        var originalObject: [String: Any] = [:]
        let existed = FileManager.default.fileExists(atPath: url.path)
        if existed, let data = try? Data(contentsOf: url), !data.isEmpty {
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "ClaudeDesktopConfigSync", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "\(url.lastPathComponent) 不是 JSON object",
                ])
            }
            object = decoded
            originalObject = decoded
        }

        try mergeVisionMCPServerConfig(mcpServerConfig, into: &object)

        if existed, try jsonData(object) == jsonData(originalObject) {
            report.unchangedClaudeCodeSettings.append(url.path)
            return
        }

        if existed {
            let backupURL = backupURL(for: url)
            try FileManager.default.copyItem(at: url, to: backupURL)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
            report.backups.append(backupURL.path)
        }

        try writeJSONObject(object, to: url)
        if existed {
            report.updatedClaudeCodeSettings.append(url.path)
        } else {
            report.createdClaudeCodeSettings.append(url.path)
        }
    }

    private static func claudeCodeUserConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
    }

    private static func normalizedClaudeCodeModel(_ model: String) -> String? {
        switch model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "opus[1m]":
            return "opus"
        case "sonnet[1m]":
            return "sonnet"
        case "haiku[1m]":
            return "haiku"
        default:
            return nil
        }
    }

    private static func backupURL(for url: URL) -> URL {
        let directory = url.deletingLastPathComponent()
        let baseName = "\(url.lastPathComponent).bak-\(Int(Date().timeIntervalSince1970))"
        var candidate = directory.appendingPathComponent(baseName)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(counter)")
            counter += 1
        }
        return candidate
    }

    private static func readJSONObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try jsonData(object)
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
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
            visionProvider: decoded.visionProvider,
            visionProviderModel: decoded.visionProviderModel.trimmingCharacters(in: .whitespacesAndNewlines),
            visionProviderBaseURL: decoded.visionProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
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
