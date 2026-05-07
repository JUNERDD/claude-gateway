import Foundation

enum GatewayLogParser {
    private static let structuredPrefix = "CDSG_EVENT "

    static func parse(_ text: String) -> [GatewayLogEvent] {
        let context = ParseContext()
        var parsed: [GatewayLogEvent] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        parsed.reserveCapacity(min(lines.count, 5_000))

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix(structuredPrefix) {
                let jsonText = String(trimmed.dropFirst(structuredPrefix.count))
                if let event = parseStructured(jsonText, fallbackID: "structured-\(index)", context: context) {
                    parsed.append(event)
                    continue
                }
            }

            parsed.append(parsePlain(trimmed, index: index))
        }

        return Array(parsed.suffix(5_000)).map { $0.indexedForSearch() }
    }

    private static func parseStructured(_ jsonText: String, fallbackID: String, context: ParseContext) -> GatewayLogEvent? {
        guard let data = jsonText.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let timestamp = shortTimestamp(object["timestamp"] as? String, context: context)
        let requestID = object["requestID"] as? String
        let id = requestID.map { "\(fallbackID)-\($0)-\(object["type"] as? String ?? "event")" } ?? fallbackID
        let type = object["type"] as? String ?? "event"

        switch type {
        case "deepseek_request", "gateway_request":
            let original = object["originalModel"] as? String ?? "-"
            let target = object["targetModel"] as? String ?? "-"
            let method = object["method"] as? String ?? "POST"
            let path = object["path"] as? String ?? "/v1/messages"
            let payload = object["payload"]
            return GatewayLogEvent(
                id: id,
                timestamp: timestamp,
                tone: .request,
                title: type == "gateway_request" ? "Gateway 请求" : "DeepSeek 请求",
                subtitle: "\(method) \(path)",
                fields: [
                    GatewayLogField(label: "模型", value: original == target ? target : "\(original) -> \(target)"),
                    GatewayLogField(label: "stream", value: stringValue(object["stream"])),
                    GatewayLogField(label: "body", value: "\(object["bodyBytes"] as? Int ?? 0) bytes"),
                ],
                detailTitle: "DeepSeek 参数",
                detailJSON: prettyJSON(payload ?? object)
            )

        case "deepseek_response", "gateway_response":
            let status = object["status"] as? Int ?? 0
            let duration = object["durationMs"] as? Int ?? 0
            var fields = [
                GatewayLogField(label: "耗时", value: "\(duration) ms"),
                GatewayLogField(label: "request", value: shortRequestID(requestID)),
            ]
            if let outputTokens = object["outputTokens"] as? Int {
                fields.append(GatewayLogField(label: "output", value: "\(outputTokens) tokens"))
            } else if let estimate = object["outputTokensEstimate"] as? Int {
                fields.append(GatewayLogField(label: "output", value: "~\(estimate) tokens"))
            }
            if let responseBodyBytes = object["responseBodyBytes"] as? Int {
                fields.append(GatewayLogField(label: "body", value: "\(responseBodyBytes) bytes"))
            }
            return GatewayLogEvent(
                id: id,
                timestamp: timestamp,
                tone: (200..<300).contains(status) ? .response : .warning,
                title: type == "gateway_response" ? "Gateway 响应" : "DeepSeek 响应",
                subtitle: "HTTP \(status)",
                fields: fields,
                detailTitle: "响应元数据",
                detailJSON: prettyJSON(object)
            )

        case "deepseek_error":
            return GatewayLogEvent(
                id: id,
                timestamp: timestamp,
                tone: .error,
                title: "DeepSeek 请求失败",
                subtitle: object["message"] as? String ?? "Upstream error",
                fields: [
                    GatewayLogField(label: "耗时", value: "\(object["durationMs"] as? Int ?? 0) ms"),
                    GatewayLogField(label: "request", value: shortRequestID(requestID)),
                ],
                detailTitle: "错误详情",
                detailJSON: prettyJSON(object)
            )

        case "gemini_vision_preprocess":
            let imageCount = object["imageCount"] as? Int ?? 0
            let successCount = object["successCount"] as? Int ?? 0
            let fallbackCount = object["fallbackCount"] as? Int ?? 0
            let duration = object["durationMs"] as? Int ?? 0
            let model = object["model"] as? String ?? "-"
            return GatewayLogEvent(
                id: id,
                timestamp: timestamp,
                tone: fallbackCount > 0 ? .warning : .request,
                title: "Gemini 图片预处理",
                subtitle: "\(successCount)/\(imageCount) 张成功",
                fields: [
                    GatewayLogField(label: "模型", value: model),
                    GatewayLogField(label: "降级", value: "\(fallbackCount)"),
                    GatewayLogField(label: "耗时", value: "\(duration) ms"),
                    GatewayLogField(label: "request", value: shortRequestID(requestID)),
                ],
                detailTitle: "Gemini 图片预处理",
                detailJSON: prettyJSON(object)
            )

        case "image_attachment_bridge":
            let imageCount = object["imageCount"] as? Int ?? 0
            let savedCount = object["savedCount"] as? Int ?? 0
            let fallbackCount = object["fallbackCount"] as? Int ?? 0
            let totalBytes = object["totalBytes"] as? Int ?? 0
            return GatewayLogEvent(
                id: id,
                timestamp: timestamp,
                tone: fallbackCount > 0 ? .warning : .request,
                title: "图片附件桥接",
                subtitle: "\(savedCount)/\(imageCount) 张已保存",
                fields: [
                    GatewayLogField(label: "降级", value: "\(fallbackCount)"),
                    GatewayLogField(label: "大小", value: "\(totalBytes) bytes"),
                    GatewayLogField(label: "request", value: shortRequestID(requestID)),
                ],
                detailTitle: "图片附件桥接",
                detailJSON: prettyJSON(object)
            )

        case "vision_gateway_request":
            return GatewayLogEvent(
                id: id,
                timestamp: timestamp,
                tone: .request,
                title: "Vision MCP 请求",
                subtitle: object["path"] as? String ?? "/v1/vision/describe",
                fields: [
                    GatewayLogField(label: "body", value: "\(object["bodyBytes"] as? Int ?? 0) bytes"),
                    GatewayLogField(label: "request", value: shortRequestID(requestID)),
                ],
                detailTitle: "Vision MCP 请求",
                detailJSON: prettyJSON(object)
            )

        case "vision_gateway_response":
            let status = object["status"] as? Int ?? 0
            let duration = object["durationMs"] as? Int ?? 0
            let provider = object["provider"] as? String ?? "-"
            let model = object["model"] as? String ?? "-"
            return GatewayLogEvent(
                id: id,
                timestamp: timestamp,
                tone: (200..<300).contains(status) ? .response : .error,
                title: "Vision MCP 响应",
                subtitle: "HTTP \(status)",
                fields: [
                    GatewayLogField(label: "provider", value: provider),
                    GatewayLogField(label: "模型", value: model),
                    GatewayLogField(label: "图片", value: "\(object["imageBytes"] as? Int ?? 0) bytes"),
                    GatewayLogField(label: "耗时", value: "\(duration) ms"),
                    GatewayLogField(label: "request", value: shortRequestID(requestID)),
                ],
                detailTitle: "Vision MCP 响应",
                detailJSON: prettyJSON(object)
            )

        default:
            return GatewayLogEvent(
                id: id,
                timestamp: timestamp,
                tone: .info,
                title: type,
                subtitle: "结构化事件",
                fields: [],
                detailTitle: "事件 JSON",
                detailJSON: prettyJSON(object)
            )
        }
    }

    private static func parsePlain(_ line: String, index: Int) -> GatewayLogEvent {
        let tone: GatewayLogTone
        if line.localizedCaseInsensitiveContains("error") || line.contains("错误") || line.contains("失败") {
            tone = .error
        } else if line.localizedCaseInsensitiveContains("warn") || line.contains("警告") {
            tone = .warning
        } else {
            tone = .info
        }

        if line.hasPrefix("model rewrite: ") {
            let mapping = line.replacingOccurrences(of: "model rewrite: ", with: "")
            return GatewayLogEvent(
                id: "plain-\(index)-\(line.hashValue)",
                timestamp: "",
                tone: .request,
                title: "模型映射",
                subtitle: mapping,
                fields: [],
                detailTitle: nil,
                detailJSON: nil
            )
        }

        return GatewayLogEvent(
            id: "plain-\(index)-\(line.hashValue)",
            timestamp: "",
            tone: tone,
            title: cleanedPlainTitle(line),
            subtitle: "",
            fields: [],
            detailTitle: nil,
            detailJSON: nil
        )
    }

    private static func cleanedPlainTitle(_ value: String) -> String {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: "—- "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func prettyJSON(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func stringValue(_ value: Any?) -> String {
        switch value {
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            return number.stringValue
        case let string as String:
            return string
        case nil:
            return "-"
        default:
            return String(describing: value!)
        }
    }

    private static func shortTimestamp(_ value: String?, context: ParseContext) -> String {
        guard let value, !value.isEmpty else { return "" }
        if let date = context.isoFormatter.date(from: value) {
            return context.timeFormatter.string(from: date)
        }
        return String(value.suffix(8))
    }

    private static func shortRequestID(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return String(value.prefix(8))
    }

    private final class ParseContext {
        let isoFormatter = ISO8601DateFormatter()
        let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }()
    }
}
