import XCTest
@testable import ClaudeDeepSeekGateway

final class GatewayDashboardSnapshotTests: XCTestCase {
    func testSnapshotAggregatesCurrentAndPreviousStructuredEvents() throws {
        let now = try XCTUnwrap(Self.isoFormatter.date(from: "2026-05-07T10:00:00Z"))
        let logText = [
            event([
                "type": "deepseek_request",
                "timestamp": "2026-05-07T09:59:50Z",
                "requestID": "current-ok",
                "method": "POST",
                "path": "/v1/messages",
                "originalModel": "claude-sonnet-4-6",
                "targetModel": "deepseek-v4-pro[1m]",
                "inputTokens": 12,
            ]),
            event([
                "type": "deepseek_response",
                "timestamp": "2026-05-07T09:59:51Z",
                "requestID": "current-ok",
                "status": 200,
                "durationMs": 250,
                "outputTokens": 30,
            ]),
            event([
                "type": "deepseek_request",
                "timestamp": "2026-05-07T09:59:40Z",
                "requestID": "current-error",
                "method": "POST",
                "path": "/v1/messages",
                "originalModel": "claude-haiku-4-5",
                "targetModel": "deepseek-v4-flash",
                "bodyBytes": 120,
            ]),
            event([
                "type": "deepseek_response",
                "timestamp": "2026-05-07T09:59:41Z",
                "requestID": "current-error",
                "status": 429,
                "durationMs": 1_200,
                "outputTokensEstimate": 6,
            ]),
            event([
                "type": "gateway_request",
                "timestamp": "2026-05-07T09:58:30Z",
                "requestID": "previous-ok",
                "method": "GET",
                "path": "/v1/models",
            ]),
            event([
                "type": "gateway_response",
                "timestamp": "2026-05-07T09:58:31Z",
                "requestID": "previous-ok",
                "status": 200,
                "durationMs": 40,
            ]),
        ].joined(separator: "\n")

        let snapshot = GatewayDashboardSnapshot.make(from: logText, range: .oneMinute, now: now)

        XCTAssertEqual(snapshot.totalRequests, 2)
        XCTAssertEqual(snapshot.previousTotalRequests, 1)
        XCTAssertEqual(snapshot.inputTokens, 52)
        XCTAssertEqual(snapshot.outputTokens, 36)
        XCTAssertEqual(snapshot.averageLatencyMs, 725)
        XCTAssertEqual(snapshot.errorRate, 0.5)
        XCTAssertEqual(snapshot.issueCount, 1)
        XCTAssertEqual(snapshot.chartBuckets.reduce(0, +), 2)
        XCTAssertEqual(snapshot.issueRows.map(\.id), ["current-error"])
    }

    private static let isoFormatter = ISO8601DateFormatter()

    private func event(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return "CDSG_EVENT \(String(data: data, encoding: .utf8)!)"
    }
}
