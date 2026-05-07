import Foundation

public enum CoworkProbeResponse {
    public static func payloadIfMatched(_ requestPayload: [String: Any], requestID: String = UUID().uuidString) -> [String: Any]? {
        guard isConnectivityProbe(requestPayload) else { return nil }

        return [
            "id": "msg_gateway_probe_\(requestID.replacingOccurrences(of: "-", with: "").lowercased())",
            "type": "message",
            "role": "assistant",
            "model": (requestPayload["model"] as? String) ?? "claude-haiku-4-5",
            "content": [
                [
                    "type": "text",
                    "text": ".",
                ],
            ],
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 1,
                "output_tokens": 1,
            ],
        ]
    }

    public static func isConnectivityProbe(_ payload: [String: Any]) -> Bool {
        guard intValue(payload["max_tokens"]).map({ $0 <= 1 }) == true else { return false }
        guard (payload["stream"] as? Bool) != true else { return false }
        guard payload["system"] == nil,
            payload["tools"] == nil,
            payload["thinking"] == nil,
            payload["tool_choice"] == nil
        else {
            return false
        }

        guard let messages = payload["messages"] as? [[String: Any]], messages.count == 1 else {
            return false
        }
        let message = messages[0]
        guard (message["role"] as? String) == "user" else { return false }
        return normalizedContentText(message["content"]) == "."
    }

    private static func normalizedContentText(_ content: Any?) -> String? {
        if let text = content as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let blocks = content as? [[String: Any]], blocks.count == 1 else {
            return nil
        }
        let block = blocks[0]
        guard (block["type"] as? String) == "text",
            let text = block["text"] as? String
        else {
            return nil
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
