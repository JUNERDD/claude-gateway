import GatewayProxyCore
import XCTest
@testable import ClaudeGateway

final class ProxySettingsErrorTests: XCTestCase {
    func testDiskSettingsDecodeWithDefaultVisionProviderFields() throws {
        let json = """
        {
          "host": "127.0.0.1",
          "port": 4000,
          "providers": [{
            "id": "custom",
            "displayName": "Custom",
            "baseURL": "https://provider.example.com/anthropic",
            "auth": {"type": "bearer", "customHeaderName": ""},
            "defaultHeaders": {"x-provider-region": "test"}
          }],
          "defaultProviderID": "custom",
          "defaultRoute": {"providerID": "custom", "upstreamModel": "provider-sonnet"},
          "modelRoutes": [{"alias": "claude-sonnet-4-6", "providerID": "custom", "upstreamModel": "provider-sonnet"}]
        }
        """

        let decoded = try JSONDecoder().decode(ProxyDiskSettings.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.providers.first?.baseURL, "https://provider.example.com/anthropic")
        XCTAssertEqual(decoded.defaultRoute.upstreamModel, "provider-sonnet")
        XCTAssertEqual(decoded.advertisedModels, ["claude-sonnet-4-6"])
        XCTAssertEqual(decoded.visionProvider, "auto")
        XCTAssertEqual(decoded.visionProviderModel, "")
        XCTAssertEqual(decoded.visionProviderBaseURL, "")
        XCTAssertEqual(decoded.providers.first?.systemPromptInjection, "")
        XCTAssertEqual(decoded.providers.first?.compatibilityProfileID, GatewayProvider.genericCompatibilityProfileID)
        XCTAssertEqual(decoded.providers.first?.anthropicBetaHeaderMode, GatewayProvider.anthropicBetaForward)
        XCTAssertEqual(decoded.providers.first?.claudeCode.appendSystemPromptPath, GatewayProviderClaudeCodeSettings.defaultAppendSystemPromptPath)
        XCTAssertEqual(decoded.providers.first?.claudeCode.appendSystemPromptEnabled, false)
    }

    func testEncodedSettingsUseProviderRoutesAndGenericVisionProviderFields() throws {
        let settings = ProxyDiskSettings(
            host: "127.0.0.1",
            port: 4000,
            providers: [
                GatewayProvider(
                    id: "custom",
                    displayName: "Custom",
                    baseURL: "https://provider.example.com/anthropic",
                    auth: GatewayProviderAuth(type: GatewayProviderAuth.bearer),
                    defaultHeaders: [:],
                    systemPromptInjection: "stable provider instruction"
                ),
            ],
            defaultProviderID: "custom",
            defaultRoute: GatewayRouteTarget(providerID: "custom", upstreamModel: "provider-sonnet"),
            modelRoutes: [
                GatewayModelRoute(alias: "claude-sonnet-4-6", providerID: "custom", upstreamModel: "provider-sonnet"),
            ],
            visionProvider: "dashscope",
            visionProviderModel: "qwen3-vl-flash",
            visionProviderBaseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        )

        let data = try JSONEncoder().encode(settings)
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(text.contains("providers"))
        XCTAssertTrue(text.contains("modelRoutes"))
        XCTAssertTrue(text.contains("visionProvider"))
        XCTAssertTrue(text.contains("systemPromptInjection"))
        XCTAssertTrue(text.contains("compatibilityProfileID"))
        XCTAssertTrue(text.contains("anthropicBetaHeaderMode"))
        XCTAssertTrue(text.contains("claudeCode"))
        XCTAssertFalse(text.contains("haiku" + "TargetModel"))
        XCTAssertFalse(text.contains("systemPromptPrefix"))
        XCTAssertFalse(text.contains("systemPromptSuffix"))
    }

    func testEmptyFieldErrorMessageNamesTheMissingField() {
        XCTAssertEqual(
            ProxySettingsError.emptyField("Provider API Key").errorDescription,
            "Provider API Key 不能为空。"
        )
    }

    func testInvalidPortErrorMessageUsesActionableRange() {
        XCTAssertEqual(
            ProxySettingsError.invalidPort.errorDescription,
            "端口必须是 1 到 65535 的数字。"
        )
    }

    func testInvalidVisionProviderErrorNamesSupportedProviders() {
        XCTAssertEqual(
            ProxySettingsError.invalidVisionProvider.errorDescription,
            "Vision Provider 必须是 auto、dashscope、gemini 或 openai-compatible。"
        )
    }
}
