import Darwin
import Foundation

private let gatewayEventPrefix = "CDSG_EVENT "

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
    fputs("\(gatewayEventPrefix)\(line)\n", stderr)
    fflush(stderr)
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

struct ProxySettings {
    var host: String = "127.0.0.1"
    var port: Int = 4000
    var anthropicBaseURL: String = "https://api.deepseek.com/anthropic"
    var haikuTargetModel: String = "deepseek-v4-flash"
    var nonHaikuTargetModel: String = "deepseek-v4-pro[1m]"
    var advertisedModels: [String] = [
        "claude-opus-4-7",
        "claude-sonnet-4-6",
        "claude-haiku-4-5",
    ]
}

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    var urlPath: String {
        path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
    }
}

final class SettingsLoader {
    static let shared = SettingsLoader()

    private var cached: ProxySettings?
    private var cachedMTime: timespec?

    func load() -> ProxySettings {
        let path = settingsPath()
        var statBuffer = stat()
        let exists = stat(path, &statBuffer) == 0
        let mtime = exists ? statBuffer.st_mtimespec : nil

        if let cached, sameMTime(cachedMTime, mtime) {
            return cached
        }

        var settings = ProxySettings()
        if exists,
            let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            if let value = cleanString(object["host"]) {
                settings.host = value
            }
            if let value = object["port"] as? Int {
                settings.port = value
            }
            if let value = cleanString(object["anthropicBaseURL"]) {
                settings.anthropicBaseURL = value
            }
            if let value = cleanString(object["haikuTargetModel"]) {
                settings.haikuTargetModel = value
            }
            if let value = cleanString(object["nonHaikuTargetModel"]) {
                settings.nonHaikuTargetModel = value
            }
            if let models = object["advertisedModels"] as? [String] {
                let cleaned = uniqueNonEmpty(models)
                if !cleaned.isEmpty {
                    settings.advertisedModels = cleaned
                }
            }
        }

        if let override = ProcessInfo.processInfo.environment["DEEPSEEK_ANTHROPIC_BASE_URL"],
            !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            settings.anthropicBaseURL = override.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        cached = settings
        cachedMTime = mtime
        return settings
    }

    private func settingsPath() -> String {
        if let configured = ProcessInfo.processInfo.environment["ALIAS_PROXY_SETTINGS_PATH"], !configured.isEmpty {
            return NSString(string: configured).expandingTildeInPath
        }
        return "\(NSHomeDirectory())/.config/claude-deepseek-gateway/proxy_settings.json"
    }

    private func cleanString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, !seen.contains(cleaned) else { continue }
            seen.insert(cleaned)
            result.append(cleaned)
        }
        return result
    }

    private func sameMTime(_ lhs: timespec?, _ rhs: timespec?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (l?, r?):
            return l.tv_sec == r.tv_sec && l.tv_nsec == r.tv_nsec
        default:
            return false
        }
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
            guard authorized(request) else {
                writeJSON(status: 401, payload: [
                    "error": [
                        "type": "authentication_error",
                        "message": "Invalid local proxy API key",
                    ],
                ])
                return
            }

            switch (request.method, request.urlPath) {
            case ("HEAD", "/"), ("HEAD", "/health/liveliness"):
                writeRawResponse(status: 200, headers: ["content-length": "0"], body: Data())
            case ("GET", "/"), ("GET", "/health/liveliness"):
                writeJSON(status: 200, payload: ["status": "ok"])
            case ("GET", "/v1/models"):
                writeModels()
            case ("POST", "/v1/messages/count_tokens"):
                writeTokenEstimate(request)
            case ("POST", "/v1/messages"):
                forwardMessages(request)
            default:
                writeJSON(status: 404, payload: ["error": ["message": "Not found"]])
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

    private func authorized(_ request: HTTPRequest) -> Bool {
        guard !localMasterKey.isEmpty else { return true }
        return request.headers["authorization"] == "Bearer \(localMasterKey)"
            || request.headers["x-api-key"] == localMasterKey
    }

    private func writeModels() {
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
        writeJSON(status: 200, payload: [
            "object": "list",
            "data": data,
        ])
    }

    private func writeTokenEstimate(_ request: HTTPRequest) {
        let payload = (try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]) ?? [:]
        let relevant: [String: Any?] = [
            "system": payload["system"],
            "messages": payload["messages"],
            "tools": payload["tools"],
            "thinking": payload["thinking"],
            "tool_choice": payload["tool_choice"],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: relevant.compactMapValues { $0 })) ?? Data()
        let tokens = max(1, Int(ceil(Double(data.count) / 3.0)))
        writeJSON(status: 200, payload: ["input_tokens": tokens])
    }

    private func forwardMessages(_ request: HTTPRequest) {
        guard var payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
            writeJSON(status: 400, payload: [
                "error": [
                    "type": "invalid_request_error",
                    "message": "Invalid JSON",
                ],
            ])
            return
        }

        let settings = SettingsLoader.shared.load()
        let requestID = UUID().uuidString
        let originalModel = payload["model"] as? String
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

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            writeJSON(status: 400, payload: [
                "error": [
                    "type": "invalid_request_error",
                    "message": "Invalid JSON payload",
                ],
            ])
            return
        }

        let targetURLString = settings.anthropicBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + request.path
        guard let targetURL = URL(string: targetURLString) else {
            writeJSON(status: 502, payload: [
                "error": [
                    "type": "upstream_error",
                    "message": "Invalid DeepSeek Anthropic endpoint",
                ],
            ])
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
            "payload": loggableJSON(payload),
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

final class UpstreamForwarder: NSObject, URLSessionDataDelegate {
    private let fd: Int32
    private let requestID: String
    private let startedAt = Date()
    private let done = DispatchSemaphore(value: 0)
    private var sentHeaders = false
    private var transportError: Error?

    init(fd: Int32, requestID: String) {
        self.fd = fd
        self.requestID = requestID
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
                    "message": "DeepSeek upstream request failed: \(transportError.localizedDescription)",
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
        let status = http?.statusCode ?? 200
        logGatewayEvent([
            "type": "deepseek_response",
            "requestID": requestID,
            "status": status,
            "durationMs": Int(Date().timeIntervalSince(startedAt) * 1000),
            "headers": sanitizedResponseHeaders(http),
        ])
        var header = "HTTP/1.1 \(status) \(reasonPhrase(status))\r\n"
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
        writeAll(fd, data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        transportError = error
        if let error {
            logGatewayEvent([
                "type": "deepseek_error",
                "requestID": requestID,
                "durationMs": Int(Date().timeIntervalSince(startedAt) * 1000),
                "message": error.localizedDescription,
            ])
        }
        done.signal()
    }
}

func sanitizedResponseHeaders(_ response: HTTPURLResponse?) -> [String: String] {
    guard let response else { return [:] }
    var result: [String: String] = [:]
    for (key, value) in response.allHeaderFields {
        let name = String(describing: key)
        let lower = name.lowercased()
        guard !["set-cookie", "authorization", "x-api-key"].contains(lower) else { continue }
        result[name] = String(describing: value)
    }
    return result
}

func writeAll(_ fd: Int32, _ data: Data) {
    data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else { return }
        var written = 0
        while written < data.count {
            let result = Darwin.write(fd, baseAddress.advanced(by: written), data.count - written)
            if result <= 0 {
                return
            }
            written += result
        }
    }
}

func reasonPhrase(_ status: Int) -> String {
    switch status {
    case 200: return "OK"
    case 400: return "Bad Request"
    case 401: return "Unauthorized"
    case 404: return "Not Found"
    case 502: return "Bad Gateway"
    default: return "OK"
    }
}

func openServerSocket(host: String, port: Int) throws -> Int32 {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "socket() failed"])
    }

    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(port).bigEndian
    if inet_pton(AF_INET, host, &address.sin_addr) != 1 {
        close(fd)
        throw NSError(domain: "DeepSeekAliasProxy", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid bind host \(host)"])
    }

    let bindResult = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else {
        let code = errno
        close(fd)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey: "bind(\(host):\(port)) failed"])
    }

    guard listen(fd, SOMAXCONN) == 0 else {
        let code = errno
        close(fd)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey: "listen() failed"])
    }

    return fd
}

signal(SIGPIPE, SIG_IGN)

let environment = ProcessInfo.processInfo.environment
guard let deepSeekAPIKey = environment["DEEPSEEK_API_KEY"], !deepSeekAPIKey.isEmpty, deepSeekAPIKey != "replace_me" else {
    fputs("DEEPSEEK_API_KEY is required\n", stderr)
    exit(1)
}

let settings = SettingsLoader.shared.load()
let host = environment["GATEWAY_HOST"] ?? settings.host
let port = Int(environment["GATEWAY_PORT"] ?? "") ?? settings.port
let masterKey = environment["LOCAL_GATEWAY_KEY"] ?? ""
let serverFD = try openServerSocket(host: host, port: port)

print("Claude DeepSeek Gateway: http://\(host):\(port)")
print("Model rewrite: *haiku* -> \(settings.haikuTargetModel); other -> \(settings.nonHaikuTargetModel)")
print("Advertised models: \(settings.advertisedModels.joined(separator: ", "))")
fflush(stdout)

while true {
    let client = accept(serverFD, nil, nil)
    if client < 0 {
        if errno == EINTR {
            continue
        }
        break
    }
    DispatchQueue.global(qos: .userInitiated).async {
        HTTPConnection(fd: client, localMasterKey: masterKey, deepSeekAPIKey: deepSeekAPIKey).handle()
    }
}
