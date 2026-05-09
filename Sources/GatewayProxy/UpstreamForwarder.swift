import Foundation

final class UpstreamForwarder: NSObject, URLSessionDataDelegate {
    private let fd: Int32
    private let requestID: String
    private let providerID: String
    private let compatibilityProfileID: String
    private let startedAt = Date()
    private let done = DispatchSemaphore(value: 0)
    private var sentHeaders = false
    private var transportError: Error?
    private var statusCode = 200
    private var responseHeaders: [String: String] = [:]
    private var receivedBodyBytes = 0
    private var responseBodyPreview = Data()
    private let responsePreviewLimit = 2 * 1024 * 1024

    init(
        fd: Int32,
        requestID: String,
        providerID: String,
        compatibilityProfileID: String = ""
    ) {
        self.fd = fd
        self.requestID = requestID
        self.providerID = providerID
        self.compatibilityProfileID = compatibilityProfileID
    }

    func forward(_ request: URLRequest) {
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        session.dataTask(with: request).resume()
        done.wait()
        session.invalidateAndCancel()

        if let transportError, !sentHeaders {
            let payload: [String: Any] = [
                "error": [
                    "type": "upstream_error",
                    "message": "Gateway upstream request failed: \(transportError.localizedDescription)",
                ],
            ]
            let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
            let response = "HTTP/1.1 502 Bad Gateway\r\ncontent-type: application/json\r\ncontent-length: \(body.count)\r\nconnection: close\r\n\r\n"
            writeAll(fd, Data(response.utf8))
            writeAll(fd, body)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let http = response as? HTTPURLResponse
        statusCode = http?.statusCode ?? 200
        responseHeaders = sanitizedResponseHeaders(http)

        var header = "HTTP/1.1 \(statusCode) \(reasonPhrase(statusCode))\r\n"
        if let http {
            for (key, value) in http.allHeaderFields {
                let name = String(describing: key)
                let lower = name.lowercased()
                if [
                    "connection",
                    "content-length",
                    "keep-alive",
                    "proxy-authenticate",
                    "proxy-authorization",
                    "te",
                    "trailer",
                    "transfer-encoding",
                    "upgrade",
                ].contains(lower) {
                    continue
                }
                header += "\(name): \(value)\r\n"
            }
        }
        header += "connection: close\r\n\r\n"
        sentHeaders = true
        writeAll(fd, Data(header.utf8))
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedBodyBytes += data.count
        if responseBodyPreview.count < responsePreviewLimit {
            let remaining = responsePreviewLimit - responseBodyPreview.count
            responseBodyPreview.append(Data(data.prefix(remaining)))
        }
        writeAll(fd, data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        transportError = error
        if let error {
            logGatewayEvent([
                "type": "gateway_error",
                "requestID": requestID,
                "providerID": providerID,
                "durationMs": Int(Date().timeIntervalSince(startedAt) * 1000),
                "message": error.localizedDescription,
            ])
        } else {
            let usage = Self.extractUsage(from: responseBodyPreview)
            var event: [String: Any] = [
                "type": "gateway_response",
                "requestID": requestID,
                "providerID": providerID,
                "status": statusCode,
                "durationMs": Int(Date().timeIntervalSince(startedAt) * 1000),
                "headers": responseHeaders,
                "responseBodyBytes": receivedBodyBytes,
                "outputTokensEstimate": max(0, Int(ceil(Double(receivedBodyBytes) / 3.0))),
            ]
            if let inputTokens = usage.inputTokens {
                event["inputTokens"] = inputTokens
            }
            if let outputTokens = usage.outputTokens {
                event["outputTokens"] = outputTokens
            }
            logGatewayEvent(event)
            if let issue = Self.detectProviderCompatibilityIssue(
                status: statusCode,
                bodyPreview: responseBodyPreview
            ) {
                logGatewayEvent([
                    "type": "provider_compatibility_issue",
                    "requestID": requestID,
                    "providerID": providerID,
                    "compatibilityProfileID": compatibilityProfileID,
                    "status": statusCode,
                    "category": issue.category,
                    "message": issue.message,
                    "recommendation": issue.recommendation,
                ])
            }
        }
        done.signal()
    }

    private static func detectProviderCompatibilityIssue(
        status: Int,
        bodyPreview: Data
    ) -> (category: String, message: String, recommendation: String)? {
        guard status >= 400,
            let text = String(data: bodyPreview, encoding: .utf8),
            !text.isEmpty
        else {
            return nil
        }

        let lower = text.lowercased()
        if lower.contains("reasoning_content")
            || lower.contains("thinking block")
            || lower.contains("content[].thinking")
            || lower.contains("thinking-mode")
        {
            return (
                "thinking-round-trip",
                "Upstream rejected the request because thinking/reasoning history was not preserved.",
                "Use a provider route that preserves reasoning_content/thinking blocks, fix the adapter/proxy round trip, or switch this workflow to a compatible non-thinking route."
            )
        }

        if lower.contains("anthropic-beta") || lower.contains("beta header") {
            return (
                "anthropic-beta",
                "Upstream rejected an Anthropic beta or experimental header.",
                "Set this provider's Anthropic Beta Header mode to strip, then retry with a fresh Claude Code session."
            )
        }

        if lower.contains("tool_reference")
            || lower.contains("server-side tool")
            || lower.contains("unsupported tool")
            || lower.contains("mcp")
        {
            return (
                "tool-block-support",
                "Upstream appears not to support one of the tool or MCP message blocks in this workflow.",
                "Use local Claude Code tools where possible, disable unsupported server-side tool features, or route this workflow to a compatible provider."
            )
        }

        return nil
    }

    private static func extractUsage(from data: Data) -> (inputTokens: Int?, outputTokens: Int?) {
        guard !data.isEmpty else { return (nil, nil) }
        if let object = decodeJSON(data), let usage = object["usage"] as? [String: Any] {
            return (intValue(usage["input_tokens"]), intValue(usage["output_tokens"]))
        }

        guard let text = String(data: data, encoding: .utf8) else { return (nil, nil) }
        var inputTokens: Int?
        var outputTokens: Int?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]", let eventData = payload.data(using: .utf8),
                let object = decodeJSON(eventData)
            else {
                continue
            }

            if let usage = object["usage"] as? [String: Any] {
                inputTokens = intValue(usage["input_tokens"]) ?? inputTokens
                outputTokens = intValue(usage["output_tokens"]) ?? outputTokens
            }
            if let message = object["message"] as? [String: Any],
                let usage = message["usage"] as? [String: Any]
            {
                inputTokens = intValue(usage["input_tokens"]) ?? inputTokens
                outputTokens = intValue(usage["output_tokens"]) ?? outputTokens
            }
        }

        return (inputTokens, outputTokens)
    }

    private static func decodeJSON(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }
}
