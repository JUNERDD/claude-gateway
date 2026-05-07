import Foundation

public struct VisionProviderRuntimeConfiguration {
    public var provider: String
    public var model: String
    public var baseURL: String
    public var environment: [String: String]

    public init(
        provider: String,
        model: String,
        baseURL: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.provider = provider
        self.model = model
        self.baseURL = baseURL
        self.environment = environment
    }
}

public struct VisionProviderDescribeRequest {
    public var image: String
    public var mimeType: String?
    public var prompt: String
    public var provider: String?
    public var model: String?
    public var baseURL: String?

    public init(
        image: String,
        mimeType: String? = nil,
        prompt: String,
        provider: String? = nil,
        model: String? = nil,
        baseURL: String? = nil
    ) {
        self.image = image
        self.mimeType = mimeType
        self.prompt = prompt
        self.provider = provider
        self.model = model
        self.baseURL = baseURL
    }
}

public struct VisionProviderDescribeResponse {
    public var provider: String
    public var model: String
    public var text: String
    public var durationMs: Int
    public var statusCode: Int?
    public var responseBodyBytes: Int
    public var imageByteCount: Int

    public var jsonObject: [String: Any] {
        var object: [String: Any] = [
            "provider": provider,
            "model": model,
            "text": text,
            "durationMs": durationMs,
            "responseBodyBytes": responseBodyBytes,
            "imageByteCount": imageByteCount,
        ]
        if let statusCode {
            object["statusCode"] = statusCode
        }
        return object
    }
}

public enum VisionProviderGatewayError: Error, LocalizedError {
    case missingImage
    case unsupportedProvider(String)
    case missingAPIKey(String)
    case unsupportedImageMIMEType(String)
    case invalidDataURL
    case rawBase64RequiresMIMEType
    case invalidBase64(String)
    case unreadableImage(String)
    case invalidEndpoint
    case requestEncodingFailed
    case requestFailed(String)
    case providerHTTP(status: Int, body: String)
    case invalidProviderResponse(String)
    case missingProviderText(String)

    public var errorDescription: String? {
        switch self {
        case .missingImage:
            return "Vision request image is missing."
        case let .unsupportedProvider(provider):
            return "Unsupported vision provider: \(provider)."
        case let .missingAPIKey(provider):
            return "\(provider) API key is required."
        case let .unsupportedImageMIMEType(mimeType):
            return "Unsupported image MIME type: \(mimeType.isEmpty ? "missing" : mimeType)."
        case .invalidDataURL:
            return "Only base64 image data URLs are supported."
        case .rawBase64RequiresMIMEType:
            return "Raw base64 image input requires mimeType."
        case let .invalidBase64(reason):
            return "Invalid base64 image data: \(reason)"
        case let .unreadableImage(reason):
            return "Image file could not be read: \(reason)"
        case .invalidEndpoint:
            return "Vision provider endpoint URL is invalid."
        case .requestEncodingFailed:
            return "Vision provider request JSON could not be encoded."
        case let .requestFailed(reason):
            return "Vision provider request failed: \(reason)"
        case let .providerHTTP(status, body):
            return "Vision provider HTTP \(status): \(body)"
        case let .invalidProviderResponse(body):
            return "Vision provider response was not valid JSON: \(body)"
        case let .missingProviderText(body):
            return "Vision provider response did not include text: \(body)"
        }
    }
}

public final class VisionProviderGatewayService {
    private let supportedMIMETypes: Set<String> = [
        "image/png",
        "image/jpeg",
        "image/webp",
        "image/gif",
    ]

    public init() {}

    public func describe(
        _ request: VisionProviderDescribeRequest,
        configuration: VisionProviderRuntimeConfiguration
    ) throws -> VisionProviderDescribeResponse {
        let startedAt = Date()
        let image = try loadImage(request.image, forcedMIMEType: request.mimeType)
        let provider = resolvedProvider(request.provider, configuration: configuration)
        let model = resolvedModel(request.model, provider: provider, configuration: configuration)
        let baseURL = resolvedBaseURL(request.baseURL, provider: provider, configuration: configuration)
        let apiKey = try resolvedAPIKey(provider: provider, configuration: configuration)

        let providerResponse: ProviderHTTPResponse
        switch provider {
        case "dashscope":
            providerResponse = try describeOpenAICompatible(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                prompt: request.prompt,
                image: image,
                textExtractor: extractOpenAIText
            )
        case "gemini":
            providerResponse = try describeGemini(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                prompt: request.prompt,
                image: image
            )
        case "openai-compatible":
            providerResponse = try describeOpenAICompatible(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                prompt: request.prompt,
                image: image,
                textExtractor: extractOpenAIText
            )
        default:
            throw VisionProviderGatewayError.unsupportedProvider(provider)
        }

        return VisionProviderDescribeResponse(
            provider: provider,
            model: model,
            text: providerResponse.text,
            durationMs: elapsedMs(since: startedAt),
            statusCode: providerResponse.statusCode,
            responseBodyBytes: providerResponse.responseBodyBytes,
            imageByteCount: image.byteCount
        )
    }

    private func describeOpenAICompatible(
        baseURL: String,
        apiKey: String,
        model: String,
        prompt: String,
        image: LoadedVisionImage,
        textExtractor: ([String: Any], Data) throws -> String
    ) throws -> ProviderHTTPResponse {
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:\(image.mimeType);base64,\(image.base64)",
                            ],
                        ],
                    ],
                ],
            ],
            "temperature": 0,
        ]
        let response = try postJSON(
            to: "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/chat/completions",
            payload: payload,
            headers: [
                "content-type": "application/json",
                "authorization": "Bearer \(apiKey)",
            ]
        )
        let text = try textExtractor(response.object, response.body)
        return ProviderHTTPResponse(
            text: text,
            statusCode: response.statusCode,
            responseBodyBytes: response.body.count
        )
    }

    private func describeGemini(
        baseURL: String,
        apiKey: String,
        model: String,
        prompt: String,
        image: LoadedVisionImage
    ) throws -> ProviderHTTPResponse {
        let modelID = model.hasPrefix("models/") ? String(model.dropFirst("models/".count)) : model
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
        guard let encodedModel = modelID.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw VisionProviderGatewayError.invalidEndpoint
        }
        let payload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": image.mimeType,
                                "data": image.base64,
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
        let response = try postJSON(
            to: "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/v1beta/models/\(encodedModel):generateContent",
            payload: payload,
            headers: [
                "content-type": "application/json",
                "x-goog-api-key": apiKey,
            ]
        )
        let text = try extractGeminiText(response.object, response.body)
        return ProviderHTTPResponse(
            text: text,
            statusCode: response.statusCode,
            responseBodyBytes: response.body.count
        )
    }

    private func postJSON(to urlString: String, payload: [String: Any], headers: [String: String]) throws -> JSONHTTPResponse {
        guard let url = URL(string: urlString) else {
            throw VisionProviderGatewayError.invalidEndpoint
        }
        guard JSONSerialization.isValidJSONObject(payload),
            let body = try? JSONSerialization.data(withJSONObject: payload)
        else {
            throw VisionProviderGatewayError.requestEncodingFailed
        }

        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("claude-deepseek-gateway/1.0", forHTTPHeaderField: "user-agent")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var responseData = Data()
        var response: URLResponse?
        var transportError: Error?

        URLSession.shared.dataTask(with: request) { data, urlResponse, error in
            if let data {
                responseData = data
            }
            response = urlResponse
            transportError = error
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let transportError {
            throw VisionProviderGatewayError.requestFailed(transportError.localizedDescription)
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw VisionProviderGatewayError.providerHTTP(status: statusCode, body: responseBodyString(responseData))
        }
        guard let object = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw VisionProviderGatewayError.invalidProviderResponse(responseBodyString(responseData))
        }
        return JSONHTTPResponse(object: object, statusCode: statusCode, body: responseData)
    }

    private func loadImage(_ image: String, forcedMIMEType: String?) throws -> LoadedVisionImage {
        let trimmed = image.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw VisionProviderGatewayError.missingImage
        }

        let mimeType: String
        let base64: String
        let byteCount: Int
        if trimmed.hasPrefix("data:") {
            guard let comma = trimmed.firstIndex(of: ",") else {
                throw VisionProviderGatewayError.invalidDataURL
            }
            let header = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 5)..<comma])
            guard header.contains(";base64") else {
                throw VisionProviderGatewayError.invalidDataURL
            }
            mimeType = normalizeMIMEType(String(header.split(separator: ";", maxSplits: 1).first ?? ""))
            base64 = compactBase64(String(trimmed[trimmed.index(after: comma)...]))
            byteCount = try validatedByteCount(base64)
        } else {
            let path = NSString(string: trimmed).expandingTildeInPath
            if FileManager.default.fileExists(atPath: path) {
                let data: Data
                do {
                    data = try Data(contentsOf: URL(fileURLWithPath: path))
                } catch {
                    throw VisionProviderGatewayError.unreadableImage(error.localizedDescription)
                }
                mimeType = normalizeMIMEType(forcedMIMEType ?? mimeTypeForPath(path))
                base64 = data.base64EncodedString()
                byteCount = data.count
            } else {
                guard let forcedMIMEType, !forcedMIMEType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw VisionProviderGatewayError.rawBase64RequiresMIMEType
                }
                mimeType = normalizeMIMEType(forcedMIMEType)
                base64 = compactBase64(trimmed)
                byteCount = try validatedByteCount(base64)
            }
        }

        guard supportedMIMETypes.contains(mimeType) else {
            throw VisionProviderGatewayError.unsupportedImageMIMEType(mimeType)
        }
        return LoadedVisionImage(mimeType: mimeType, base64: base64, byteCount: byteCount)
    }

    private func validatedByteCount(_ base64: String) throws -> Int {
        guard let data = Data(base64Encoded: base64), !data.isEmpty else {
            throw VisionProviderGatewayError.invalidBase64("data is invalid or empty")
        }
        return data.count
    }

    private func resolvedProvider(
        _ override: String?,
        configuration: VisionProviderRuntimeConfiguration
    ) -> String {
        let explicit = cleanedLowercase(override)
        if !explicit.isEmpty, explicit != "auto" {
            return explicit
        }
        let configured = cleanedLowercase(configuration.provider)
        if !configured.isEmpty, configured != "auto" {
            return configured
        }
        if firstEnvironmentValue(["DASHSCOPE_API_KEY", "VISION_PROVIDER_API_KEY"], configuration: configuration) != nil {
            return "dashscope"
        }
        if firstEnvironmentValue(["GEMINI_API_KEY"], configuration: configuration) != nil {
            return "gemini"
        }
        if firstEnvironmentValue(["OPENAI_API_KEY"], configuration: configuration) != nil {
            return "openai-compatible"
        }
        return "auto"
    }

    private func resolvedModel(
        _ override: String?,
        provider: String,
        configuration: VisionProviderRuntimeConfiguration
    ) -> String {
        let explicit = cleanedString(override)
        if !explicit.isEmpty {
            return explicit
        }
        let configured = cleanedString(configuration.model)
        if !configured.isEmpty {
            return configured
        }
        switch provider {
        case "dashscope":
            return "qwen3-vl-flash"
        case "gemini":
            return "gemini-2.5-flash-lite"
        case "openai-compatible":
            return "gpt-4o-mini"
        default:
            return ""
        }
    }

    private func resolvedBaseURL(
        _ override: String?,
        provider: String,
        configuration: VisionProviderRuntimeConfiguration
    ) -> String {
        let explicit = cleanedString(override)
        if !explicit.isEmpty {
            return explicit
        }
        let configured = cleanedString(configuration.baseURL)
        if !configured.isEmpty {
            return configured
        }
        switch provider {
        case "dashscope":
            return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case "gemini":
            return "https://generativelanguage.googleapis.com"
        case "openai-compatible":
            return "https://api.openai.com/v1"
        default:
            return ""
        }
    }

    private func resolvedAPIKey(
        provider: String,
        configuration: VisionProviderRuntimeConfiguration
    ) throws -> String {
        let names: [String]
        switch provider {
        case "dashscope":
            names = ["DASHSCOPE_API_KEY", "VISION_PROVIDER_API_KEY"]
        case "gemini":
            names = ["GEMINI_API_KEY", "VISION_PROVIDER_API_KEY"]
        case "openai-compatible":
            names = ["OPENAI_API_KEY", "VISION_PROVIDER_API_KEY"]
        default:
            throw VisionProviderGatewayError.unsupportedProvider(provider)
        }
        guard let value = firstEnvironmentValue(names, configuration: configuration) else {
            throw VisionProviderGatewayError.missingAPIKey(provider)
        }
        return value
    }

    private func extractOpenAIText(_ response: [String: Any], _ body: Data) throws -> String {
        guard let choices = response["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"]
        else {
            throw VisionProviderGatewayError.missingProviderText(responseBodyString(body))
        }

        let text: String
        if let string = content as? String {
            text = string
        } else if let parts = content as? [[String: Any]] {
            text = parts.compactMap { part in
                (part["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }.joined(separator: "\n")
        } else {
            text = ""
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw VisionProviderGatewayError.missingProviderText(responseBodyString(body))
        }
        return trimmed
    }

    private func extractGeminiText(_ response: [String: Any], _ body: Data) throws -> String {
        let candidates = response["candidates"] as? [[String: Any]] ?? []
        let parts = candidates.flatMap { candidate -> [String] in
            guard let content = candidate["content"] as? [String: Any],
                let parts = content["parts"] as? [[String: Any]]
            else { return [] }
            return parts.compactMap { part in
                (part["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }.filter { !$0.isEmpty }

        guard !parts.isEmpty else {
            throw VisionProviderGatewayError.missingProviderText(responseBodyString(body))
        }
        return parts.joined(separator: "\n\n")
    }

    private func firstEnvironmentValue(
        _ names: [String],
        configuration: VisionProviderRuntimeConfiguration
    ) -> String? {
        for name in names {
            let value = configuration.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func cleanedString(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func cleanedLowercase(_ value: String?) -> String {
        cleanedString(value).lowercased()
    }

    private func compactBase64(_ value: String) -> String {
        value.components(separatedBy: .whitespacesAndNewlines).joined()
    }

    private func normalizeMIMEType(_ value: String) -> String {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered == "image/jpg" ? "image/jpeg" : lowered
    }

    private func mimeTypeForPath(_ path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        default:
            return ""
        }
    }

    private func responseBodyString(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
    }

    private func elapsedMs(since startedAt: Date) -> Int {
        Int(Date().timeIntervalSince(startedAt) * 1000)
    }
}

private struct LoadedVisionImage {
    var mimeType: String
    var base64: String
    var byteCount: Int
}

private struct JSONHTTPResponse {
    var object: [String: Any]
    var statusCode: Int
    var body: Data
}

private struct ProviderHTTPResponse {
    var text: String
    var statusCode: Int?
    var responseBodyBytes: Int
}
