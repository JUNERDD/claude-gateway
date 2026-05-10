import XCTest
@testable import ClaudeGateway

final class GatewayDashboardSnapshotTests: XCTestCase {
    func testSnapshotAggregatesCurrentAndPreviousStructuredEvents() throws {
        let now = try XCTUnwrap(Self.isoFormatter.date(from: "2026-05-07T10:00:00Z"))
        let logText = [
            event([
                "type": "gateway_request",
                "timestamp": "2026-05-07T09:59:50Z",
                "requestID": "current-ok",
                "method": "POST",
                "path": "/v1/messages",
                "originalModel": "claude-sonnet-4-6",
                "targetModel": "provider-sonnet",
                "inputTokens": 12,
            ]),
            event([
                "type": "gateway_response",
                "timestamp": "2026-05-07T09:59:51Z",
                "requestID": "current-ok",
                "status": 200,
                "durationMs": 250,
                "outputTokens": 30,
                "cacheCreationInputTokens": 8,
                "cacheReadInputTokens": 4,
            ]),
            event([
                "type": "gateway_request",
                "timestamp": "2026-05-07T09:59:40Z",
                "requestID": "current-error",
                "method": "POST",
                "path": "/v1/messages",
                "originalModel": "claude-haiku-4-5",
                "targetModel": "provider-haiku",
                "bodyBytes": 120,
            ]),
            event([
                "type": "gateway_response",
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
        XCTAssertEqual(snapshot.inputTokens, 52)
        XCTAssertEqual(snapshot.outputTokens, 36)
        XCTAssertEqual(snapshot.cacheCreationInputTokens, 8)
        XCTAssertEqual(snapshot.cacheReadInputTokens, 4)
        XCTAssertEqual(snapshot.cacheMissTokens, 0)
        XCTAssertEqual(snapshot.cacheHitRate, 4.0 / 64.0, accuracy: 1e-9)
        XCTAssertEqual(snapshot.averageLatencyMs, 725)
        XCTAssertEqual(snapshot.errorRate, 0.5)
        XCTAssertEqual(snapshot.issueCount, 1)
        XCTAssertEqual(snapshot.chartBuckets.reduce(0, +), 2)
        XCTAssertEqual(snapshot.issueRows.map(\.id), ["current-error"])
    }

    func testSnapshotUsesDeepSeekCacheHitRateWhenCacheMissTokensPresent() throws {
        let now = try XCTUnwrap(Self.isoFormatter.date(from: "2026-05-07T10:00:00Z"))
        let logText = [
            event([
                "type": "gateway_request",
                "timestamp": "2026-05-07T09:59:50Z",
                "requestID": "ds-ok",
                "method": "POST",
                "path": "/v1/messages",
                "originalModel": "claude-sonnet-4-6",
                "targetModel": "deepseek-v4-pro[1m]",
                "inputTokens": 200,
            ]),
            event([
                "type": "gateway_response",
                "timestamp": "2026-05-07T09:59:51Z",
                "requestID": "ds-ok",
                "status": 200,
                "durationMs": 300,
                "outputTokens": 50,
                "cacheReadInputTokens": 120,
                "cacheMissTokens": 80,
            ]),
        ].joined(separator: "\n")

        let snapshot = GatewayDashboardSnapshot.make(from: logText, range: .oneMinute, now: now)

        XCTAssertEqual(snapshot.totalRequests, 1)
        XCTAssertEqual(snapshot.inputTokens, 200)
        XCTAssertEqual(snapshot.cacheCreationInputTokens, 0)
        XCTAssertEqual(snapshot.cacheReadInputTokens, 120)
        XCTAssertEqual(snapshot.cacheMissTokens, 80)
        // DeepSeek path: hits / (hits + misses) = 120 / 200
        XCTAssertEqual(snapshot.cacheHitRate, 120.0 / 200.0, accuracy: 1e-9)
    }

    @MainActor
    func testDashboardStoreRecomputesChartWhenLogTailIsUnchanged() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeGatewayTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let logURL = tempDirectory.appendingPathComponent("proxy.log")
        let logText = event([
            "type": "gateway_request",
            "timestamp": "2026-05-07T09:59:50Z",
            "requestID": "rolling-request",
            "method": "GET",
            "path": "/v1/models",
        ])
        try Data(logText.utf8).write(to: logURL)

        var now = try XCTUnwrap(Self.isoFormatter.date(from: "2026-05-07T10:00:00Z"))
        let logStore = PersistentLogStore(fileURL: logURL)
        let dashboard = GatewayDashboardStore(now: { now })

        dashboard.reload(from: logStore, range: .oneMinute)
        try await waitForDashboard(dashboard) { snapshot in
            snapshot.generatedAt == now && snapshot.totalRequests == 1
        }
        let initialBuckets = dashboard.snapshot.chartBuckets

        now = try XCTUnwrap(Self.isoFormatter.date(from: "2026-05-07T10:00:06Z"))
        dashboard.reload(from: logStore, range: .oneMinute)
        try await waitForDashboard(dashboard) { snapshot in
            snapshot.generatedAt == now
        }

        XCTAssertEqual(dashboard.snapshot.totalRequests, 1)
        XCTAssertNotEqual(dashboard.snapshot.chartBuckets, initialBuckets)
        XCTAssertEqual(dashboard.snapshot.chartBuckets.reduce(0, +), 1)
    }

    private static let isoFormatter = ISO8601DateFormatter()

    @MainActor
    private func waitForDashboard(
        _ dashboard: GatewayDashboardStore,
        matching predicate: (GatewayDashboardSnapshot) -> Bool
    ) async throws {
        for _ in 0..<80 {
            if predicate(dashboard.snapshot) {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for dashboard snapshot update")
    }

    private func event(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return "CG_EVENT \(String(data: data, encoding: .utf8)!)"
    }
}
