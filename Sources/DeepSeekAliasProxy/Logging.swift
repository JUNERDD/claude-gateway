import Foundation

private let gatewayEventPrefix = "CDSG_EVENT "

private final class GatewayLogWriter {
    static let shared = GatewayLogWriter()

    private let lock = NSLock()
    private var handle: FileHandle?
    private var handlePath: String?

    func append(_ line: String) {
        guard let data = line.data(using: .utf8), !data.isEmpty else { return }
        let logURL = gatewayLogURL()
        lock.lock()
        defer { lock.unlock() }

        do {
            let handle = try writeHandle(for: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            closeHandle()
            fputs(line, stderr)
            fflush(stderr)
        }
    }

    private func writeHandle(for logURL: URL) throws -> FileHandle {
        if let handle, handlePath == logURL.path, FileManager.default.fileExists(atPath: logURL.path) {
            return handle
        }

        closeHandle()
        try FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL.path)
        }
        let newHandle = try FileHandle(forWritingTo: logURL)
        handle = newHandle
        handlePath = logURL.path
        return newHandle
    }

    private func closeHandle() {
        try? handle?.close()
        handle = nil
        handlePath = nil
    }
}

func logGatewayEvent(_ event: [String: Any]) {
    var payload = event
    payload["timestamp"] = ISO8601DateFormatter().string(from: Date())
    payload["source"] = "proxy"
    guard JSONSerialization.isValidJSONObject(payload),
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
        let line = String(data: data, encoding: .utf8)
    else {
        return
    }
    appendGatewayLogLine("\(gatewayEventPrefix)\(line)\n")
}

func appendGatewayLogLine(_ line: String) {
    GatewayLogWriter.shared.append(line)
}

func gatewayLogURL() -> URL {
    if let configured = ProcessInfo.processInfo.environment["CLAUDE_DEEPSEEK_GATEWAY_LOG_PATH"],
        !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
        return URL(fileURLWithPath: NSString(string: configured).expandingTildeInPath)
    }

    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
    return appSupport
        .appendingPathComponent("ClaudeDeepSeekGateway", isDirectory: true)
        .appendingPathComponent("proxy.log")
}

func loggableJSON(_ value: Any, depth: Int = 0) -> Any {
    guard depth < 12 else { return "[depth limit]" }

    switch value {
    case let object as [String: Any]:
        var result: [String: Any] = [:]
        for (key, rawValue) in object {
            result[key] = loggableJSON(rawValue, depth: depth + 1)
        }
        return result
    case let array as [Any]:
        let maxItems = 80
        var result = array.prefix(maxItems).map { loggableJSON($0, depth: depth + 1) }
        if array.count > maxItems {
            result.append(["_truncated_items": array.count - maxItems])
        }
        return result
    case let string as String:
        let maxCharacters = 12_000
        if string.count <= maxCharacters {
            return string
        }
        let end = string.index(string.startIndex, offsetBy: maxCharacters)
        return [
            "_truncated": true,
            "characters": string.count,
            "preview": String(string[..<end]),
        ]
    case let number as NSNumber:
        return number
    case is NSNull:
        return NSNull()
    default:
        return String(describing: value)
    }
}

func prettyJSONObject(_ value: Any) -> String? {
    guard JSONSerialization.isValidJSONObject(value),
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}
