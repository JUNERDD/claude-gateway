import Foundation

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

    static func runtimeLooksInstalled() -> Bool {
        let fm = FileManager.default
        let requiredFiles = [
            startScriptURL.path,
            binDirURL.appendingPathComponent("claude-deepseek-gateway-proxy.sh").path,
            binDirURL.appendingPathComponent("claude-deepseek-gateway-doctor.sh").path,
            configDirURL.appendingPathComponent("deepseek_anthropic_alias_proxy").path,
            settingsURL.path,
            secretsURL.path,
        ]
        return requiredFiles.allSatisfy { fm.fileExists(atPath: $0) }
            && fm.isExecutableFile(atPath: startScriptURL.path)
            && fm.isExecutableFile(atPath: binDirURL.appendingPathComponent("claude-deepseek-gateway-proxy.sh").path)
            && fm.isExecutableFile(atPath: binDirURL.appendingPathComponent("claude-deepseek-gateway-doctor.sh").path)
            && fm.isExecutableFile(atPath: configDirURL.appendingPathComponent("deepseek_anthropic_alias_proxy").path)
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
        let fm = FileManager.default
        guard fm.fileExists(atPath: destination.path),
            let sourceSize = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            let destinationSize = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            sourceSize == destinationSize
        else { return true }

        guard let sourceHandle = try? FileHandle(forReadingFrom: source),
            let destinationHandle = try? FileHandle(forReadingFrom: destination)
        else { return true }
        defer {
            try? sourceHandle.close()
            try? destinationHandle.close()
        }

        let chunkSize = 256 * 1024
        while true {
            let sourceData = (try? sourceHandle.read(upToCount: chunkSize)) ?? Data()
            let destinationData = (try? destinationHandle.read(upToCount: chunkSize)) ?? Data()
            if sourceData != destinationData { return true }
            if sourceData.isEmpty { return false }
        }
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
            export VISION_PROVIDER_API_KEY=""
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
        if !text.contains("VISION_PROVIDER_API_KEY=") {
            text += "\nexport VISION_PROVIDER_API_KEY=\"\"\n"
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
