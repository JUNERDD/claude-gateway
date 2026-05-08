import Darwin
import Foundation
import DeepSeekAliasProxyCore

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    var urlPath: String {
        path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
    }
}

final class HTTPConnection {
    private let fd: Int32
    private let localMasterKey: String
    private let deepSeekAPIKey: String

    init(fd: Int32, localMasterKey: String, deepSeekAPIKey: String) {
        self.fd = fd
        self.localMasterKey = localMasterKey
        self.deepSeekAPIKey = deepSeekAPIKey
    }

    func handle() {
        defer { close(fd) }

        do {
            let request = try readRequest()
            if writeHealthCheckIfNeeded(request) {
                return
            }

            guard authorized(request) else {
                writeLoggedJSON(status: 401, payload: [
                    "error": [
                        "type": "authentication_error",
                        "message": "Invalid local proxy API key",
                    ],
                ], request: request)
                return
            }

            switch (request.method, request.urlPath) {
            case ("GET", "/v1/models"):
                writeModels(request)
            case ("POST", "/v1/vision/describe"):
                writeVisionDescribe(request)
            case ("POST", "/v1/messages/count_tokens"):
                writeTokenEstimate(request)
            case ("POST", "/v1/messages"):
                forwardMessages(request)
            default:
                writeLoggedJSON(status: 404, payload: ["error": ["message": "Not found"]], request: request)
            }
        } catch {
            writeJSON(status: 400, payload: [
                "error": [
                    "type": "invalid_request_error",
                    "message": error.localizedDescription,
                ],
            ])
        }
    }

    private func writeHealthCheckIfNeeded(_ request: HTTPRequest) -> Bool {
        switch (request.method, request.urlPath) {
        case ("HEAD", "/"), ("HEAD", "/health/liveliness"):
            writeLoggedRawResponse(status: 200, headers: ["content-length": "0"], body: Data(), request: request)
            return true
        case ("GET", "/"), ("GET", "/health/liveliness"):
            writeLoggedJSON(status: 200, payload: ["status": "ok"], request: request)
            return true
        default:
            return false
        }
    }

    private func authorized(_ request: HTTPRequest) -> Bool {
        guard !localMasterKey.isEmpty else { return true }
        return request.headers["authorization"] == "Bearer \(localMasterKey)"
            || request.headers["x-api-key"] == localMasterKey
    }

    private func writeModels(_ request: HTTPRequest) {
        let settings = SettingsLoader.shared.load()
        let created = Int(Date().timeIntervalSince1970)
        let data = settings.advertisedModels.map { model in
            [
                "id": model,
                "object": "model",
                "created": created,
                "owned_by": "deepseek",
            ] as [String: Any]
        }
        writeLoggedJSON(status: 200, payload: [
            "object": "list",
            "data": data,
        ], request: request)
    }

    private func writeTokenEstimate(_ request: HTTPRequest) {
        let payload = (try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]) ?? [:]
        let tokens = estimatedInputTokens(for: payload, settings: SettingsLoader.shared.load())
        writeLoggedJSON(status: 200, payload: ["input_tokens": tokens], request: request, responseFields: [
            "inputTokens": tokens,
        ])
    }

    private func writeVisionDescribe(_ request: HTTPRequest) {
        let requestID = UUID().uuidString
        let startedAt = Date()
        logGatewayEvent([
            "type": "vision_gateway_request",
            "requestID": requestID,
            "method": request.method,
            "path": request.path,
            "bodyBytes": request.body.count,
        ])

        guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
            writeVisionDescribeResponse(
                requestID: requestID,
                status: 400,
                startedAt: startedAt,
                payload: [
                    "error": [
                        "type": "invalid_request_error",
                        "message": "Invalid JSON",
                    ],
                ],
                logFields: ["error": "Invalid JSON"]
            )
            return
        }

        guard let image = firstString(in: payload, keys: ["image", "imagePath", "image_path"]) else {
            writeVisionDescribeResponse(
                requestID: requestID,
                status: 400,
                startedAt: startedAt,
                payload: [
                    "error": [
                        "type": "invalid_request_error",
                        "message": "Vision request image is missing.",
                    ],
                ],
                logFields: ["error": "Vision request image is missing."]
            )
            return
        }

        let settings = SettingsLoader.shared.load()
        let describeRequest = VisionProviderDescribeRequest(
            image: image,
            mimeType: firstString(in: payload, keys: ["mimeType", "mime_type"]),
            prompt: firstString(in: payload, keys: ["prompt"]) ?? defaultVisionPrompt,
            provider: firstString(in: payload, keys: ["provider"]),
            model: firstString(in: payload, keys: ["model"]),
            baseURL: firstString(in: payload, keys: ["baseURL", "base_url"])
        )
        let configuration = VisionProviderRuntimeConfiguration(
            provider: settings.visionProvider,
            model: settings.visionProviderModel,
            baseURL: settings.visionProviderBaseURL,
            environment: ProcessInfo.processInfo.environment
        )

        do {
            let result = try VisionProviderGatewayService().describe(describeRequest, configuration: configuration)
            writeVisionDescribeResponse(
                requestID: requestID,
                status: 200,
                startedAt: startedAt,
                payload: result.jsonObject,
                logFields: [
                    "provider": result.provider,
                    "model": result.model,
                    "providerStatus": result.statusCode ?? NSNull(),
                    "imageBytes": result.imageByteCount,
                    "responseBodyBytes": result.responseBodyBytes,
                ]
            )
        } catch {
            writeVisionDescribeResponse(
                requestID: requestID,
                status: 502,
                startedAt: startedAt,
                payload: [
                    "error": [
                        "type": "vision_provider_error",
                        "message": error.localizedDescription,
                    ],
                ],
                logFields: [
                    "error": error.localizedDescription,
                    "provider": firstString(in: payload, keys: ["provider"]) ?? settings.visionProvider,
                    "model": firstString(in: payload, keys: ["model"]) ?? settings.visionProviderModel,
                ]
            )
        }
    }

    private func forwardMessages(_ request: HTTPRequest) {
        guard var payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
            writeLoggedJSON(status: 400, payload: [
                "error": [
                    "type": "invalid_request_error",
                    "message": "Invalid JSON",
                ],
            ], request: request)
            return
        }

        let settings = SettingsLoader.shared.load()
        let requestID = UUID().uuidString
        let originalModel = payload["model"] as? String

        if let probePayload = CoworkProbeResponse.payloadIfMatched(payload, requestID: requestID) {
            writeLoggedJSON(status: 200, payload: probePayload, request: request, responseFields: [
                "probe": "cowork_connectivity",
                "inputTokens": 1,
                "outputTokens": 1,
            ])
            return
        }

        let attachmentBridgeResult = AnthropicImageAttachmentBridge().bridge(payload: payload, requestID: requestID)
        payload = attachmentBridgeResult.payload
        if attachmentBridgeResult.report.didBridgeImages {
            var logObject = attachmentBridgeResult.report.logObject
            logObject["type"] = "image_attachment_bridge"
            logObject["requestID"] = requestID
            logGatewayEvent(logObject)
        }

        var targetModel = originalModel
        if let original = payload["model"] as? String {
            let target = original.localizedCaseInsensitiveContains("haiku")
                ? settings.haikuTargetModel
                : settings.nonHaikuTargetModel
            payload["model"] = target
            targetModel = target
            if original != target {
                fputs("model rewrite: \(original) -> \(target)\n", stderr)
            }
        }

        payload = payloadByInjectingSystemPrompt(into: payload, settings: settings)

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            writeLoggedJSON(status: 400, payload: [
                "error": [
                    "type": "invalid_request_error",
                    "message": "Invalid JSON payload",
                ],
            ], request: request)
            return
        }

        let targetURLString = settings.anthropicBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + request.path
        guard let targetURL = URL(string: targetURLString) else {
            writeLoggedJSON(status: 502, payload: [
                "error": [
                    "type": "upstream_error",
                    "message": "Invalid DeepSeek Anthropic endpoint",
                ],
            ], request: request)
            return
        }

        var upstream = URLRequest(url: targetURL)
        upstream.httpMethod = "POST"
        upstream.httpBody = body
        upstream.setValue("application/json", forHTTPHeaderField: "content-type")
        upstream.setValue(request.headers["accept"] ?? "application/json", forHTTPHeaderField: "accept")
        upstream.setValue(deepSeekAPIKey, forHTTPHeaderField: "x-api-key")
        upstream.setValue(request.headers["anthropic-version"] ?? "2023-06-01", forHTTPHeaderField: "anthropic-version")
        upstream.setValue("claude-deepseek-gateway/1.0", forHTTPHeaderField: "user-agent")
        if let beta = request.headers["anthropic-beta"] {
            upstream.setValue(beta, forHTTPHeaderField: "anthropic-beta")
        }

        logGatewayEvent([
            "type": "deepseek_request",
            "requestID": requestID,
            "method": "POST",
            "path": request.path,
            "upstreamURL": targetURLString,
            "originalModel": originalModel ?? NSNull(),
            "targetModel": targetModel ?? NSNull(),
            "bodyBytes": body.count,
            "stream": payload["stream"] ?? false,
            "payload": loggableJSON(AnthropicPayloadSanitizer.sanitizedForLogging(payload)),
            "headers": [
                "accept": request.headers["accept"] ?? "application/json",
                "anthropic-version": request.headers["anthropic-version"] ?? "2023-06-01",
                "anthropic-beta": request.headers["anthropic-beta"] ?? "",
                "content-type": "application/json",
                "user-agent": "claude-deepseek-gateway/1.0",
            ],
        ])

        let forwarder = UpstreamForwarder(fd: fd, requestID: requestID)
        forwarder.forward(upstream)
    }

    private var defaultVisionPrompt: String {
        "Describe this image for a downstream agent. Include visible text exactly, important layout/state, diagrams, tables, charts, code, errors, and uncertainty."
    }

    private func firstString(in payload: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = payload[key] as? String else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func writeVisionDescribeResponse(
        requestID: String,
        status: Int,
        startedAt: Date,
        payload: Any,
        logFields: [String: Any]
    ) {
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        writeRawResponse(status: status, headers: ["content-type": "application/json"], body: body)

        var event: [String: Any] = [
            "type": "vision_gateway_response",
            "requestID": requestID,
            "status": status,
            "durationMs": Int(Date().timeIntervalSince(startedAt) * 1000),
            "responseBodyBytes": body.count,
        ]
        for (key, value) in logFields {
            event[key] = value
        }
        logGatewayEvent(event)
    }

    private func readRequest() throws -> HTTPRequest {
        var buffer = Data()
        let delimiter = Data("\r\n\r\n".utf8)
        var temp = [UInt8](repeating: 0, count: 16 * 1024)

        while buffer.range(of: delimiter) == nil {
            let count = Darwin.read(fd, &temp, temp.count)
            if count <= 0 {
                throw NSError(domain: "DeepSeekAliasProxy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty HTTP request"])
            }
            buffer.append(temp, count: count)
            if buffer.count > 2 * 1024 * 1024 {
                throw NSError(domain: "DeepSeekAliasProxy", code: 2, userInfo: [NSLocalizedDescriptionKey: "HTTP headers are too large"])
            }
        }

        guard let headerRange = buffer.range(of: delimiter),
            let headerText = String(data: buffer[..<headerRange.lowerBound], encoding: .utf8)
        else {
            throw NSError(domain: "DeepSeekAliasProxy", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP headers"])
        }

        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let requestLine = lines.first else {
            throw NSError(domain: "DeepSeekAliasProxy", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing request line"])
        }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            throw NSError(domain: "DeepSeekAliasProxy", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid request line"])
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).lowercased()
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        var body = Data(buffer[bodyStart...])
        while body.count < contentLength {
            let count = Darwin.read(fd, &temp, min(temp.count, contentLength - body.count))
            if count <= 0 {
                break
            }
            body.append(temp, count: count)
        }
        if body.count > contentLength {
            body = body.prefix(contentLength)
        }

        return HTTPRequest(
            method: requestParts[0].uppercased(),
            path: requestParts[1],
            headers: headers,
            body: body
        )
    }

    private func writeJSON(status: Int, payload: Any) {
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        writeRawResponse(status: status, headers: ["content-type": "application/json"], body: body)
    }

    private func writeLoggedJSON(
        status: Int,
        payload: Any,
        request: HTTPRequest,
        responseFields: [String: Any] = [:]
    ) {
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        writeLoggedRawResponse(
            status: status,
            headers: ["content-type": "application/json"],
            body: body,
            request: request,
            responseFields: responseFields
        )
    }

    private func writeLoggedRawResponse(
        status: Int,
        headers: [String: String],
        body: Data,
        request: HTTPRequest,
        responseFields: [String: Any] = [:]
    ) {
        let requestID = UUID().uuidString
        let startedAt = Date()
        logGatewayEvent([
            "type": "gateway_request",
            "requestID": requestID,
            "method": request.method,
            "path": request.path,
            "bodyBytes": request.body.count,
        ])

        writeRawResponse(status: status, headers: headers, body: body)

        var event: [String: Any] = [
            "type": "gateway_response",
            "requestID": requestID,
            "status": status,
            "durationMs": Int(Date().timeIntervalSince(startedAt) * 1000),
            "responseBodyBytes": body.count,
        ]
        for (key, value) in responseFields {
            event[key] = value
        }
        logGatewayEvent(event)
    }

    private func writeRawResponse(status: Int, headers: [String: String], body: Data) {
        var response = "HTTP/1.1 \(status) \(reasonPhrase(status))\r\n"
        var normalized = headers
        normalized["connection"] = "close"
        if normalized["content-length"] == nil {
            normalized["content-length"] = String(body.count)
        }
        for (key, value) in normalized {
            response += "\(key): \(value)\r\n"
        }
        response += "\r\n"
        writeAll(fd, Data(response.utf8))
        if !body.isEmpty {
            writeAll(fd, body)
        }
    }
}
