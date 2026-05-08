import Darwin
import Foundation
import XCTest
@testable import GatewayProxy

final class GatewayProxyForwardingTests: XCTestCase {
    func testForwardingUsesExplicitRouteProviderAuthHeadersAndStreamsBody() throws {
        let upstream = try FakeAnthropicServer()
        defer { upstream.close() }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatewayProxyForwardingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsURL = tempDirectory.appendingPathComponent("proxy_settings.json")
        let secretsURL = tempDirectory.appendingPathComponent("secrets.json")
        try """
        {
          "host": "127.0.0.1",
          "port": 4000,
          "providers": [{
            "id": "custom",
            "displayName": "Local Fake",
            "baseURL": "http://127.0.0.1:\(upstream.port)",
            "auth": {"type": "x-api-key", "customHeaderName": ""},
            "defaultHeaders": {"x-provider-region": "test-region"},
            "systemPromptInjection": ""
          }],
          "defaultProviderID": "custom",
          "defaultRoute": {"providerID": "custom", "upstreamModel": "provider-default"},
          "modelRoutes": [{"alias": "claude-sonnet-4-6", "providerID": "custom", "upstreamModel": "provider-sonnet"}],
          "visionProvider": "auto",
          "visionProviderModel": "",
          "visionProviderBaseURL": ""
        }
        """.write(to: settingsURL, atomically: true, encoding: .utf8)
        try """
        {
          "localGatewayKey": "sk-local-test",
          "providerSecrets": {
            "custom": {"apiKey": "sk-upstream-test"}
          },
          "visionProviderAPIKey": ""
        }
        """.write(to: secretsURL, atomically: true, encoding: .utf8)

        setenv("GATEWAY_SETTINGS_PATH", settingsURL.path, 1)
        setenv("GATEWAY_SECRETS_PATH", secretsURL.path, 1)
        defer {
            unsetenv("GATEWAY_SETTINGS_PATH")
            unsetenv("GATEWAY_SECRETS_PATH")
        }

        let capturedRequest = upstream.respondOnce(body: "data: {\"type\":\"message_delta\"}\n\ndata: [DONE]\n")

        var sockets = [Int32](repeating: 0, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer {
            close(sockets[0])
            close(sockets[1])
        }

        let proxyFinished = expectation(description: "proxy finished")
        DispatchQueue.global(qos: .userInitiated).async {
            HTTPConnection(fd: sockets[1], localMasterKey: "sk-local-test").handle()
            proxyFinished.fulfill()
        }

        let payload = #"{"model":"claude-sonnet-4-6","stream":true,"messages":[{"role":"user","content":"ping"}]}"#
        let request = """
        POST /v1/messages HTTP/1.1\r
        Host: 127.0.0.1\r
        Authorization: Bearer sk-local-test\r
        Content-Type: application/json\r
        Accept: text/event-stream\r
        Anthropic-Version: 2023-06-01\r
        Content-Length: \(payload.utf8.count)\r
        \r
        \(payload)
        """
        writeAll(sockets[0], Data(request.utf8))
        shutdown(sockets[0], SHUT_WR)

        let response = readAll(from: sockets[0])
        wait(for: [proxyFinished], timeout: 2)

        let upstreamRequest = try capturedRequest.wait()
        XCTAssertTrue(response.contains("HTTP/1.1 200 OK"))
        XCTAssertTrue(response.contains("data: {\"type\":\"message_delta\"}"))
        XCTAssertEqual(upstreamRequest.path, "/v1/messages")
        XCTAssertEqual(upstreamRequest.headers["x-api-key"], "sk-upstream-test")
        XCTAssertEqual(upstreamRequest.headers["x-provider-region"], "test-region")
        XCTAssertTrue(upstreamRequest.body.contains(#""model":"provider-sonnet""#))
        XCTAssertFalse(upstreamRequest.body.contains("claude-sonnet-4-6"))
        XCTAssertFalse(upstreamRequest.body.contains(#""system""#))
    }

    func testForwardingInjectsOnlyRoutedProviderSystemPrompt() throws {
        let upstream = try FakeAnthropicServer()
        defer { upstream.close() }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GatewayProxyForwardingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsURL = tempDirectory.appendingPathComponent("proxy_settings.json")
        let secretsURL = tempDirectory.appendingPathComponent("secrets.json")
        try """
        {
          "host": "127.0.0.1",
          "port": 4000,
          "providers": [
            {
              "id": "default",
              "displayName": "Default Provider",
              "baseURL": "http://127.0.0.1:\(upstream.port)",
              "auth": {"type": "x-api-key", "customHeaderName": ""},
              "defaultHeaders": {},
              "systemPromptInjection": "default provider instruction"
            },
            {
              "id": "routed",
              "displayName": "Routed Provider",
              "baseURL": "http://127.0.0.1:\(upstream.port)",
              "auth": {"type": "x-api-key", "customHeaderName": ""},
              "defaultHeaders": {},
              "systemPromptInjection": "routed provider instruction"
            }
          ],
          "defaultProviderID": "default",
          "defaultRoute": {"providerID": "default", "upstreamModel": "provider-default"},
          "modelRoutes": [{"alias": "claude-sonnet-4-6", "providerID": "routed", "upstreamModel": "provider-sonnet"}],
          "visionProvider": "auto",
          "visionProviderModel": "",
          "visionProviderBaseURL": ""
        }
        """.write(to: settingsURL, atomically: true, encoding: .utf8)
        try """
        {
          "localGatewayKey": "sk-local-test",
          "providerSecrets": {
            "default": {"apiKey": "sk-default-test"},
            "routed": {"apiKey": "sk-routed-test"}
          },
          "visionProviderAPIKey": ""
        }
        """.write(to: secretsURL, atomically: true, encoding: .utf8)

        setenv("GATEWAY_SETTINGS_PATH", settingsURL.path, 1)
        setenv("GATEWAY_SECRETS_PATH", secretsURL.path, 1)
        defer {
            unsetenv("GATEWAY_SETTINGS_PATH")
            unsetenv("GATEWAY_SECRETS_PATH")
        }

        let capturedRequest = upstream.respondOnce(body: #"{"type":"message","content":[]}"#)

        var sockets = [Int32](repeating: 0, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer {
            close(sockets[0])
            close(sockets[1])
        }

        let proxyFinished = expectation(description: "proxy finished")
        DispatchQueue.global(qos: .userInitiated).async {
            HTTPConnection(fd: sockets[1], localMasterKey: "sk-local-test").handle()
            proxyFinished.fulfill()
        }

        let payload = #"{"model":"claude-sonnet-4-6","system":"base","messages":[{"role":"user","content":"ping"}]}"#
        let request = """
        POST /v1/messages HTTP/1.1\r
        Host: 127.0.0.1\r
        Authorization: Bearer sk-local-test\r
        Content-Type: application/json\r
        Accept: application/json\r
        Anthropic-Version: 2023-06-01\r
        Content-Length: \(payload.utf8.count)\r
        \r
        \(payload)
        """
        writeAll(sockets[0], Data(request.utf8))
        shutdown(sockets[0], SHUT_WR)

        _ = readAll(from: sockets[0])
        wait(for: [proxyFinished], timeout: 2)

        let upstreamRequest = try capturedRequest.wait()
        XCTAssertEqual(upstreamRequest.headers["x-api-key"], "sk-routed-test")
        XCTAssertTrue(upstreamRequest.body.contains("base\\n\\nrouted provider instruction"))
        XCTAssertFalse(upstreamRequest.body.contains("default provider instruction"))
    }

    private func readAll(from fd: Int32) -> String {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private final class CapturedHTTPRequestBox {
    private let semaphore = DispatchSemaphore(value: 0)
    private var request: CapturedHTTPRequest?

    func set(_ request: CapturedHTTPRequest) {
        self.request = request
        semaphore.signal()
    }

    func wait() throws -> CapturedHTTPRequest {
        XCTAssertEqual(semaphore.wait(timeout: .now() + 2), .success)
        return try XCTUnwrap(request)
    }
}

private struct CapturedHTTPRequest {
    var path: String
    var headers: [String: String]
    var body: String
}

private final class FakeAnthropicServer {
    let fd: Int32
    let port: Int

    init() throws {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw POSIXError(.EIO) }

        var yes: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(0).bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw POSIXError(.EADDRINUSE) }
        guard listen(socketFD, 1) == 0 else { throw POSIXError(.EIO) }

        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketFD, $0, &length)
            }
        }
        guard nameResult == 0 else { throw POSIXError(.EIO) }
        fd = socketFD
        port = Int(UInt16(bigEndian: bound.sin_port))
    }

    func respondOnce(body: String) -> CapturedHTTPRequestBox {
        let box = CapturedHTTPRequestBox()
        DispatchQueue.global(qos: .userInitiated).async {
            let client = accept(self.fd, nil, nil)
            guard client >= 0 else { return }
            defer { Darwin.close(client) }

            let request = self.readRequest(from: client)
            box.set(request)

            let response = """
            HTTP/1.1 200 OK\r
            content-type: text/event-stream\r
            content-length: \(body.utf8.count)\r
            connection: close\r
            \r
            \(body)
            """
            writeAll(client, Data(response.utf8))
        }
        return box
    }

    func close() {
        Darwin.close(fd)
    }

    private func readRequest(from fd: Int32) -> CapturedHTTPRequest {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var headerEnd: Range<Data.Index>?

        while headerEnd == nil {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
            headerEnd = data.range(of: Data("\r\n\r\n".utf8))
        }

        guard let headerEnd,
            let headerText = String(data: data[..<headerEnd.lowerBound], encoding: .utf8)
        else {
            return CapturedHTTPRequest(path: "", headers: [:], body: "")
        }

        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        let requestParts = lines.first?.split(separator: " ", maxSplits: 2).map(String.init) ?? []
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[String(name)] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        while data.count - bodyStart < contentLength {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        let bodyData = data[bodyStart..<min(data.count, bodyStart + contentLength)]
        return CapturedHTTPRequest(
            path: requestParts.count > 1 ? requestParts[1] : "",
            headers: headers,
            body: String(decoding: bodyData, as: UTF8.self)
        )
    }
}
