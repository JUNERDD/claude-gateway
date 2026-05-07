import XCTest
@testable import ClaudeDeepSeekGateway

final class ClaudeMCPSyncTests: XCTestCase {
    func testBundledClaudeMCPServerSyncReplacesExistingDirectoryWithSymlink() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("ClaudeMCPSyncTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }

        let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        let sourceServer = sourceRoot.appendingPathComponent("vision-provider", isDirectory: true)
        let destinationRoot = root.appendingPathComponent("claude-mcp", isDirectory: true)
        let existingServer = destinationRoot.appendingPathComponent("vision-provider", isDirectory: true)

        try fm.createDirectory(at: sourceServer, withIntermediateDirectories: true)
        try "#!/usr/bin/env python3\n".write(
            to: sourceServer.appendingPathComponent("server.py"),
            atomically: true,
            encoding: .utf8
        )
        try fm.createDirectory(at: existingServer, withIntermediateDirectories: true)
        try "old server\n".write(
            to: existingServer.appendingPathComponent("server.py"),
            atomically: true,
            encoding: .utf8
        )

        var report = ClaudeConfigSyncReport()
        ClaudeDesktopConfigSync.syncBundledClaudeMCPServers(
            sourceRoot: sourceRoot,
            destinationRoot: destinationRoot,
            report: &report
        )

        let destination = destinationRoot.appendingPathComponent("vision-provider", isDirectory: true)
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: destination.path), sourceServer.path)
        XCTAssertEqual(report.installedClaudeMCPServers.count, 1)
        XCTAssertEqual(report.unchangedClaudeMCPServers.count, 0)
        XCTAssertEqual(report.backups.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: URL(fileURLWithPath: try XCTUnwrap(report.backups.first)).appendingPathComponent("server.py").path))

        var secondReport = ClaudeConfigSyncReport()
        ClaudeDesktopConfigSync.syncBundledClaudeMCPServers(
            sourceRoot: sourceRoot,
            destinationRoot: destinationRoot,
            report: &secondReport
        )

        XCTAssertEqual(secondReport.installedClaudeMCPServers.count, 0)
        XCTAssertEqual(secondReport.unchangedClaudeMCPServers.count, 1)
        XCTAssertTrue(secondReport.userMessage.contains("Claude MCP Server 已匹配"))
    }

    func testClaudeCodeUserMCPConfigAddsVisionProviderWithoutRemovingExistingServers() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("ClaudeCodeUserMCPConfigTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let configURL = root.appendingPathComponent(".claude.json")
        let existing: [String: Any] = [
            "theme": "dark",
            "mcpServers": [
                "next-devtools": [
                    "type": "stdio",
                    "command": "npx",
                    "args": ["next-devtools-mcp@latest"],
                ],
            ],
        ]
        let existingData = try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted, .sortedKeys])
        try existingData.write(to: configURL)

        let visionConfig: [String: Any] = [
            "type": "stdio",
            "command": "python3",
            "args": ["/tmp/vision-provider/server.py"],
            "env": [
                "CLAUDE_DEEPSEEK_GATEWAY_URL": "http://127.0.0.1:4000",
                "LOCAL_GATEWAY_KEY": "sk-local-test",
            ],
        ]

        var report = ClaudeConfigSyncReport()
        try ClaudeDesktopConfigSync.syncClaudeCodeUserMCPConfig(
            at: configURL,
            mcpServerConfig: visionConfig,
            report: &report
        )

        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any])
        let servers = try XCTUnwrap(decoded["mcpServers"] as? [String: Any])
        XCTAssertNotNil(servers["next-devtools"])
        let vision = try XCTUnwrap(servers["vision-provider"] as? [String: Any])
        XCTAssertEqual(vision["type"] as? String, "stdio")
        XCTAssertEqual(vision["command"] as? String, "python3")
        XCTAssertEqual(report.updatedClaudeCodeSettings, [configURL.path])
    }

    func testClaudeDesktopMCPConfigAddsVisionProviderWithoutRemovingExistingServers() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("ClaudeDesktopMCPConfigTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let configURL = root.appendingPathComponent("claude_desktop_config.json")
        let existing: [String: Any] = [
            "mcpServers": [
                "filesystem": [
                    "type": "stdio",
                    "command": "npx",
                    "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
                ],
            ],
        ]
        let existingData = try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted, .sortedKeys])
        try existingData.write(to: configURL)

        let visionConfig: [String: Any] = [
            "type": "stdio",
            "command": "python3",
            "args": ["/tmp/vision-provider/server.py"],
            "env": [
                "CLAUDE_DEEPSEEK_GATEWAY_URL": "http://127.0.0.1:4000",
                "LOCAL_GATEWAY_KEY": "sk-local-test",
            ],
        ]

        var report = ClaudeConfigSyncReport()
        try ClaudeDesktopConfigSync.syncClaudeDesktopMCPConfig(
            at: configURL,
            mcpServerConfig: visionConfig,
            report: &report
        )

        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any])
        let servers = try XCTUnwrap(decoded["mcpServers"] as? [String: Any])
        XCTAssertNotNil(servers["filesystem"])
        let vision = try XCTUnwrap(servers["vision-provider"] as? [String: Any])
        XCTAssertEqual(vision["type"] as? String, "stdio")
        XCTAssertEqual(vision["command"] as? String, "python3")
        XCTAssertEqual(report.updatedClaudeDesktopMCPConfig, [configURL.path])
        XCTAssertEqual(report.backups.count, 1)

        var secondReport = ClaudeConfigSyncReport()
        try ClaudeDesktopConfigSync.syncClaudeDesktopMCPConfig(
            at: configURL,
            mcpServerConfig: visionConfig,
            report: &secondReport
        )
        XCTAssertEqual(secondReport.unchangedClaudeDesktopMCPConfig, [configURL.path])
    }

    func testClaudeDesktopMCPConfigTargetsClaude3pAndExistingStandardConfig() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("ClaudeDesktopMCPConfigTargetTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }

        let appSupport = root.appendingPathComponent("Application Support", isDirectory: true)
        let claude3pConfig = appSupport
            .appendingPathComponent("Claude-3p", isDirectory: true)
            .appendingPathComponent("claude_desktop_config.json")
        let standardConfig = appSupport
            .appendingPathComponent("Claude", isDirectory: true)
            .appendingPathComponent("claude_desktop_config.json")

        XCTAssertEqual(
            normalizedPaths(
                ClaudeDesktopConfigSync.targetClaudeDesktopMCPConfigURLs(
                    appSupportURL: appSupport,
                    environment: [:]
                )
            ),
            normalizedPaths([claude3pConfig])
        )

        try fm.createDirectory(at: standardConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{}".write(to: standardConfig, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            normalizedPaths(
                ClaudeDesktopConfigSync.targetClaudeDesktopMCPConfigURLs(
                    appSupportURL: appSupport,
                    environment: [:]
                )
            ),
            normalizedPaths([claude3pConfig, standardConfig])
        )
    }

    func testClaudeDesktopMCPConfigDiscoversCustomIndependentConfigDirectory() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("ClaudeDesktopCustomMCPConfigTargetTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }

        let appSupport = root.appendingPathComponent("Application Support", isDirectory: true)
        let customConfig = appSupport
            .appendingPathComponent("Company Claude", isDirectory: true)
            .appendingPathComponent("claude_desktop_config.json")
        let claude3pConfig = appSupport
            .appendingPathComponent("Claude-3p", isDirectory: true)
            .appendingPathComponent("claude_desktop_config.json")

        try fm.createDirectory(at: customConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{}".write(to: customConfig, atomically: true, encoding: .utf8)

        let targets = ClaudeDesktopConfigSync.targetClaudeDesktopMCPConfigURLs(
            appSupportURL: appSupport,
            environment: [:]
        )

        XCTAssertEqual(normalizedPaths(targets), normalizedPaths([customConfig]))
        XCTAssertFalse(normalizedPaths(targets).contains(normalizedPaths([claude3pConfig])[0]))
    }

    private func normalizedPaths(_ urls: [URL]) -> [String] {
        urls.map { $0.resolvingSymlinksInPath().path }
    }
}
