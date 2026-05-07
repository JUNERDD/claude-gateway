import Foundation

public struct AnthropicImageAttachmentBridgeConfiguration {
    public var cacheDirectory: URL
    public var maxImageBytes: Int

    public init(
        cacheDirectory: URL = Self.defaultCacheDirectory(),
        maxImageBytes: Int = 100 * 1024 * 1024
    ) {
        self.cacheDirectory = cacheDirectory
        self.maxImageBytes = maxImageBytes
    }

    public static func defaultCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("ClaudeDeepSeekGateway", isDirectory: true)
    }
}

public struct AnthropicImageAttachmentReport {
    public var imageIndex: Int
    public var status: String
    public var mimeType: String?
    public var path: String?
    public var byteCount: Int
    public var reason: String?

    public init(
        imageIndex: Int,
        status: String,
        mimeType: String?,
        path: String?,
        byteCount: Int,
        reason: String?
    ) {
        self.imageIndex = imageIndex
        self.status = status
        self.mimeType = mimeType
        self.path = path
        self.byteCount = byteCount
        self.reason = reason
    }

    public var logObject: [String: Any] {
        var object: [String: Any] = [
            "imageIndex": imageIndex,
            "status": status,
            "byteCount": byteCount,
        ]
        if let mimeType {
            object["mimeType"] = mimeType
        }
        if let path {
            object["path"] = path
        }
        if let reason {
            object["reason"] = reason
        }
        return object
    }
}

public struct AnthropicImageAttachmentBridgeReport {
    public var imageCount: Int = 0
    public var savedCount: Int = 0
    public var fallbackCount: Int = 0
    public var totalBytes: Int = 0
    public var attachments: [AnthropicImageAttachmentReport] = []

    public init() {}

    public var didBridgeImages: Bool {
        imageCount > 0
    }

    public var logObject: [String: Any] {
        [
            "imageCount": imageCount,
            "savedCount": savedCount,
            "fallbackCount": fallbackCount,
            "totalBytes": totalBytes,
            "attachments": attachments.map(\.logObject),
        ]
    }
}

public struct AnthropicImageAttachmentBridgeResult {
    public var payload: [String: Any]
    public var report: AnthropicImageAttachmentBridgeReport

    public init(payload: [String: Any], report: AnthropicImageAttachmentBridgeReport) {
        self.payload = payload
        self.report = report
    }
}

public final class AnthropicImageAttachmentBridge {
    private let configuration: AnthropicImageAttachmentBridgeConfiguration
    private let fileManager: FileManager
    private let supportedMediaTypes: Set<String> = [
        "image/jpeg",
        "image/png",
        "image/gif",
        "image/webp",
    ]

    public init(
        configuration: AnthropicImageAttachmentBridgeConfiguration = AnthropicImageAttachmentBridgeConfiguration(),
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
    }

    public func bridge(
        payload: [String: Any],
        requestID: String,
        date: Date = Date()
    ) -> AnthropicImageAttachmentBridgeResult {
        var report = AnthropicImageAttachmentBridgeReport()
        var transformed = payload
        guard let messages = payload["messages"] as? [Any] else {
            return AnthropicImageAttachmentBridgeResult(payload: transformed, report: report)
        }

        var nextImageIndex = 1
        var transformedMessages: [Any] = []
        transformedMessages.reserveCapacity(messages.count)

        for rawMessage in messages {
            guard var message = rawMessage as? [String: Any],
                let content = message["content"] as? [Any]
            else {
                transformedMessages.append(rawMessage)
                continue
            }

            var transformedContent: [Any] = []
            transformedContent.reserveCapacity(content.count)

            for rawBlock in content {
                guard let block = rawBlock as? [String: Any],
                    (block["type"] as? String) == "image"
                else {
                    transformedContent.append(rawBlock)
                    continue
                }

                transformedContent.append(replacementBlock(
                    for: block,
                    imageIndex: nextImageIndex,
                    requestID: requestID,
                    date: date,
                    report: &report
                ))
                nextImageIndex += 1
            }

            message["content"] = transformedContent
            transformedMessages.append(message)
        }

        transformed["messages"] = transformedMessages
        return AnthropicImageAttachmentBridgeResult(payload: transformed, report: report)
    }

    private func replacementBlock(
        for block: [String: Any],
        imageIndex: Int,
        requestID: String,
        date: Date,
        report: inout AnthropicImageAttachmentBridgeReport
    ) -> [String: Any] {
        report.imageCount += 1

        let source = block["source"] as? [String: Any]
        let mimeType = (source?["media_type"] as? String)?.lowercased()

        guard let source else {
            return fallbackBlock(imageIndex: imageIndex, mimeType: nil, reason: "Anthropic image source is missing.", report: &report)
        }
        guard (source["type"] as? String) == "base64" else {
            let sourceType = source["type"] as? String ?? "unknown"
            return fallbackBlock(
                imageIndex: imageIndex,
                mimeType: mimeType,
                reason: "Unsupported image source type: \(sourceType). Only base64 is supported for local attachment bridging.",
                report: &report
            )
        }
        guard let mimeType, supportedMediaTypes.contains(mimeType) else {
            return fallbackBlock(
                imageIndex: imageIndex,
                mimeType: mimeType,
                reason: "Unsupported image media type: \(mimeType ?? "missing").",
                report: &report
            )
        }
        guard let rawBase64 = source["data"] as? String else {
            return fallbackBlock(imageIndex: imageIndex, mimeType: mimeType, reason: "Base64 image data is missing.", report: &report)
        }

        let compactBase64 = rawBase64.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let decoded = Data(base64Encoded: compactBase64), !decoded.isEmpty else {
            return fallbackBlock(
                imageIndex: imageIndex,
                mimeType: mimeType,
                reason: "Base64 image data is invalid or empty.",
                report: &report
            )
        }
        guard decoded.count <= configuration.maxImageBytes else {
            return fallbackBlock(
                imageIndex: imageIndex,
                mimeType: mimeType,
                reason: "Image is larger than the local attachment bridge limit.",
                byteCount: decoded.count,
                report: &report
            )
        }

        do {
            let fileURL = try writeImage(decoded, mimeType: mimeType, imageIndex: imageIndex, requestID: requestID, date: date)
            report.savedCount += 1
            report.totalBytes += decoded.count
            report.attachments.append(AnthropicImageAttachmentReport(
                imageIndex: imageIndex,
                status: "saved",
                mimeType: mimeType,
                path: fileURL.path,
                byteCount: decoded.count,
                reason: nil
            ))
            return savedTextBlock(imageIndex: imageIndex, mimeType: mimeType, byteCount: decoded.count, path: fileURL.path)
        } catch {
            return fallbackBlock(
                imageIndex: imageIndex,
                mimeType: mimeType,
                reason: "Image could not be saved for vision-provider: \(error.localizedDescription)",
                byteCount: decoded.count,
                report: &report
            )
        }
    }

    private func writeImage(
        _ data: Data,
        mimeType: String,
        imageIndex: Int,
        requestID: String,
        date: Date
    ) throws -> URL {
        let directory = configuration.cacheDirectory
            .appendingPathComponent("attachments", isDirectory: true)
            .appendingPathComponent(dayString(for: date), isDirectory: true)
            .appendingPathComponent(safePathComponent(requestID), isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let fileURL = directory.appendingPathComponent("image-\(imageIndex).\(fileExtension(for: mimeType))")
        try data.write(to: fileURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        return fileURL
    }

    private func savedTextBlock(imageIndex: Int, mimeType: String, byteCount: Int, path: String) -> [String: Any] {
        textBlock("""
        [Image attachment #\(imageIndex) saved for vision-provider]
        The original Anthropic image block was saved as a local file because the downstream DeepSeek model is text-only.
        Path: \(path)
        MIME type: \(mimeType)
        Size: \(byteCount) bytes

        If the user asks about this image, call the vision-provider MCP tool before answering:
        Tool: vision_describe
        Arguments: {"image_path": "\(path)", "prompt": "Describe image #\(imageIndex) for the current task. Preserve visible text exactly."}

        Use the tool output as the image context. Do not answer image-content questions from this placeholder alone.
        """)
    }

    private func fallbackBlock(
        imageIndex: Int,
        mimeType: String?,
        reason: String,
        byteCount: Int = 0,
        report: inout AnthropicImageAttachmentBridgeReport
    ) -> [String: Any] {
        report.fallbackCount += 1
        report.attachments.append(AnthropicImageAttachmentReport(
            imageIndex: imageIndex,
            status: "fallback",
            mimeType: mimeType,
            path: nil,
            byteCount: byteCount,
            reason: reason
        ))
        return textBlock("""
        [Image attachment #\(imageIndex) unavailable for vision-provider]
        The original image was not sent to DeepSeek because DeepSeek is not a multimodal model.
        Raw error: \(reason)
        """)
    }

    private func textBlock(_ text: String) -> [String: Any] {
        [
            "type": "text",
            "text": text.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
    }

    private func fileExtension(for mimeType: String) -> String {
        switch mimeType {
        case "image/jpeg":
            return "jpg"
        case "image/png":
            return "png"
        case "image/gif":
            return "gif"
        case "image/webp":
            return "webp"
        default:
            return "img"
        }
    }

    private func dayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private func safePathComponent(_ value: String) -> String {
        let cleaned = value.unicodeScalars.map { scalar -> String in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                return String(scalar)
            }
            return "-"
        }.joined()
        return cleaned.isEmpty ? UUID().uuidString : cleaned
    }

}
