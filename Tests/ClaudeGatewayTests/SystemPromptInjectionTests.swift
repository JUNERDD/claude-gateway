import XCTest
import GatewayProxyCore
@testable import GatewayProxy

final class SystemPromptInjectionTests: XCTestCase {
    func testRuntimeSettingsLoaderReadsProviderScopedSystemPromptInjection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settingsURL = directory.appendingPathComponent("proxy_settings.json")
        try """
        {
          "providers": [{
            "id": "custom",
            "displayName": "Custom",
            "baseURL": "https://provider.example.com/anthropic",
            "auth": {"type": "x-api-key", "customHeaderName": ""},
            "defaultHeaders": {},
            "systemPromptInjection": "stable provider instruction"
          }],
          "defaultProviderID": "custom",
          "defaultRoute": {"providerID": "custom", "upstreamModel": "provider-sonnet"},
          "modelRoutes": [{"alias": "claude-sonnet-4-6", "providerID": "custom", "upstreamModel": "provider-sonnet"}]
        }
        """.write(to: settingsURL, atomically: true, encoding: .utf8)

        setenv("GATEWAY_SETTINGS_PATH", settingsURL.path, 1)
        defer {
            unsetenv("GATEWAY_SETTINGS_PATH")
            try? FileManager.default.removeItem(at: directory)
        }

        let settings = SettingsLoader.shared.load()

        XCTAssertEqual(settings.provider(id: "custom")?.systemPromptInjection, "stable provider instruction")
    }

    func testBlankSystemPromptInjectionLeavesPayloadUnchanged() {
        let payload: [String: Any] = [
            "system": "base",
            "messages": [
                ["role": "user", "content": "hello"],
            ],
        ]

        let injected = payloadByInjectingSystemPrompt(into: payload, injection: " \n\t ")

        XCTAssertEqual(injected["system"] as? String, "base")
        XCTAssertEqual((injected["messages"] as? [[String: String]])?.first?["content"], "hello")
    }

    func testStringSystemPromptInjectionAppendsWithSeparator() {
        let injected = payloadByInjectingSystemPrompt(
            into: ["system": "base"],
            injection: "\n\nstable provider instruction\n"
        )

        XCTAssertEqual(injected["system"] as? String, "base\n\nstable provider instruction")
    }

    func testArraySystemPromptInjectionAppendsTextBlockAndPreservesCacheControl() throws {
        let payload: [String: Any] = [
            "system": [
                [
                    "type": "text",
                    "text": "base",
                    "cache_control": ["type": "ephemeral"],
                ],
            ],
        ]

        let injected = payloadByInjectingSystemPrompt(into: payload, injection: "stable provider instruction")
        let blocks = try XCTUnwrap(injected["system"] as? [[String: Any]])

        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0]["text"] as? String, "base")
        XCTAssertEqual((blocks[0]["cache_control"] as? [String: String])?["type"], "ephemeral")
        XCTAssertEqual(blocks[1]["type"] as? String, "text")
        XCTAssertEqual(blocks[1]["text"] as? String, "stable provider instruction")
        XCTAssertNil(blocks[1]["cache_control"])
    }

    func testMissingSystemPromptInjectionCreatesSystemPrompt() {
        let injected = payloadByInjectingSystemPrompt(
            into: ["messages": [["role": "user", "content": "hello"]]],
            injection: "stable provider instruction"
        )

        XCTAssertEqual(injected["system"] as? String, "stable provider instruction")
    }

    func testTokenEstimateUsesRoutedProviderSystemPromptInjection() {
        let payload: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "system": "base",
            "messages": [
                ["role": "user", "content": "hello"],
            ],
        ]
        let withoutInjection = ProxySettings()
        var withInjection = ProxySettings()
        withInjection.providers = [
            GatewayProvider(
                id: "custom",
                displayName: "Custom",
                baseURL: "https://provider.example.com/anthropic",
                systemPromptInjection: String(repeating: "extra context ", count: 40)
            ),
        ]
        withInjection.defaultProviderID = "custom"
        withInjection.defaultRoute = GatewayRouteTarget(providerID: "custom", upstreamModel: "provider-sonnet")
        withInjection.modelRoutes = [
            GatewayModelRoute(alias: "claude-sonnet-4-6", providerID: "custom", upstreamModel: "provider-sonnet"),
        ]

        let baseline = estimatedInputTokens(for: payload, settings: withoutInjection)
        let injected = estimatedInputTokens(for: payload, settings: withInjection)

        XCTAssertGreaterThan(injected, baseline)
    }
}
