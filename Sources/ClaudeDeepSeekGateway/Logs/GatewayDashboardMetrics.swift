import Combine
import Foundation

enum GatewayDashboardRange: String, CaseIterable, Hashable, Identifiable {
    case oneMinute = "1m"
    case fiveMinutes = "5m"
    case oneHour = "1h"
    case oneDay = "24h"

    var id: String { rawValue }

    var duration: TimeInterval {
        switch self {
        case .oneMinute:
            return 60
        case .fiveMinutes:
            return 5 * 60
        case .oneHour:
            return 60 * 60
        case .oneDay:
            return 24 * 60 * 60
        }
    }

    var comparisonLabel: String {
        "vs previous \(rawValue)"
    }
}

@MainActor
final class GatewayDashboardStore: ObservableObject {
    @Published private(set) var snapshot = GatewayDashboardSnapshot.empty(range: .oneMinute)

    func reload(from logStore: PersistentLogStore, range: GatewayDashboardRange) {
        logStore.readTail(maxBytes: 5_000_000) { [weak self] tail in
            self?.snapshot = GatewayDashboardSnapshot.make(from: tail, range: range, now: Date())
        }
    }

    func clear(range: GatewayDashboardRange) {
        snapshot = .empty(range: range)
    }
}

struct GatewayDashboardSnapshot {
    var range: GatewayDashboardRange
    var generatedAt: Date
    var totalRequests: Int
    var previousTotalRequests: Int
    var inputTokens: Int
    var previousInputTokens: Int
    var outputTokens: Int
    var previousOutputTokens: Int
    var averageLatencyMs: Double?
    var previousAverageLatencyMs: Double?
    var errorRate: Double
    var previousErrorRate: Double
    var issueCount: Int
    var chartBuckets: [Int]
    var requestRows: [DashboardRequestRow]

    var recentRequests: [DashboardRequestRow] {
        Array(requestRows.prefix(8))
    }

    var issueRows: [DashboardRequestRow] {
        requestRows.filter(\.isIssue)
    }

    static func empty(range: GatewayDashboardRange) -> GatewayDashboardSnapshot {
        GatewayDashboardSnapshot(
            range: range,
            generatedAt: Date(),
            totalRequests: 0,
            previousTotalRequests: 0,
            inputTokens: 0,
            previousInputTokens: 0,
            outputTokens: 0,
            previousOutputTokens: 0,
            averageLatencyMs: nil,
            previousAverageLatencyMs: nil,
            errorRate: 0,
            previousErrorRate: 0,
            issueCount: 0,
            chartBuckets: Array(repeating: 0, count: 12),
            requestRows: []
        )
    }

    static func make(from logText: String, range: GatewayDashboardRange, now: Date) -> GatewayDashboardSnapshot {
        let records = GatewayMetricsParser.records(from: logText)
        let currentStart = now.addingTimeInterval(-range.duration)
        let previousStart = now.addingTimeInterval(-range.duration * 2)

        let current = records.filter { record in
            guard let date = record.sortDate else { return false }
            return date >= currentStart && date <= now
        }
        let previous = records.filter { record in
            guard let date = record.sortDate else { return false }
            return date >= previousStart && date < currentStart
        }

        let requestRows = records
            .sorted { lhs, rhs in
                (lhs.sortDate ?? .distantPast) > (rhs.sortDate ?? .distantPast)
            }
            .prefix(500)
            .map(DashboardRequestRow.init(record:))

        return GatewayDashboardSnapshot(
            range: range,
            generatedAt: now,
            totalRequests: current.count,
            previousTotalRequests: previous.count,
            inputTokens: current.reduce(0) { $0 + $1.inputTokens },
            previousInputTokens: previous.reduce(0) { $0 + $1.inputTokens },
            outputTokens: current.reduce(0) { $0 + $1.outputTokens },
            previousOutputTokens: previous.reduce(0) { $0 + $1.outputTokens },
            averageLatencyMs: averageLatency(current),
            previousAverageLatencyMs: averageLatency(previous),
            errorRate: errorRate(current),
            previousErrorRate: errorRate(previous),
            issueCount: current.filter(\.isIssue).count,
            chartBuckets: bucketCounts(records: current, start: currentStart, duration: range.duration),
            requestRows: Array(requestRows)
        )
    }

    var requestRate: Double {
        guard range.duration > 0 else { return 0 }
        return Double(totalRequests) / range.duration
    }

    var healthText: String {
        if totalRequests == 0 {
            return issueCount > 0 ? "Issues" : "--"
        }
        return issueCount == 0 ? "OK" : "\(issueCount)"
    }

    private static func averageLatency(_ records: [GatewayMetricRecord]) -> Double? {
        let values = records.compactMap(\.latencyMs)
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private static func errorRate(_ records: [GatewayMetricRecord]) -> Double {
        guard !records.isEmpty else { return 0 }
        return Double(records.filter(\.isIssue).count) / Double(records.count)
    }

    private static func bucketCounts(records: [GatewayMetricRecord], start: Date, duration: TimeInterval) -> [Int] {
        let bucketCount = 12
        let bucketDuration = duration / Double(bucketCount)
        guard bucketDuration > 0 else { return Array(repeating: 0, count: bucketCount) }

        var buckets = Array(repeating: 0, count: bucketCount)
        for record in records {
            guard let date = record.sortDate else { continue }
            let offset = date.timeIntervalSince(start)
            let index = min(max(Int(offset / bucketDuration), 0), bucketCount - 1)
            buckets[index] += 1
        }
        return buckets
    }
}

struct DashboardRequestRow: Identifiable {
    var id: String
    var time: String
    var method: String
    var model: String
    var route: String
    var status: String
    var isIssue: Bool
    var latency: String

    init(record: GatewayMetricRecord) {
        id = record.requestID
        time = record.sortDate.map(Self.timeFormatter.string(from:)) ?? "--:--:--"
        method = record.method.isEmpty ? "-" : record.method
        model = record.displayModel
        route = record.path.isEmpty ? "-" : record.path
        status = record.status.map(String.init) ?? (record.errorMessage == nil ? "..." : "ERR")
        isIssue = record.isIssue
        latency = record.latencyMs.map(Self.formatLatency) ?? "-"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static func formatLatency(_ milliseconds: Int) -> String {
        if milliseconds < 1_000 {
            return "\(milliseconds)ms"
        }
        let seconds = Double(milliseconds) / 1_000
        return String(format: "%.1fs", seconds)
    }
}

struct GatewayMetricRecord {
    var requestID: String
    var startedAt: Date?
    var responseAt: Date?
    var method: String = ""
    var path: String = ""
    var originalModel: String = ""
    var targetModel: String = ""
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var status: Int?
    var latencyMs: Int?
    var errorMessage: String?

    var sortDate: Date? {
        startedAt ?? responseAt
    }

    var isIssue: Bool {
        if errorMessage != nil { return true }
        guard let status else { return false }
        return !(200..<400).contains(status)
    }

    var displayModel: String {
        if !originalModel.isEmpty, !targetModel.isEmpty, originalModel != targetModel {
            return "\(originalModel) -> \(targetModel)"
        }
        if !originalModel.isEmpty { return originalModel }
        if !targetModel.isEmpty { return targetModel }
        return "-"
    }
}

private enum GatewayMetricsParser {
    private static let structuredPrefix = "CDSG_EVENT "
    private static let isoFormatter = ISO8601DateFormatter()

    static func records(from text: String) -> [GatewayMetricRecord] {
        var records: [String: GatewayMetricRecord] = [:]

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix(structuredPrefix) else { continue }
            let jsonText = String(line.dropFirst(structuredPrefix.count))
            guard let object = decodeObject(jsonText),
                let type = object["type"] as? String,
                let requestID = object["requestID"] as? String,
                !requestID.isEmpty
            else {
                continue
            }

            var record = records[requestID] ?? GatewayMetricRecord(requestID: requestID)
            let timestamp = dateValue(object["timestamp"] as? String)

            switch type {
            case "deepseek_request", "gateway_request":
                record.startedAt = record.startedAt ?? timestamp
                record.method = stringValue(object["method"]) ?? record.method
                record.path = stringValue(object["path"]) ?? record.path
                record.originalModel = stringValue(object["originalModel"]) ?? record.originalModel
                record.targetModel = stringValue(object["targetModel"]) ?? record.targetModel
                if type == "deepseek_request" {
                    record.inputTokens = intValue(object["inputTokens"])
                        ?? estimateTokens(fromBytes: intValue(object["bodyBytes"]))
                        ?? record.inputTokens
                }

            case "deepseek_response", "gateway_response":
                record.responseAt = timestamp ?? record.responseAt
                record.status = intValue(object["status"]) ?? record.status
                record.latencyMs = intValue(object["durationMs"]) ?? record.latencyMs
                if type == "deepseek_response" {
                    if let inputTokens = intValue(object["inputTokens"]) {
                        record.inputTokens = inputTokens
                    }
                    record.outputTokens = intValue(object["outputTokens"])
                        ?? intValue(object["outputTokensEstimate"])
                        ?? estimateTokens(fromBytes: intValue(object["responseBodyBytes"]))
                        ?? record.outputTokens
                }

            case "deepseek_error":
                record.responseAt = timestamp ?? record.responseAt
                record.latencyMs = intValue(object["durationMs"]) ?? record.latencyMs
                record.errorMessage = stringValue(object["message"]) ?? "Upstream error"

            default:
                continue
            }

            records[requestID] = record
        }

        return Array(records.values)
    }

    private static func decodeObject(_ jsonText: String) -> [String: Any]? {
        guard let data = jsonText.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    private static func dateValue(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return isoFormatter.date(from: value)
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.isEmpty ? nil : string
        case is NSNull, nil:
            return nil
        default:
            return value.map { String(describing: $0) }
        }
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

    private static func estimateTokens(fromBytes bytes: Int?) -> Int? {
        guard let bytes, bytes > 0 else { return nil }
        return max(1, Int(ceil(Double(bytes) / 3.0)))
    }
}
