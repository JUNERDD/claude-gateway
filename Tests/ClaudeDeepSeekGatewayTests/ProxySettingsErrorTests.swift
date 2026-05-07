import XCTest
@testable import ClaudeDeepSeekGateway

final class ProxySettingsErrorTests: XCTestCase {
    func testDiskSettingsDecodeWithDefaultVisionProviderFields() throws {
        let json = """
        {
          "host": "127.0.0.1",
          "port": 4000,
          "anthropicBaseURL": "https://api.deepseek.com/anthropic",
          "haikuTargetModel": "deepseek-v4-flash",
          "nonHaikuTargetModel": "deepseek-v4-pro[1m]",
          "advertisedModels": ["claude-haiku-4-5"]
        }
        """

        let decoded = try JSONDecoder().decode(ProxyDiskSettings.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.haikuTargetModel, "deepseek-v4-flash")
        XCTAssertEqual(decoded.nonHaikuTargetModel, "deepseek-v4-pro[1m]")
        XCTAssertEqual(decoded.advertisedModels, ["claude-haiku-4-5"])
        XCTAssertEqual(decoded.visionProvider, "auto")
        XCTAssertEqual(decoded.visionProviderModel, "")
        XCTAssertEqual(decoded.visionProviderBaseURL, "")
    }

    func testEncodedSettingsUseGenericVisionProviderFields() throws {
        let settings = ProxyDiskSettings(
            host: "127.0.0.1",
            port: 4000,
            anthropicBaseURL: "https://api.deepseek.com/anthropic",
            haikuTargetModel: "deepseek-v4-flash",
            nonHaikuTargetModel: "deepseek-v4-pro[1m]",
            visionProvider: "dashscope-anthropic",
            visionProviderModel: "qwen3-vl-flash",
            visionProviderBaseURL: "https://dashscope.aliyuncs.com/apps/anthropic",
            advertisedModels: ["claude-sonnet-4-6"]
        )

        let data = try JSONEncoder().encode(settings)
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(text.contains("visionProvider"))
        XCTAssertTrue(text.contains("qwen3-vl-flash"))
        XCTAssertFalse(text.contains("geminiVisionModel"))
    }

    func testEmptyFieldErrorMessageNamesTheMissingField() {
        XCTAssertEqual(
            ProxySettingsError.emptyField("DeepSeek API Key").errorDescription,
            "DeepSeek API Key 不能为空。"
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
