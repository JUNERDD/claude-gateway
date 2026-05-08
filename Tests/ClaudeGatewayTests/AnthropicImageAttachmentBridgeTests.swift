import XCTest
@testable import GatewayProxyCore

final class AnthropicImageAttachmentBridgeTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("attachment-bridge-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testBase64ImageBlockIsSavedAndReplacedWithVisionProviderPath() throws {
        let imageBytes = Data("image-bytes".utf8)
        let imageData = imageBytes.base64EncodedString()
        let payload = messagePayload(content: [
            base64ImageBlock(data: imageData, mimeType: "image/png"),
            ["type": "text", "text": "Explain this image."],
        ])

        let result = bridge().bridge(payload: payload, requestID: "req-test", date: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(result.report.imageCount, 1)
        XCTAssertEqual(result.report.savedCount, 1)
        XCTAssertEqual(result.report.fallbackCount, 0)
        XCTAssertEqual(result.report.totalBytes, imageBytes.count)

        let attachment = try XCTUnwrap(result.report.attachments.first)
        XCTAssertEqual(attachment.status, "saved")
        XCTAssertEqual(attachment.mimeType, "image/png")
        let path = try XCTUnwrap(attachment.path)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), imageBytes)

        let json = try jsonString(result.payload)
        let text = joinedText(in: result.payload)
        XCTAssertFalse(json.contains(imageData))
        XCTAssertTrue(text.contains("Image attachment #1 saved for vision-provider"))
        XCTAssertTrue(text.contains(path))
        XCTAssertTrue(text.contains("Tool: vision_describe"))
        XCTAssertTrue(text.contains(#""image_path": "\#(path)""#))
    }

    func testMultipleImagesAreSavedInOriginalOrder() throws {
        let first = Data("first".utf8).base64EncodedString()
        let second = Data("second".utf8).base64EncodedString()
        let payload = messagePayload(content: [
            base64ImageBlock(data: first, mimeType: "image/jpeg"),
            ["type": "text", "text": "Compare these."],
            base64ImageBlock(data: second, mimeType: "image/webp"),
        ])

        let result = bridge().bridge(payload: payload, requestID: "req-test", date: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(result.report.imageCount, 2)
        XCTAssertEqual(result.report.savedCount, 2)
        XCTAssertEqual(result.report.attachments.map(\.imageIndex), [1, 2])

        let json = try jsonString(result.payload)
        let text = joinedText(in: result.payload)
        let firstRange = try XCTUnwrap(text.range(of: "Image attachment #1 saved for vision-provider"))
        let secondRange = try XCTUnwrap(text.range(of: "Image attachment #2 saved for vision-provider"))
        XCTAssertLessThan(firstRange.lowerBound, secondRange.lowerBound)
        XCTAssertFalse(json.contains(first))
        XCTAssertFalse(json.contains(second))
    }

    func testUnsupportedAndInvalidImagesBecomeFallbackTextWithoutBase64() throws {
        let imageData = Data("image".utf8).base64EncodedString()
        let payload = messagePayload(content: [
            ["type": "image", "source": ["type": "url", "url": "https://example.test/image.png"]],
            base64ImageBlock(data: imageData, mimeType: "application/pdf"),
            base64ImageBlock(data: "not-valid-base64", mimeType: "image/png"),
        ])

        let result = bridge().bridge(payload: payload, requestID: "req-test", date: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(result.report.imageCount, 3)
        XCTAssertEqual(result.report.savedCount, 0)
        XCTAssertEqual(result.report.fallbackCount, 3)
        XCTAssertTrue(result.report.attachments.allSatisfy { $0.status == "fallback" })

        let json = try jsonString(result.payload)
        let text = joinedText(in: result.payload)
        XCTAssertTrue(text.contains("Unsupported image source type: url"))
        XCTAssertTrue(text.contains("Unsupported image media type: application/pdf"))
        XCTAssertTrue(text.contains("Base64 image data is invalid or empty"))
        XCTAssertFalse(json.contains(imageData))
        XCTAssertFalse(json.contains("not-valid-base64"))
    }

    private func bridge() -> AnthropicImageAttachmentBridge {
        AnthropicImageAttachmentBridge(configuration: AnthropicImageAttachmentBridgeConfiguration(cacheDirectory: tempDirectory))
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

    private func joinedText(in payload: [String: Any]) -> String {
        guard let messages = payload["messages"] as? [[String: Any]] else { return "" }
        return messages.flatMap { message -> [String] in
            guard let content = message["content"] as? [[String: Any]] else { return [] }
            return content.compactMap { block in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }
        }.joined(separator: "\n")
    }
}
