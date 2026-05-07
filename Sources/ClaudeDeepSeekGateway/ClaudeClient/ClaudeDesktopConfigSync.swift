import Foundation

struct ClaudeConfigSyncReport {
    var updated: [String] = []
    var created: [String] = []
    var unchanged: [String] = []
    var updatedClaudeCodeSettings: [String] = []
    var createdClaudeCodeSettings: [String] = []
    var unchangedClaudeCodeSettings: [String] = []
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

        let configURLs = targetConfigURLs(report: &report)
        if configURLs.isEmpty {
            report.warnings.append("没有发现可同步的 Claude configLibrary 配置文件")
        }

        for url in configURLs {
            do {
                try updateJSONConfig(at: url, gatewayFields: gatewayFields, report: &report)
            } catch {
                report.warnings.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        syncClaudeCodeSettings(settings: settings, localGatewayKey: key, report: &report)
        refreshGatewayModelCache(report: &report)
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

    private static func updateJSONConfig(at url: URL, gatewayFields: [String: Any], report: inout ClaudeConfigSyncReport) throws {
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
