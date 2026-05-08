import Foundation
import GatewayProxyCore

func payloadByInjectingSystemPrompt(into payload: [String: Any], injection: String) -> [String: Any] {
    let injection = injection.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !injection.isEmpty else {
        return payload
    }

    var payload = payload
    if let system = payload["system"] as? String {
        payload["system"] = system + "\n\n" + injection
    } else if var blocks = payload["system"] as? [[String: Any]] {
        blocks.append(["type": "text", "text": injection])
        payload["system"] = blocks
    } else {
        payload["system"] = injection
    }
    return payload
}

func estimatedInputTokens(for payload: [String: Any], settings: ProxySettings) -> Int {
    let injectedPayload = payloadByInjectingSystemPrompt(
        into: payload,
        injection: systemPromptInjection(for: payload, settings: settings)
    )
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

private func systemPromptInjection(for payload: [String: Any], settings: ProxySettings) -> String {
    let route = settings.route(for: payload["model"] as? String)
    return settings.provider(id: route.providerID)?.systemPromptInjection ?? ""
}
