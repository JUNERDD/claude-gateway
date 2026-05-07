import XCTest
@testable import ClaudeDeepSeekGateway

final class ProxySettingsErrorTests: XCTestCase {
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
}
