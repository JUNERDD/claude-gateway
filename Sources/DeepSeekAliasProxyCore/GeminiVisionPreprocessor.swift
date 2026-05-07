import Foundation

public struct GeminiVisionConfiguration {
    public var apiKey: String
    public var model: String
    public var apiBaseURL: String

    public init(
        apiKey: String,
        model: String,
        apiBaseURL: String = "https://generativelanguage.googleapis.com"
    ) {
        self.apiKey = apiKey
        self.model = model
        self.apiBaseURL = apiBaseURL
    }

    var cleanAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var cleanModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct GeminiVisionImageRequest {
    public var imageIndex: Int
    public var apiKey: String
    public var model: String
    public var apiBaseURL: String
    public var mimeType: String
    public var base64Data: String
    public var prompt: String

    public init(
        imageIndex: Int,
        apiKey: String,
        model: String,
        apiBaseURL: String,
        mimeType: String,
        base64Data: String,
        prompt: String
    ) {
        self.imageIndex = imageIndex
        self.apiKey = apiKey
        self.model = model
        self.apiBaseURL = apiBaseURL
        self.mimeType = mimeType
        self.base64Data = base64Data
        self.prompt = prompt
    }
}

public struct GeminiVisionDescription {
    public var text: String?
    public var errorMessage: String?
    public var statusCode: Int?
    public var durationMs: Int
    public var responseBodyBytes: Int

    public init(
        text: String?,
        errorMessage: String?,
        statusCode: Int? = nil,
        durationMs: Int,
        responseBodyBytes: Int = 0
    ) {
        self.text = text
        self.errorMessage = errorMessage
        self.statusCode = statusCode
        self.durationMs = durationMs
        self.responseBodyBytes = responseBodyBytes
    }
}

public protocol GeminiVisionDescribing {
    func describeImage(_ request: GeminiVisionImageRequest) -> GeminiVisionDescription
}

public struct GeminiVisionImageReport {
    public var imageIndex: Int
    public var status: String
    public var mimeType: String?
    public var reason: String?
    public var durationMs: Int
    public var responseBodyBytes: Int

    public init(
        imageIndex: Int,
        status: String,
        mimeType: String?,
        reason: String?,
        durationMs: Int,
        responseBodyBytes: Int
    ) {
        self.imageIndex = imageIndex
        self.status = status
        self.mimeType = mimeType
        self.reason = reason
        self.durationMs = durationMs
        self.responseBodyBytes = responseBodyBytes
    }

    public var logObject: [String: Any] {
        var object: [String: Any] = [
            "imageIndex": imageIndex,
            "status": status,
            "durationMs": durationMs,
            "responseBodyBytes": responseBodyBytes,
        ]
        if let mimeType {
            object["mimeType"] = mimeType
        }
        if let reason {
            object["reason"] = reason
        }
        return object
    }
}

public struct GeminiVisionPreprocessReport {
    public var model: String?
    public var imageCount: Int = 0
    public var successCount: Int = 0
    public var fallbackCount: Int = 0
    public var totalDurationMs: Int = 0
    public var images: [GeminiVisionImageReport] = []

    public init(model: String? = nil) {
        self.model = model
    }

    public var didInspectImages: Bool {
        imageCount > 0
    }

    public var logObject: [String: Any] {
        var object: [String: Any] = [
            "imageCount": imageCount,
            "successCount": successCount,
            "fallbackCount": fallbackCount,
            "durationMs": totalDurationMs,
            "images": images.map(\.logObject),
        ]
        if let model {
            object["model"] = model
        }
        return object
    }
}

public struct GeminiVisionPreprocessResult {
    public var payload: [String: Any]
    public var report: GeminiVisionPreprocessReport

    public init(payload: [String: Any], report: GeminiVisionPreprocessReport) {
        self.payload = payload
        self.report = report
    }
}

public final class GeminiRESTVisionClient: GeminiVisionDescribing {
    public init() {}

    public func describeImage(_ request: GeminiVisionImageRequest) -> GeminiVisionDescription {
        let startedAt = Date()
        guard let url = geminiURL(baseURL: request.apiBaseURL, model: request.model) else {
            return GeminiVisionDescription(
                text: nil,
                errorMessage: "Gemini endpoint URL is invalid.",
                durationMs: elapsedMs(since: startedAt)
            )
        }

        let payload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": request.prompt],
                        [
                            "inline_data": [
                                "mime_type": request.mimeType,
                                "data": request.base64Data,
                            ],
                        ],
                    ],
                ],
            ],
            "generation_config": [
                "media_resolution": "MEDIA_RESOLUTION_HIGH",
                "temperature": 0,
            ],
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return GeminiVisionDescription(
                text: nil,
                errorMessage: "Gemini request JSON could not be encoded.",
                durationMs: elapsedMs(since: startedAt)
            )
        }

        var urlRequest = URLRequest(url: url, timeoutInterval: 120)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = body
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(request.apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("claude-deepseek-gateway/1.0", forHTTPHeaderField: "user-agent")

        let semaphore = DispatchSemaphore(value: 0)
        var responseData = Data()
        var response: URLResponse?
        var transportError: Error?

        URLSession.shared.dataTask(with: urlRequest) { data, urlResponse, error in
            if let data {
                responseData = data
            }
            response = urlResponse
            transportError = error
            semaphore.signal()
        }.resume()
        semaphore.wait()

        let statusCode = (response as? HTTPURLResponse)?.statusCode
        let durationMs = elapsedMs(since: startedAt)
        if let transportError {
            return GeminiVisionDescription(
                text: nil,
                errorMessage: "Gemini request failed: \(transportError.localizedDescription)",
                statusCode: statusCode,
                durationMs: durationMs,
                responseBodyBytes: responseData.count
            )
        }

        guard (200..<300).contains(statusCode ?? 0) else {
            return GeminiVisionDescription(
                text: nil,
                errorMessage: extractGeminiError(from: responseData) ?? "Gemini returned HTTP \(statusCode ?? 0).",
                statusCode: statusCode,
                durationMs: durationMs,
                responseBodyBytes: responseData.count
            )
        }

        guard let text = extractGeminiText(from: responseData), !text.isEmpty else {
            return GeminiVisionDescription(
                text: nil,
                errorMessage: "Gemini response did not include text.",
                statusCode: statusCode,
                durationMs: durationMs,
                responseBodyBytes: responseData.count
            )
        }

        return GeminiVisionDescription(
            text: text,
            errorMessage: nil,
            statusCode: statusCode,
            durationMs: durationMs,
            responseBodyBytes: responseData.count
        )
    }

    private func geminiURL(baseURL: String, model: String) -> URL? {
        let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var modelID = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if modelID.hasPrefix("models/") {
            modelID = String(modelID.dropFirst("models/".count))
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
        guard let encodedModel = modelID.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return URL(string: "\(trimmedBase)/v1beta/models/\(encodedModel):generateContent")
    }

    private func elapsedMs(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
    }

    private func extractGeminiText(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = object["candidates"] as? [[String: Any]]
        else {
            return nil
        }

        var parts: [String] = []
        for candidate in candidates {
            guard let content = candidate["content"] as? [String: Any],
                let contentParts = content["parts"] as? [[String: Any]]
            else {
                continue
            }
            for part in contentParts {
                if let text = part["text"] as? String {
                    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        parts.append(cleaned)
                    }
                }
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    private func extractGeminiError(from data: Data) -> String? {
        guard !data.isEmpty,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? [String: Any]
        else {
            return nil
        }
        return error["message"] as? String
    }
}

public final class GeminiVisionPreprocessor {
    private let client: GeminiVisionDescribing
    private let supportedMediaTypes: Set<String> = [
        "image/jpeg",
        "image/png",
        "image/gif",
        "image/webp",
    ]
    private let maxInlineImageBytes = 100 * 1024 * 1024

    public init(client: GeminiVisionDescribing = GeminiRESTVisionClient()) {
        self.client = client
    }

    public func preprocess(
        payload: [String: Any],
        configuration: GeminiVisionConfiguration
    ) -> GeminiVisionPreprocessResult {
        var report = GeminiVisionPreprocessReport(model: configuration.cleanModel.isEmpty ? nil : configuration.cleanModel)
        var transformed = payload
        guard let messages = payload["messages"] as? [Any] else {
            return GeminiVisionPreprocessResult(payload: transformed, report: report)
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

            let surroundingText = surroundingText(in: content)
            var transformedContent: [Any] = []
            transformedContent.reserveCapacity(content.count)

            for rawBlock in content {
                guard let block = rawBlock as? [String: Any],
                    (block["type"] as? String) == "image"
                else {
                    transformedContent.append(rawBlock)
                    continue
                }

                let replacement = replacementBlock(
                    for: block,
                    imageIndex: nextImageIndex,
                    surroundingText: surroundingText,
                    configuration: configuration,
                    report: &report
                )
                transformedContent.append(replacement)
                nextImageIndex += 1
            }

            message["content"] = transformedContent
            transformedMessages.append(message)
        }

        transformed["messages"] = transformedMessages
        return GeminiVisionPreprocessResult(payload: transformed, report: report)
    }

    private func replacementBlock(
        for block: [String: Any],
        imageIndex: Int,
        surroundingText: String,
        configuration: GeminiVisionConfiguration,
        report: inout GeminiVisionPreprocessReport
    ) -> [String: Any] {
        report.imageCount += 1

        let source = block["source"] as? [String: Any]
        let mimeType = (source?["media_type"] as? String)?.lowercased()

        guard !configuration.cleanAPIKey.isEmpty else {
            return fallbackBlock(
                imageIndex: imageIndex,
                mimeType: mimeType,
                reason: "GEMINI_API_KEY is not configured.",
                report: &report
            )
        }
        guard !configuration.cleanModel.isEmpty else {
            return fallbackBlock(
                imageIndex: imageIndex,
                mimeType: mimeType,
                reason: "Gemini Vision Model is not configured.",
                report: &report
            )
        }
        guard let source else {
            return fallbackBlock(
                imageIndex: imageIndex,
                mimeType: nil,
                reason: "Anthropic image source is missing.",
                report: &report
            )
        }
        guard (source["type"] as? String) == "base64" else {
            let sourceType = source["type"] as? String ?? "unknown"
            return fallbackBlock(
                imageIndex: imageIndex,
                mimeType: mimeType,
                reason: "Unsupported image source type: \(sourceType). Only base64 is supported.",
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
            return fallbackBlock(
                imageIndex: imageIndex,
                mimeType: mimeType,
                reason: "Base64 image data is missing.",
                report: &report
            )
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
        guard decoded.count <= maxInlineImageBytes else {
            return fallbackBlock(
                imageIndex: imageIndex,
                mimeType: mimeType,
                reason: "Image is larger than Gemini inline data limit.",
                report: &report
            )
        }

        let request = GeminiVisionImageRequest(
            imageIndex: imageIndex,
            apiKey: configuration.cleanAPIKey,
            model: configuration.cleanModel,
            apiBaseURL: configuration.apiBaseURL,
            mimeType: mimeType,
            base64Data: compactBase64,
            prompt: prompt(forImageIndex: imageIndex, surroundingText: surroundingText)
        )
        let description = client.describeImage(request)
        report.totalDurationMs += description.durationMs

        if let text = description.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            report.successCount += 1
            report.images.append(GeminiVisionImageReport(
                imageIndex: imageIndex,
                status: "success",
                mimeType: mimeType,
                reason: nil,
                durationMs: description.durationMs,
                responseBodyBytes: description.responseBodyBytes
            ))
            return textBlock("""
            [Gemini image recognition result #\(imageIndex)]
            \(text)
            """)
        }

        return fallbackBlock(
            imageIndex: imageIndex,
            mimeType: mimeType,
            reason: description.errorMessage ?? "Gemini returned no usable description.",
            durationMs: description.durationMs,
            responseBodyBytes: description.responseBodyBytes,
            report: &report
        )
    }

    private func fallbackBlock(
        imageIndex: Int,
        mimeType: String?,
        reason: String,
        durationMs: Int = 0,
        responseBodyBytes: Int = 0,
        report: inout GeminiVisionPreprocessReport
    ) -> [String: Any] {
        report.fallbackCount += 1
        report.totalDurationMs += durationMs
        report.images.append(GeminiVisionImageReport(
            imageIndex: imageIndex,
            status: "fallback",
            mimeType: mimeType,
            reason: reason,
            durationMs: durationMs,
            responseBodyBytes: responseBodyBytes
        ))
        return textBlock("""
        [Gemini image recognition failed #\(imageIndex)]
        The original image was not sent to DeepSeek because DeepSeek is not a multimodal model.
        Raw error: \(reason)
        """)
    }

    private func prompt(forImageIndex imageIndex: Int, surroundingText: String) -> String {
        var prompt = """
        You are a vision preprocessor for a downstream text-only language model.
        Analyze image #\(imageIndex) and return a concise but complete text description.
        Include OCR text, UI layout, charts, tables, diagrams, code, visible errors, and details likely to matter to the user's request.
        Do not solve the user's final task unless doing so is necessary to describe the image.
        """
        let cleanedContext = surroundingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedContext.isEmpty {
            prompt += "\n\nSurrounding user text for context:\n\(cleanedContext)"
        }
        return prompt
    }

    private func surroundingText(in content: [Any]) -> String {
        let values = content.compactMap { block -> String? in
            guard let object = block as? [String: Any],
                (object["type"] as? String) == "text",
                let text = object["text"] as? String
            else {
                return nil
            }
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
        let joined = values.joined(separator: "\n")
        if joined.count <= 2_000 {
            return joined
        }
        let end = joined.index(joined.startIndex, offsetBy: 2_000)
        return String(joined[..<end])
    }

    private func textBlock(_ text: String) -> [String: Any] {
        [
            "type": "text",
            "text": text.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
    }
}

public enum AnthropicPayloadSanitizer {
    public static let estimatedImageTokens = 1120

    public static func sanitizedForLogging(_ value: Any) -> Any {
        if let object = value as? [String: Any] {
            if (object["type"] as? String) == "image" {
                var sanitized: [String: Any] = ["type": "image"]
                if let source = object["source"] as? [String: Any] {
                    var sanitizedSource = source
                    if sanitizedSource["data"] != nil {
                        sanitizedSource["data"] = "[base64 image data omitted from logs]"
                    }
                    sanitized["source"] = sanitizedSource
                }
                return sanitized
            }

            var result: [String: Any] = [:]
            for (key, rawValue) in object {
                result[key] = sanitizedForLogging(rawValue)
            }
            return result
        }

        if let array = value as? [Any] {
            return array.map { sanitizedForLogging($0) }
        }

        return value
    }

    public static func sanitizedForTokenEstimate(_ value: Any) -> Any {
        if let object = value as? [String: Any] {
            if (object["type"] as? String) == "image" {
                return [
                    "type": "text",
                    "text": "[Image input omitted from token estimate; approximate visual cost: \(estimatedImageTokens) tokens.]",
                ]
            }

            var result: [String: Any] = [:]
            for (key, rawValue) in object {
                result[key] = sanitizedForTokenEstimate(rawValue)
            }
            return result
        }

        if let array = value as? [Any] {
            return array.map { sanitizedForTokenEstimate($0) }
        }

        return value
    }

    public static func imageBlockCount(in value: Any) -> Int {
        if let object = value as? [String: Any] {
            if (object["type"] as? String) == "image" {
                return 1
            }
            return object.values.reduce(0) { $0 + imageBlockCount(in: $1) }
        }

        if let array = value as? [Any] {
            return array.reduce(0) { $0 + imageBlockCount(in: $1) }
        }

        return 0
    }
}
