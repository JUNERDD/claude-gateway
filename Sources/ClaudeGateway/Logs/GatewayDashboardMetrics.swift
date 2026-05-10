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

}

@MainActor
final class GatewayDashboardStore: ObservableObject {
    @Published private(set) var snapshot = GatewayDashboardSnapshot.empty(range: .oneMinute)
    private var tailSignature: PersistentLogTailSignature?
    private var cachedRecords: [GatewayMetricRecord] = []
    private var reloadInFlight = false
    private var reloadGeneration = 0
    private let nowProvider: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.nowProvider = now
    }

    func reload(from logStore: PersistentLogStore, range: GatewayDashboardRange) {
        guard !reloadInFlight else { return }
        reloadInFlight = true
        logStore.readTail(maxBytes: 5_000_000, ifChangedFrom: tailSignature) { [weak self] read in
            guard let self else { return }
            self.reloadGeneration += 1
            let generation = self.reloadGeneration
            let now = self.nowProvider()
            let cachedRecords = self.cachedRecords
            Task.detached(priority: .utility) {
                let records: [GatewayMetricRecord]
                if let read {
                    records = GatewayMetricsParser.records(from: read.text)
                } else {
                    records = cachedRecords
                }
                let snapshot = GatewayDashboardSnapshot.make(from: records, range: range, now: now)
                await MainActor.run {
                    guard self.reloadGeneration == generation else {
                        self.reloadInFlight = false
                        return
                    }
                    if let read {
                        self.tailSignature = read.signature
                        self.cachedRecords = records
                    }
                    self.snapshot = snapshot
                    self.reloadInFlight = false
                }
            }
        }
    }

    func clear(range: GatewayDashboardRange) {
        tailSignature = nil
        cachedRecords = []
        reloadGeneration += 1
        reloadInFlight = false
        snapshot = .empty(range: range)
    }
}

struct GatewayDashboardSnapshot {
    var range: GatewayDashboardRange
    var generatedAt: Date
    var totalRequests: Int
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationInputTokens: Int
    var cacheReadInputTokens: Int
    var cacheMissTokens: Int
    var averageLatencyMs: Double?
    var errorRate: Double
    var issueCount: Int
    var outputTokenBuckets: [Int]
    var cacheTokenBuckets: [Int]
    var requestRows: [DashboardRequestRow]

    var issueRows: [DashboardRequestRow] {
        requestRows.filter(\.isIssue)
    }

    static func empty(range: GatewayDashboardRange) -> GatewayDashboardSnapshot {
        GatewayDashboardSnapshot(
            range: range,
            generatedAt: Date(),
            totalRequests: 0,
            inputTokens: 0,
            outputTokens: 0,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            cacheMissTokens: 0,
            averageLatencyMs: nil,
            errorRate: 0,
            issueCount: 0,
            outputTokenBuckets: Array(repeating: 0, count: 12),
            cacheTokenBuckets: Array(repeating: 0, count: 12),
            requestRows: []
        )
    }

    static func make(from logText: String, range: GatewayDashboardRange, now: Date) -> GatewayDashboardSnapshot {
        make(from: GatewayMetricsParser.records(from: logText), range: range, now: now)
    }

    static func make(from records: [GatewayMetricRecord], range: GatewayDashboardRange, now: Date) -> GatewayDashboardSnapshot {
        let windowStart = now.addingTimeInterval(-range.duration)

        let inWindow = records.filter { record in
            guard let date = record.sortDate else { return false }
            return date >= windowStart && date <= now
        }

        let requestRows = inWindow
            .sorted { lhs, rhs in
                (lhs.sortDate ?? .distantPast) > (rhs.sortDate ?? .distantPast)
            }
            .prefix(500)
            .map(DashboardRequestRow.init(record:))

        let (output, cache) = tokenBuckets(records: inWindow, start: windowStart, duration: range.duration)
        return GatewayDashboardSnapshot(
            range: range,
            generatedAt: now,
            totalRequests: inWindow.count,
            inputTokens: inWindow.reduce(0) { $0 + $1.inputTokens },
            outputTokens: inWindow.reduce(0) { $0 + $1.outputTokens },
            cacheCreationInputTokens: inWindow.reduce(0) { $0 + $1.cacheCreationInputTokens },
            cacheReadInputTokens: inWindow.reduce(0) { $0 + $1.cacheReadInputTokens },
            cacheMissTokens: inWindow.reduce(0) { $0 + $1.cacheMissTokens },
            averageLatencyMs: averageLatency(inWindow),
            errorRate: errorRate(inWindow),
            issueCount: inWindow.filter(\.isIssue).count,
            outputTokenBuckets: output,
            cacheTokenBuckets: cache,
            requestRows: Array(requestRows)
        )
    }

    var cacheHitRate: Double? {
        if cacheMissTokens > 0 {
            // DeepSeek path: hits / (hits + misses)
            let denominator = cacheReadInputTokens + cacheMissTokens
            guard denominator > 0 else { return nil }
            return Double(cacheReadInputTokens) / Double(denominator)
        }
        // Anthropic path: reads / (input + writes + reads)
        let denominator = inputTokens + cacheCreationInputTokens + cacheReadInputTokens
        guard denominator > 0 else { return nil }
        return Double(cacheReadInputTokens) / Double(denominator)
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

    private static func tokenBuckets(records: [GatewayMetricRecord], start: Date, duration: TimeInterval) -> (output: [Int], cache: [Int]) {
        let bucketCount = 12
        let bucketDuration = duration / Double(bucketCount)
        guard bucketDuration > 0 else {
            return (Array(repeating: 0, count: bucketCount), Array(repeating: 0, count: bucketCount))
        }

        var outputBuckets = Array(repeating: 0, count: bucketCount)
        var cacheBuckets = Array(repeating: 0, count: bucketCount)
        for record in records {
            guard let date = record.sortDate else { continue }
            let offset = date.timeIntervalSince(start)
            let index = min(max(Int(offset / bucketDuration), 0), bucketCount - 1)
            outputBuckets[index] += record.outputTokens
            cacheBuckets[index] += record.cacheReadInputTokens
        }
        return (outputBuckets, cacheBuckets)
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
    var cacheCreationInputTokens: Int = 0
    var cacheReadInputTokens: Int = 0
    var cacheMissTokens: Int = 0
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
    private static let structuredPrefix = "CG_EVENT "
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
            case "gateway_request":
                record.startedAt = record.startedAt ?? timestamp
                record.method = stringValue(object["method"]) ?? record.method
                record.path = stringValue(object["path"]) ?? record.path
                record.originalModel = stringValue(object["originalModel"]) ?? record.originalModel
                record.targetModel = stringValue(object["targetModel"]) ?? record.targetModel
                record.inputTokens = intValue(object["inputTokens"])
                    ?? estimateTokens(fromBytes: intValue(object["bodyBytes"]))
                    ?? record.inputTokens

            case "gateway_response":
                record.responseAt = timestamp ?? record.responseAt
                record.status = intValue(object["status"]) ?? record.status
                record.latencyMs = intValue(object["durationMs"]) ?? record.latencyMs
                if let inputTokens = intValue(object["inputTokens"]) {
                    record.inputTokens = inputTokens
                }
                record.outputTokens = intValue(object["outputTokens"])
                    ?? intValue(object["outputTokensEstimate"])
                    ?? estimateTokens(fromBytes: intValue(object["responseBodyBytes"]))
                    ?? record.outputTokens
                record.cacheCreationInputTokens = intValue(object["cacheCreationInputTokens"]) ?? record.cacheCreationInputTokens
                record.cacheReadInputTokens = intValue(object["cacheReadInputTokens"]) ?? record.cacheReadInputTokens
                record.cacheMissTokens = intValue(object["cacheMissTokens"]) ?? record.cacheMissTokens

            case "gateway_error":
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
