import Foundation
import DeepSeekAliasProxyCore

func payloadByInjectingSystemPrompt(into payload: [String: Any], settings: ProxySettings) -> [String: Any] {
    guard !settings.systemPromptPrefix.isEmpty || !settings.systemPromptSuffix.isEmpty else {
        return payload
    }

    var payload = payload
    if let system = payload["system"] as? String {
        payload["system"] = settings.systemPromptPrefix + system + settings.systemPromptSuffix
    } else if var blocks = payload["system"] as? [[String: Any]] {
        if !settings.systemPromptPrefix.isEmpty {
            blocks.insert(["type": "text", "text": settings.systemPromptPrefix], at: 0)
        }
        if !settings.systemPromptSuffix.isEmpty {
            blocks.append(["type": "text", "text": settings.systemPromptSuffix])
        }
        payload["system"] = blocks
    } else {
        payload["system"] = settings.systemPromptPrefix + settings.systemPromptSuffix
    }
    return payload
}

func estimatedInputTokens(for payload: [String: Any], settings: ProxySettings) -> Int {
    let injectedPayload = payloadByInjectingSystemPrompt(into: payload, settings: settings)
    let sanitizedPayload = AnthropicPayloadSanitizer.sanitizedForTokenEstimate(injectedPayload) as? [String: Any] ?? injectedPayload
    let imageTokens = AnthropicPayloadSanitizer.imageBlockCount(in: injectedPayload) * AnthropicPayloadSanitizer.estimatedImageTokens
    let relevant: [String: Any?] = [
        "system": sanitizedPayload["system"],
        "messages": sanitizedPayload["messages"],
        "tools": sanitizedPayload["tools"],
        "thinking": sanitizedPayload["thinking"],
        "tool_choice": sanitizedPayload["tool_choice"],
    ]
    let data = (try? JSONSerialization.data(withJSONObject: relevant.compactMapValues { $0 })) ?? Data()
    return max(1, Int(ceil(Double(data.count) / 3.0)) + imageTokens)
}
