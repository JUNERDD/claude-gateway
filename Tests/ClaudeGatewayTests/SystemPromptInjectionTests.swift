import XCTest
@testable import GatewayProxy

final class SystemPromptInjectionTests: XCTestCase {
    func testRuntimeSettingsLoaderPreservesSystemPromptWhitespace() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settingsURL = directory.appendingPathComponent("proxy_settings.json")
        try """
        {
          "systemPromptPrefix": "prefix\\n\\n",
          "systemPromptSuffix": "\\n\\nsuffix"
        }
        """.write(to: settingsURL, atomically: true, encoding: .utf8)

        setenv("GATEWAY_SETTINGS_PATH", settingsURL.path, 1)
        defer {
            unsetenv("GATEWAY_SETTINGS_PATH")
            try? FileManager.default.removeItem(at: directory)
        }

        let settings = SettingsLoader.shared.load()

        XCTAssertEqual(settings.systemPromptPrefix, "prefix\n\n")
        XCTAssertEqual(settings.systemPromptSuffix, "\n\nsuffix")
    }

    func testStringSystemPromptInjectionPreservesConfiguredSeparators() {
        var settings = ProxySettings()
        settings.systemPromptPrefix = "prefix\n\n"
        settings.systemPromptSuffix = "\n\nsuffix"

        let injected = payloadByInjectingSystemPrompt(into: ["system": "base"], settings: settings)

        XCTAssertEqual(injected["system"] as? String, "prefix\n\nbase\n\nsuffix")
    }

    func testTokenEstimateIncludesInjectedSystemPrompt() {
        let payload: [String: Any] = [
            "system": "base",
            "messages": [
                ["role": "user", "content": "hello"],
            ],
        ]
        let withoutInjection = ProxySettings()
        var withInjection = ProxySettings()
        withInjection.systemPromptPrefix = String(repeating: "extra context ", count: 40)

        let baseline = estimatedInputTokens(for: payload, settings: withoutInjection)
        let injected = estimatedInputTokens(for: payload, settings: withInjection)

        XCTAssertGreaterThan(injected, baseline)
    }
}
