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

    func testGeminiVisionPreprocessEventShowsFallbackWarning() throws {
        let logText = """
        CDSG_EVENT {"durationMs":99,"fallbackCount":1,"imageCount":2,"model":"gemini-2.5-flash","requestID":"req-vision","successCount":1,"timestamp":"2026-05-07T10:00:00Z","type":"gemini_vision_preprocess"}
        """

        let event = try XCTUnwrap(GatewayLogParser.parse(logText).first)

        XCTAssertEqual(event.title, "Gemini 图片预处理")
        XCTAssertEqual(event.subtitle, "1/2 张成功")
        XCTAssertEqual(event.tone.label, "Warning")
        XCTAssertTrue(event.fields.contains { $0.label == "模型" && $0.value == "gemini-2.5-flash" })
    }

    func testImageAttachmentBridgeEventShowsSavedCount() throws {
        let logText = """
        CDSG_EVENT {"attachments":[{"byteCount":12,"imageIndex":1,"mimeType":"image/png","path":"/tmp/image-1.png","status":"saved"}],"fallbackCount":0,"imageCount":1,"requestID":"req-bridge","savedCount":1,"timestamp":"2026-05-07T10:00:00Z","totalBytes":12,"type":"image_attachment_bridge"}
        """

        let event = try XCTUnwrap(GatewayLogParser.parse(logText).first)

        XCTAssertEqual(event.title, "图片附件桥接")
        XCTAssertEqual(event.subtitle, "1/1 张已保存")
        XCTAssertEqual(event.tone.label, "Request")
        XCTAssertTrue(event.fields.contains { $0.label == "大小" && $0.value == "12 bytes" })
    }

    func testVisionGatewayResponseEventShowsProviderAndModel() throws {
        let logText = """
        CDSG_EVENT {"durationMs":321,"imageBytes":80288,"model":"qwen3-vl-flash","provider":"dashscope","requestID":"req-vision-mcp","responseBodyBytes":512,"status":200,"timestamp":"2026-05-07T10:00:00Z","type":"vision_gateway_response"}
        """

        let event = try XCTUnwrap(GatewayLogParser.parse(logText).first)

        XCTAssertEqual(event.title, "Vision MCP 响应")
        XCTAssertEqual(event.subtitle, "HTTP 200")
        XCTAssertEqual(event.tone.label, "Response")
        XCTAssertTrue(event.fields.contains { $0.label == "provider" && $0.value == "dashscope" })
        XCTAssertTrue(event.fields.contains { $0.label == "模型" && $0.value == "qwen3-vl-flash" })
    }
}
