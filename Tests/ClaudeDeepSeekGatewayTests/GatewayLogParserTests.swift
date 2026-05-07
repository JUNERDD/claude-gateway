import XCTest
@testable import ClaudeDeepSeekGateway

final class GatewayLogParserTests: XCTestCase {
    func testStructuredErrorResponseIsPromotedToWarningEvent() throws {
        let logText = """
        CDSG_EVENT {"durationMs":1200,"outputTokensEstimate":88,"requestID":"req-429","responseBodyBytes":512,"status":429,"timestamp":"2026-05-07T10:00:00Z","type":"deepseek_response"}
        """

        let event = try XCTUnwrap(GatewayLogParser.parse(logText).first)

        XCTAssertEqual(event.title, "DeepSeek 响应")
        XCTAssertEqual(event.subtitle, "HTTP 429")
        XCTAssertEqual(event.tone.label, "Warning")
        XCTAssertTrue(event.fields.contains { $0.label == "output" && $0.value == "~88 tokens" })
        XCTAssertTrue(event.detailJSON?.contains(#""status" : 429"#) == true)
    }

    func testPlainFailureLineUsesErrorTone() throws {
        let event = try XCTUnwrap(GatewayLogParser.parse("操作失败：DeepSeek API Key 不能为空。").first)

        XCTAssertEqual(event.title, "操作失败：DeepSeek API Key 不能为空。")
        XCTAssertEqual(event.tone.label, "Error")
        XCTAssertNil(event.detailJSON)
    }
}
