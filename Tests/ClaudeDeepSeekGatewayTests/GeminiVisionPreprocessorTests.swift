import XCTest
@testable import DeepSeekAliasProxyCore

final class GeminiVisionPreprocessorTests: XCTestCase {
    func testBase64ImageBlockIsReplacedWithGeminiTextAndNoBase64Remains() throws {
        let imageData = Data("image-bytes".utf8).base64EncodedString()
        let client = FakeGeminiClient(responses: [
            GeminiVisionDescription(
                text: "The screen shows a login form with an error banner.",
                errorMessage: nil,
                statusCode: 200,
                durationMs: 42,
                responseBodyBytes: 128
            ),
        ])
        let payload = messagePayload(content: [
            base64ImageBlock(data: imageData, mimeType: "image/png"),
            ["type": "text", "text": "What is wrong with this screen?"],
        ])

        let result = GeminiVisionPreprocessor(client: client).preprocess(
            payload: payload,
            configuration: GeminiVisionConfiguration(apiKey: "gemini-key", model: "gemini-2.5-flash")
        )

        XCTAssertEqual(result.report.imageCount, 1)
        XCTAssertEqual(result.report.successCount, 1)
        XCTAssertEqual(result.report.fallbackCount, 0)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests.first?.mimeType, "image/png")
        XCTAssertTrue(client.requests.first?.prompt.contains("What is wrong with this screen?") == true)

        let transformed = try jsonString(result.payload)
        XCTAssertFalse(transformed.contains(imageData))
        XCTAssertTrue(transformed.contains("Gemini image recognition result #1"))
        XCTAssertTrue(transformed.contains("login form"))
    }

    func testMultipleImagesAreReplacedInOrder() throws {
        let client = FakeGeminiClient(responses: [
            GeminiVisionDescription(text: "First image description.", errorMessage: nil, durationMs: 10),
            GeminiVisionDescription(text: "Second image description.", errorMessage: nil, durationMs: 20),
        ])
        let payload = messagePayload(content: [
            base64ImageBlock(data: Data("one".utf8).base64EncodedString(), mimeType: "image/jpeg"),
            ["type": "text", "text": "Compare these."],
            base64ImageBlock(data: Data("two".utf8).base64EncodedString(), mimeType: "image/webp"),
        ])

        let result = GeminiVisionPreprocessor(client: client).preprocess(
            payload: payload,
            configuration: GeminiVisionConfiguration(apiKey: "gemini-key", model: "gemini-2.5-flash")
        )

        XCTAssertEqual(result.report.imageCount, 2)
        XCTAssertEqual(result.report.successCount, 2)
        XCTAssertEqual(result.report.totalDurationMs, 30)

        let text = try jsonString(result.payload)
        let firstRange = try XCTUnwrap(text.range(of: "First image description."))
        let secondRange = try XCTUnwrap(text.range(of: "Second image description."))
        XCTAssertLessThan(firstRange.lowerBound, secondRange.lowerBound)
    }

    func testUnsupportedInvalidAndGeminiFailureImagesBecomeFallbackText() throws {
        let client = FakeGeminiClient(responses: [
            GeminiVisionDescription(
                text: nil,
                errorMessage: "Gemini quota exceeded.",
                statusCode: 429,
                durationMs: 99,
                responseBodyBytes: 256
            ),
        ])
        let payload = messagePayload(content: [
            ["type": "image", "source": ["type": "url", "url": "https://example.test/image.png"]],
            base64ImageBlock(data: Data("pdf".utf8).base64EncodedString(), mimeType: "application/pdf"),
            base64ImageBlock(data: "not-valid-base64", mimeType: "image/png"),
            base64ImageBlock(data: Data("ok".utf8).base64EncodedString(), mimeType: "image/gif"),
        ])

        let result = GeminiVisionPreprocessor(client: client).preprocess(
            payload: payload,
            configuration: GeminiVisionConfiguration(apiKey: "gemini-key", model: "gemini-2.5-flash")
        )

        XCTAssertEqual(result.report.imageCount, 4)
        XCTAssertEqual(result.report.successCount, 0)
        XCTAssertEqual(result.report.fallbackCount, 4)
        XCTAssertEqual(client.requests.count, 1)

        let text = try jsonString(result.payload)
        XCTAssertTrue(text.contains("Unsupported image source type: url"))
        XCTAssertTrue(text.contains("Unsupported image media type"))
        XCTAssertTrue(text.contains("Base64 image data is invalid or empty"))
        XCTAssertTrue(text.contains("Gemini quota exceeded"))
        XCTAssertTrue(text.contains("Raw error: Gemini quota exceeded"))
        XCTAssertFalse(text.contains("具体错误"))
    }

    func testMissingGeminiConfigurationFallsBackWithoutCallingClient() throws {
        let client = FakeGeminiClient(responses: [])
        let imageData = Data("image".utf8).base64EncodedString()
        let payload = messagePayload(content: [
            base64ImageBlock(data: imageData, mimeType: "image/png"),
        ])

        let result = GeminiVisionPreprocessor(client: client).preprocess(
            payload: payload,
            configuration: GeminiVisionConfiguration(apiKey: "", model: "")
        )

        XCTAssertEqual(client.requests.count, 0)
        XCTAssertEqual(result.report.imageCount, 1)
        XCTAssertEqual(result.report.fallbackCount, 1)

        let text = try jsonString(result.payload)
        XCTAssertFalse(text.contains(imageData))
        XCTAssertTrue(text.contains("GEMINI_API_KEY is not configured"))
        XCTAssertTrue(text.contains("Raw error: GEMINI_API_KEY is not configured."))
        XCTAssertFalse(text.contains("未能识别"))
    }

    func testTokenEstimateSanitizerStripsBase64AndCountsImageBlocks() throws {
        let imageData = Data("large-image-value".utf8).base64EncodedString()
        let payload = messagePayload(content: [
            ["type": "text", "text": "Describe this."],
            base64ImageBlock(data: imageData, mimeType: "image/png"),
        ])

        let sanitized = AnthropicPayloadSanitizer.sanitizedForTokenEstimate(payload)
        let text = try jsonString(sanitized)

        XCTAssertEqual(AnthropicPayloadSanitizer.imageBlockCount(in: payload), 1)
        XCTAssertFalse(text.contains(imageData))
        XCTAssertTrue(text.contains("approximate visual cost"))
    }

    func testLoggingSanitizerStripsBase64WithoutReplacingImageBlock() throws {
        let imageData = Data("log-image-value".utf8).base64EncodedString()
        let payload = messagePayload(content: [
            ["type": "text", "text": "Describe this."],
            base64ImageBlock(data: imageData, mimeType: "image/png"),
        ])

        let sanitized = AnthropicPayloadSanitizer.sanitizedForLogging(payload)
        let text = try jsonString(sanitized)

        XCTAssertFalse(text.contains(imageData))
        XCTAssertTrue(text.contains("\"type\":\"image\""))
        XCTAssertTrue(text.contains("\"media_type\":\"image/png\"") || text.contains("\"media_type\":\"image\\/png\""))
        XCTAssertTrue(text.contains("[base64 image data omitted from logs]"))
    }

    private func messagePayload(content: [Any]) -> [String: Any] {
        [
            "model": "claude-sonnet-4-6",
            "messages": [
                [
                    "role": "user",
                    "content": content,
                ],
            ],
        ]
    }

    private func base64ImageBlock(data: String, mimeType: String) -> [String: Any] {
        [
            "type": "image",
            "source": [
                "type": "base64",
                "media_type": mimeType,
                "data": data,
            ],
        ]
    }

    private func jsonString(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

private final class FakeGeminiClient: GeminiVisionDescribing {
    var responses: [GeminiVisionDescription]
    private(set) var requests: [GeminiVisionImageRequest] = []

    init(responses: [GeminiVisionDescription]) {
        self.responses = responses
    }

    func describeImage(_ request: GeminiVisionImageRequest) -> GeminiVisionDescription {
        requests.append(request)
        if responses.isEmpty {
            return GeminiVisionDescription(
                text: nil,
                errorMessage: "Unexpected Gemini call.",
                durationMs: 0
            )
        }
        return responses.removeFirst()
    }
}
