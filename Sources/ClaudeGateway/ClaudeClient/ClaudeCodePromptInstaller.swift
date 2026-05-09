import Foundation
import GatewayProxyCore

struct ClaudeCodePromptInstallResult: Equatable {
    enum Status: Equatable {
        case created
        case updated
        case unchanged
    }

    var status: Status
    var path: String
    var displayPath: String
    var backupPath: String?
    var command: String
}

enum ClaudeCodePromptInstaller {
    static func install(
        provider: GatewayProvider?,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) throws -> ClaudeCodePromptInstallResult? {
        guard let provider,
            provider.claudeCode.appendSystemPromptEnabled,
            !provider.claudeCode.appendSystemPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let configuredPath = provider.claudeCode.appendSystemPromptPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayPath = configuredPath.isEmpty
            ? GatewayProviderClaudeCodeSettings.defaultAppendSystemPromptPath
            : configuredPath
        let url = expandedURL(for: displayPath, homeURL: homeURL)
        let bytes = Data(normalizedPromptText(provider.claudeCode.appendSystemPromptText).utf8)
        let existed = fileManager.fileExists(atPath: url.path)

        if existed, let existingBytes = try? Data(contentsOf: url), existingBytes == bytes {
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return ClaudeCodePromptInstallResult(
                status: .unchanged,
                path: url.path,
                displayPath: displayPath,
                backupPath: nil,
                command: appendPromptCommand(displayPath: displayPath)
            )
        }

        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var backupPath: String?
        if existed {
            let backupURL = backupURL(for: url, fileManager: fileManager)
            try fileManager.copyItem(at: url, to: backupURL)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
            backupPath = backupURL.path
        }

        try bytes.write(to: url, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        return ClaudeCodePromptInstallResult(
            status: existed ? .updated : .created,
            path: url.path,
            displayPath: displayPath,
            backupPath: backupPath,
            command: appendPromptCommand(displayPath: displayPath)
        )
    }

    static func appendPromptCommand(displayPath: String = GatewayProviderClaudeCodeSettings.defaultAppendSystemPromptPath) -> String {
        "claude --append-system-prompt-file \(shellQuoted(displayPath))"
    }

    private static func normalizedPromptText(_ text: String) -> String {
        text.hasSuffix("\n") ? text : text + "\n"
    }

    private static func expandedURL(for path: String, homeURL: URL) -> URL {
        if path == "~" {
            return homeURL
        }
        if path.hasPrefix("~/") {
            return homeURL.appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    private static func backupURL(for url: URL, fileManager: FileManager) -> URL {
        let directory = url.deletingLastPathComponent()
        let baseName = "\(url.lastPathComponent).bak-\(Int(Date().timeIntervalSince1970))"
        var candidate = directory.appendingPathComponent(baseName)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(counter)")
            counter += 1
        }
        return candidate
    }

    private static func shellQuoted(_ value: String) -> String {
        if value.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "'\""))) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
