import Foundation
import SwiftUI

struct LogTimelineView: View {
    @ObservedObject var runner: ProxyController
    @State private var events: [GatewayLogEvent] = []
    @State private var filteredEvents: [GatewayLogEvent] = []
    @State private var detailEvent: GatewayLogEvent?
    @State private var filter: LogEventFilter = .all
    @State private var searchText = ""
    @State private var autoRefresh = true
    @State private var tailSignature: PersistentLogTailSignature?
    @State private var reloadInFlight = false
    @State private var parseGeneration = 0
    private let refreshTimer = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Logs")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize()

                Spacer()

                Button {
                    autoRefresh.toggle()
                } label: {
                    Label(autoRefresh ? "Pause" : "Resume", systemImage: autoRefresh ? "pause.fill" : "play.fill")
                }
                .controlSize(.small)
                .help(autoRefresh ? "暂停自动刷新" : "继续自动刷新")

                Button {
                    clearLogs()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .controlSize(.small)
                .help("清空日志文件")

                Picker("Level", selection: $filter) {
                    ForEach(LogEventFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 88)

                Button {
                    reload()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .controlSize(.small)
                .help("重新读取日志文件")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if events.isEmpty {
                LogEmptyState(
                    symbol: "doc.text.magnifyingglass",
                    title: "暂无日志",
                    message: "启动 gateway 或从 Claude 发起请求后，这里会显示事件。"
                )
            } else if filteredEvents.isEmpty {
                LogEmptyState(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: "没有匹配事件",
                    message: "调整搜索关键字或日志级别过滤器。"
                )
            } else {
                VirtualLogTableView(events: filteredEvents) { event in
                    detailEvent = event
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search Logs")
        .sheet(item: $detailEvent) { event in
            LogDetailSheet(event: event)
        }
        .onAppear(perform: reload)
        .onReceive(refreshTimer) { _ in
            guard autoRefresh else { return }
            reload()
        }
        .onChange(of: filter) { _, _ in
            applyFilter()
        }
        .onChange(of: searchText) { _, _ in
            applyFilter()
        }
    }

    private func reload() {
        guard !reloadInFlight else { return }
        reloadInFlight = true
        runner.logStore.readTail(maxBytes: 5_000_000, ifChangedFrom: tailSignature) { read in
            guard let read else {
                reloadInFlight = false
                return
            }

            tailSignature = read.signature
            parseGeneration += 1
            let generation = parseGeneration
            Task.detached(priority: .userInitiated) {
                let parsed = GatewayLogParser.parse(read.text)
                await MainActor.run {
                    guard parseGeneration == generation else {
                        reloadInFlight = false
                        return
                    }
                    events = parsed
                    applyFilter()
                    reloadInFlight = false
                }
            }
        }
    }

    private func clearLogs() {
        runner.clearLog()
        tailSignature = nil
        parseGeneration += 1
        reloadInFlight = false
        events = []
        filteredEvents = []
    }

    private func applyFilter() {
        let query = GatewayLogEvent.normalizedSearchText(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
        filteredEvents = events.filter { event in
            filter.includes(event) && (query.isEmpty || event.matchesSearch(query))
        }
    }
}

private enum LogEventFilter: String, CaseIterable, Identifiable {
    case all
    case requests
    case issues
    case info

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .requests:
            return "HTTP"
        case .issues:
            return "Warn+"
        case .info:
            return "Info"
        }
    }

    func includes(_ event: GatewayLogEvent) -> Bool {
        switch self {
        case .all:
            return true
        case .requests:
            return event.tone == .request || event.tone == .response
        case .issues:
            return event.tone == .warning || event.tone == .error
        case .info:
            return event.tone == .info
        }
    }
}

private struct LogEmptyState: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: 420)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private extension GatewayLogEvent {
    func matchesSearch(_ query: String) -> Bool {
        searchIndex.contains(query)
    }
}
