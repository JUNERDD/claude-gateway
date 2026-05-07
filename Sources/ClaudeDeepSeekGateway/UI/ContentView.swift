import AppKit
import Charts
import SwiftUI

struct ContentView: View {
    @ObservedObject var settings: ProxySettingsStore
    @StateObject private var runner = ProxyController()
    @StateObject private var dashboard = GatewayDashboardStore()
    @Environment(\.openSettings) private var openSettings

    @State private var didAutoStart = false
    @State private var selectedSection: GatewaySection = .overview
    @State private var selectedRange: GatewayDashboardRange = .oneMinute

    private let refreshTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedSection: $selectedSection,
                settings: settings,
                runner: runner,
                snapshot: dashboard.snapshot
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            detailView
                .navigationTitle(selectedSection.title)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            reloadFromDisk()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .help("Reload settings, service status, and recent gateway metrics")

                        Button {
                            syncClaude()
                        } label: {
                            Label("Save and Sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .help("Save current settings, sync Claude configuration, and refresh the LaunchAgent")

                        ControlGroup {
                            Button {
                                startGateway()
                            } label: {
                                Label("Start Gateway", systemImage: "play.fill")
                            }
                            .disabled(runner.isRunning)
                            .keyboardShortcut("r", modifiers: .command)
                            .help("Save current settings and start the local gateway")

                            Button {
                                stopGateway()
                            } label: {
                                Label("Stop Gateway", systemImage: "stop.fill")
                            }
                            .disabled(!runner.isRunning)
                            .help("Stop the local gateway LaunchAgent")
                        }

                        Menu {
                            Button {
                                clearLogs()
                            } label: {
                                Label("Clear Logs", systemImage: "trash")
                            }

                            Divider()

                            Button {
                                openSettings()
                            } label: {
                                Label("Open Settings", systemImage: "gearshape")
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                    }
                }
        }
        .frame(minWidth: 1120, minHeight: 760)
        .onAppear {
            guard !didAutoStart else { return }
            didAutoStart = true
            settings.load()
            runner.refreshStatus()
            dashboard.reload(from: runner.logStore, range: selectedRange)
            if BundledRuntimeInstaller.hasUsableDeepSeekAPIKey() {
                runner.start()
                runner.refreshStatus()
            }
        }
        .onReceive(refreshTimer) { _ in
            runner.refreshStatus()
            dashboard.reload(from: runner.logStore, range: selectedRange)
        }
        .onChange(of: selectedRange) { _, range in
            dashboard.reload(from: runner.logStore, range: range)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .overview:
            OverviewPage(
                settings: settings,
                runner: runner,
                snapshot: dashboard.snapshot,
                selectedRange: $selectedRange,
                start: startGateway,
                stop: stopGateway,
                sync: syncClaude
            )
        case .requests:
            RequestsPage(snapshot: dashboard.snapshot, selectedRange: $selectedRange)
        case .issues:
            IssuesPage(snapshot: dashboard.snapshot)
        case .logs:
            LogsPage(runner: runner, clearLogs: clearLogs)
        case .endpoint:
            EndpointPage(settings: settings, save: syncClaude, reload: reloadFromDisk)
        case .models:
            ModelsPage(settings: settings, save: syncClaude)
        case .credentials:
            CredentialsPage(settings: settings, save: syncClaude)
        case .claude:
            ClaudePage(settings: settings, sync: syncClaude)
        case .runtime:
            RuntimePage(settings: settings)
        }
    }

    private func startGateway() {
        settings.save()
        runner.refreshStatus()
        dashboard.reload(from: runner.logStore, range: selectedRange)
    }

    private func stopGateway() {
        runner.stop()
        runner.refreshStatus()
        dashboard.reload(from: runner.logStore, range: selectedRange)
    }

    private func syncClaude() {
        settings.syncClaudeDesktopConfig()
        runner.refreshStatus()
        dashboard.reload(from: runner.logStore, range: selectedRange)
    }

    private func reloadFromDisk() {
        settings.load()
        runner.refreshStatus()
        dashboard.reload(from: runner.logStore, range: selectedRange)
    }

    private func clearLogs() {
        runner.clearLog()
        dashboard.clear(range: selectedRange)
    }
}

private enum GatewaySection: String, CaseIterable, Identifiable {
    case overview
    case requests
    case issues
    case logs
    case endpoint
    case models
    case credentials
    case claude
    case runtime

    var id: String { rawValue }

    static let monitor: [GatewaySection] = [.overview, .requests, .issues, .logs]
    static let configuration: [GatewaySection] = [.endpoint, .models, .credentials, .claude, .runtime]

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .requests:
            return "Requests"
        case .issues:
            return "Issues"
        case .logs:
            return "Logs"
        case .endpoint:
            return "Endpoint"
        case .models:
            return "Model Mapping"
        case .credentials:
            return "Credentials"
        case .claude:
            return "Claude Integration"
        case .runtime:
            return "Runtime"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "gauge.with.dots.needle.67percent"
        case .requests:
            return "arrow.left.arrow.right"
        case .issues:
            return "exclamationmark.triangle"
        case .logs:
            return "doc.text.magnifyingglass"
        case .endpoint:
            return "network"
        case .models:
            return "rectangle.stack"
        case .credentials:
            return "key"
        case .claude:
            return "arrow.triangle.2.circlepath"
        case .runtime:
            return "wrench.and.screwdriver"
        }
    }
}

private struct SidebarView: View {
    @Binding var selectedSection: GatewaySection
    @ObservedObject var settings: ProxySettingsStore
    @ObservedObject var runner: ProxyController
    var snapshot: GatewayDashboardSnapshot

    var body: some View {
        List(selection: $selectedSection) {
            Section("Monitor") {
                ForEach(GatewaySection.monitor) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }

            Section("Configuration") {
                ForEach(GatewaySection.configuration) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter(settings: settings, runner: runner, snapshot: snapshot)
        }
    }
}

private struct SidebarFooter: View {
    @ObservedObject var settings: ProxySettingsStore
    @ObservedObject var runner: ProxyController
    var snapshot: GatewayDashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            HStack(spacing: 8) {
                StatusDot(isRunning: runner.isRunning)
                VStack(alignment: .leading, spacing: 1) {
                    Text(runner.isRunning ? "Gateway Running" : "Gateway Stopped")
                        .font(.caption.weight(.semibold))
                    Text("\(settings.host):\(settings.portText)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            HStack {
                SidebarFooterMetric(label: "Requests", value: AppFormat.compact(snapshot.totalRequests))
                SidebarFooterMetric(label: "Issues", value: "\(snapshot.issueCount)")
                SidebarFooterMetric(label: "Models", value: "\(settings.advertisedModels.count)")
            }

            Text(appVersionText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (version?, build?):
            return "v\(version) (\(build))"
        case let (version?, nil):
            return "v\(version)"
        default:
            return "Version unavailable"
        }
    }
}

private struct SidebarFooterMetric: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.caption.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OverviewPage: View {
    @ObservedObject var settings: ProxySettingsStore
    @ObservedObject var runner: ProxyController
    var snapshot: GatewayDashboardSnapshot
    @Binding var selectedRange: GatewayDashboardRange
    var start: () -> Void
    var stop: () -> Void
    var sync: () -> Void

    var body: some View {
        NativePage {
            PageHeader(
                title: "Gateway Overview",
                subtitle: "Monitor local traffic and keep Claude configured for the DeepSeek alias proxy."
            ) {
                RangePicker(selection: $selectedRange)
            }

            StatusSummaryGroup(
                settings: settings,
                runner: runner,
                snapshot: snapshot,
                start: start,
                stop: stop,
                sync: sync
            )

            MetricsGrid(snapshot: snapshot)

            CardSection(title: "Request Rate", systemImage: "chart.xyaxis.line") {
                RequestRateChart(snapshot: snapshot)
                    .frame(height: 210)
            }

            CardSection(title: "Recent Requests", systemImage: "clock") {
                RequestTable(rows: snapshot.recentRequests, compact: true)
                    .frame(minHeight: 230)
            }

            SettingsStatusBanner(settings: settings)
        }
    }
}

private struct StatusSummaryGroup: View {
    @ObservedObject var settings: ProxySettingsStore
    @ObservedObject var runner: ProxyController
    var snapshot: GatewayDashboardSnapshot
    var start: () -> Void
    var stop: () -> Void
    var sync: () -> Void

    var body: some View {
        CardSurface {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow {
                    SummaryCell(
                        title: "Status",
                        value: runner.isRunning ? "Running" : "Stopped",
                        detail: runner.isRunning ? "LaunchAgent is active" : "LaunchAgent is not running",
                        systemImage: runner.isRunning ? "checkmark.circle.fill" : "pause.circle",
                        tint: runner.isRunning ? .green : .secondary
                    )

                    SummaryCell(
                        title: "Uptime",
                        value: runner.isRunning ? "Running" : "00:00:00",
                        detail: runner.isRunning ? "Updated from launchd process time" : "Start the gateway to begin serving",
                        systemImage: "timer",
                        tint: .blue,
                        runningSince: runner.runningSince,
                        isRunning: runner.isRunning
                    )

                    SummaryCell(
                        title: "Endpoint",
                        value: "\(settings.host):\(settings.portText)",
                        detail: settings.anthropicBaseURL,
                        systemImage: "network",
                        tint: .blue
                    )
                }

                GridRow {
                    SummaryCell(
                        title: "Models",
                        value: "\(settings.advertisedModels.count) advertised",
                        detail: "Haiku and default mappings are editable in Model Mapping",
                        systemImage: "rectangle.stack",
                        tint: .purple
                    )

                    SummaryCell(
                        title: "Health",
                        value: snapshot.issueCount == 0 ? "No issues" : "\(snapshot.issueCount) issues",
                        detail: snapshot.totalRequests == 0 ? "No traffic in selected range" : "\(AppFormat.percent(snapshot.errorRate)) error rate",
                        systemImage: snapshot.issueCount == 0 ? "heart.text.square" : "exclamationmark.triangle.fill",
                        tint: snapshot.issueCount == 0 ? .green : .orange
                    )

                    HStack(spacing: 8) {
                        Button {
                            start()
                        } label: {
                            Label("Start", systemImage: "play.fill")
                        }
                        .disabled(runner.isRunning)

                        Button {
                            stop()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .disabled(!runner.isRunning)

                        Button {
                            sync()
                        } label: {
                            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .controlSize(.regular)
                }
            }
        }
    }
}

private struct SummaryCell: View {
    var title: String
    var value: String
    var detail: String
    var systemImage: String
    var tint: Color
    var runningSince: Date?
    var isRunning = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if runningSince != nil || isRunning {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text(uptimeText(now: timeline.date))
                            .font(.body.weight(.semibold).monospacedDigit())
                    }
                } else {
                    Text(value)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(minWidth: 190, maxWidth: .infinity, alignment: .leading)
    }

    private func uptimeText(now: Date) -> String {
        guard isRunning, let runningSince else { return "00:00:00" }
        return AppFormat.duration(now.timeIntervalSince(runningSince))
    }
}

private struct MetricsGrid: View {
    var snapshot: GatewayDashboardSnapshot

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 12)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            MetricTile(
                title: "Requests",
                value: AppFormat.integer(snapshot.totalRequests),
                detail: trendText(current: Double(snapshot.totalRequests), previous: Double(snapshot.previousTotalRequests)),
                isGood: trendIsGood(current: Double(snapshot.totalRequests), previous: Double(snapshot.previousTotalRequests))
            )
            MetricTile(
                title: "Input Tokens",
                value: AppFormat.compact(snapshot.inputTokens),
                detail: trendText(current: Double(snapshot.inputTokens), previous: Double(snapshot.previousInputTokens)),
                isGood: trendIsGood(current: Double(snapshot.inputTokens), previous: Double(snapshot.previousInputTokens))
            )
            MetricTile(
                title: "Output Tokens",
                value: AppFormat.compact(snapshot.outputTokens),
                detail: trendText(current: Double(snapshot.outputTokens), previous: Double(snapshot.previousOutputTokens)),
                isGood: trendIsGood(current: Double(snapshot.outputTokens), previous: Double(snapshot.previousOutputTokens))
            )
            MetricTile(
                title: "Average Latency",
                value: AppFormat.latency(snapshot.averageLatencyMs),
                detail: trendText(current: snapshot.averageLatencyMs, previous: snapshot.previousAverageLatencyMs),
                isGood: trendIsGood(current: snapshot.averageLatencyMs, previous: snapshot.previousAverageLatencyMs, lowerIsBetter: true)
            )
            MetricTile(
                title: "Error Rate",
                value: AppFormat.percent(snapshot.errorRate),
                detail: trendText(current: snapshot.errorRate, previous: snapshot.previousErrorRate),
                isGood: trendIsGood(current: snapshot.errorRate, previous: snapshot.previousErrorRate, lowerIsBetter: true)
            )
        }
    }

    private func trendText(current: Double?, previous: Double?) -> String {
        guard let current, let previous else { return "No comparison" }
        guard previous > 0 else { return current > 0 ? "New in this range" : "No change" }
        let delta = (current - previous) / previous
        guard abs(delta) >= 0.005 else { return "No change" }
        let arrow = delta > 0 ? "Up" : "Down"
        return "\(arrow) \(AppFormat.percent(abs(delta)))"
    }

    private func trendIsGood(current: Double?, previous: Double?, lowerIsBetter: Bool = false) -> Bool? {
        guard let current, let previous, previous > 0 else { return nil }
        guard abs(current - previous) >= 0.000_001 else { return nil }
        return lowerIsBetter ? current < previous : current > previous
    }
}

private struct MetricTile: View {
    var title: String
    var value: String
    var detail: String
    var isGood: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack(spacing: 5) {
                if let isGood {
                    Image(systemName: isGood ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2.weight(.semibold))
                }
                Text(detail)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(trendColor)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var trendColor: Color {
        guard let isGood else { return .secondary }
        return isGood ? .green : .orange
    }
}

private struct RequestsPage: View {
    var snapshot: GatewayDashboardSnapshot
    @Binding var selectedRange: GatewayDashboardRange

    var body: some View {
        NativePage {
            PageHeader(
                title: "Requests",
                subtitle: "All structured gateway traffic parsed from the local persistent log."
            ) {
                RangePicker(selection: $selectedRange)
            }

            CardSection(title: "Request History", systemImage: "list.bullet.rectangle") {
                RequestTable(rows: snapshot.requestRows, compact: false)
                    .frame(minHeight: 520)
            }
        }
    }
}

private struct IssuesPage: View {
    var snapshot: GatewayDashboardSnapshot

    var body: some View {
        NativePage {
            PageHeader(
                title: "Issues",
                subtitle: "Non-2xx responses and transport errors from the gateway log."
            )

            CardSection(title: "Failures", systemImage: "exclamationmark.triangle") {
                RequestTable(rows: snapshot.issueRows, compact: false, emptyTitle: "No Issues", emptyDescription: "No failed requests were found in the loaded log tail.")
                    .frame(minHeight: 520)
            }
        }
    }
}

private struct LogsPage: View {
    @ObservedObject var runner: ProxyController
    var clearLogs: () -> Void

    var body: some View {
        NativePage {
            PageHeader(
                title: "Logs",
                subtitle: "Structured and plain proxy events from the persistent log file."
            ) {
                Button {
                    clearLogs()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            }

            LogTimelineView(runner: runner)
                .frame(minHeight: 560)
        }
    }
}

private struct EndpointPage: View {
    @ObservedObject var settings: ProxySettingsStore
    var save: () -> Void
    var reload: () -> Void

    var body: some View {
        NativePage {
            PageHeader(
                title: "Endpoint",
                subtitle: "Configure the local listener and the upstream Anthropic-compatible DeepSeek endpoint."
            )

            SettingsStack {
                SettingsSectionCard(title: "Local Gateway") {
                    SettingsRow("Host") {
                        TextField("127.0.0.1", text: $settings.host)
                            .textFieldStyle(.roundedBorder)
                    }
                    SettingsDivider()
                    SettingsRow("Port") {
                        TextField("4000", text: $settings.portText)
                            .textFieldStyle(.roundedBorder)
                    }
                    SettingsDivider()
                    SettingsRow("Config File") {
                        SelectablePath(settings.configPathForDisplay)
                    }
                }

                SettingsSectionCard(title: "Upstream") {
                    SettingsRow("Anthropic Base URL") {
                        TextField("https://api.deepseek.com/anthropic", text: $settings.anthropicBaseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                SettingsActionBar {
                    Button {
                        reload()
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }

                    Spacer()

                    Button {
                        save()
                    } label: {
                        Label("Save and Sync", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }

            SettingsStatusBanner(settings: settings)
        }
    }
}

private struct ModelsPage: View {
    @ObservedObject var settings: ProxySettingsStore
    var save: () -> Void

    var body: some View {
        NativePage {
            PageHeader(
                title: "Model Mapping",
                subtitle: "Advertise Claude model names locally and map them to DeepSeek targets."
            ) {
                Button {
                    settings.resetModelDefaults()
                } label: {
                    Label("Defaults", systemImage: "arrow.counterclockwise")
                }
            }

            SettingsStack {
                SettingsSectionCard(title: "Target Models") {
                    SettingsRow("Haiku Target") {
                        TextField("deepseek-v4-flash", text: $settings.haikuTargetModel)
                            .textFieldStyle(.roundedBorder)
                    }
                    SettingsDivider()
                    SettingsRow("Default Target") {
                        TextField("deepseek-v4-pro[1m]", text: $settings.nonHaikuTargetModel)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                SettingsSectionCard(title: "Advertised Models") {
                    TextEditor(text: $settings.advertisedModelsText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 180)
                        .frame(maxWidth: .infinity)
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                    SettingsDivider()
                    SettingsRow("Count") {
                        Text("\(settings.advertisedModels.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                SettingsSectionCard(title: "Preview") {
                    ForEach(Array(settings.advertisedModels.enumerated()), id: \.element) { index, model in
                        if index > 0 {
                            SettingsDivider()
                        }
                        SettingsRow(model) {
                            Text(mappedTarget(for: model))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }

                SettingsActionBar {
                    Spacer()
                    Button {
                        save()
                    } label: {
                        Label("Save and Sync", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }

            SettingsStatusBanner(settings: settings)
        }
    }

    private func mappedTarget(for model: String) -> String {
        model.localizedCaseInsensitiveContains("haiku") ? settings.haikuTargetModel : settings.nonHaikuTargetModel
    }
}

private struct CredentialsPage: View {
    @ObservedObject var settings: ProxySettingsStore
    var save: () -> Void

    var body: some View {
        NativePage {
            PageHeader(
                title: "Credentials",
                subtitle: "Keep the upstream DeepSeek key separate from the local gateway bearer key."
            )

            SettingsStack {
                SettingsSectionCard(title: "Secrets") {
                    SettingsRow("DeepSeek API Key") {
                        SecureField("sk-...", text: $settings.deepSeekAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    SettingsDivider()
                    SettingsRow("Local Gateway Key") {
                        HStack(spacing: 10) {
                            SecureField("Claude uses this bearer key", text: $settings.localGatewayKey)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                settings.generateLocalGatewayKey()
                            } label: {
                                Label("Generate", systemImage: "key.fill")
                            }
                        }
                    }
                    SettingsDivider()
                    SettingsRow("Secrets File") {
                        SelectablePath(settings.secretsPathForDisplay)
                    }
                }

                SettingsSectionCard(title: "Status") {
                    SettingsRow("DeepSeek API Key") {
                        Text(settings.deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not configured" : "Configured")
                            .foregroundStyle(settings.deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .orange : .secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    SettingsDivider()
                    SettingsRow("Local Gateway Key") {
                        Text(settings.localGatewayKey.isEmpty ? "Not generated" : "Generated")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                SettingsActionBar {
                    Spacer()
                    Button {
                        save()
                    } label: {
                        Label("Save and Sync", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }

            SettingsStatusBanner(settings: settings)
        }
    }
}

private struct ClaudePage: View {
    @ObservedObject var settings: ProxySettingsStore
    var sync: () -> Void

    var body: some View {
        NativePage {
            PageHeader(
                title: "Claude Integration",
                subtitle: "Write the gateway configuration to Claude Desktop and Claude Code."
            )

            CardSection(title: "Configuration Snippet", systemImage: "curlybraces") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(settings.claudeConfigSnippet)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

                    HStack {
                        Button {
                            sync()
                        } label: {
                            Label("Save, Sync, and Start", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .keyboardShortcut(.defaultAction)

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(settings.claudeConfigSnippet, forType: .string)
                        } label: {
                            Label("Copy Snippet", systemImage: "doc.on.doc")
                        }
                    }
                }
            }

            if !settings.claudeSyncStatusMessage.isEmpty {
                InlineStatus(message: settings.claudeSyncStatusMessage, isError: settings.claudeSyncStatusIsError, monospaced: true)
            }
        }
    }
}

private struct RuntimePage: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        NativePage {
            PageHeader(
                title: "Runtime",
                subtitle: "Install or repair the bundled proxy binary, scripts, and LaunchAgent support files."
            )

            CardSection(title: "Runtime Status", systemImage: "shippingbox") {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: settings.runtimeStatusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(settings.runtimeStatusIsError ? .orange : .green)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(settings.runtimeStatusIsError ? "Needs Attention" : "Runtime Ready")
                            .font(.headline)
                        Text(settings.runtimeStatusMessage.isEmpty ? "Runtime status is unknown." : settings.runtimeStatusMessage)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    Button {
                        settings.installBundledRuntime()
                        settings.load()
                    } label: {
                        Label("Install or Repair", systemImage: "wrench.and.screwdriver")
                    }
                }
            }

            CardSection(title: "Files", systemImage: "folder") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Config") {
                        SelectablePath(settings.configPathForDisplay)
                    }
                    LabeledContent("Secrets") {
                        SelectablePath(settings.secretsPathForDisplay)
                    }
                }
            }
        }
    }
}

private struct RequestRateChart: View {
    var snapshot: GatewayDashboardSnapshot

    private var buckets: [ChartBucket] {
        snapshot.chartBuckets.enumerated().map { ChartBucket(index: $0.offset + 1, count: $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(AppFormat.rate(snapshot.requestRate)) req/s")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text("average")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(snapshot.range.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if snapshot.chartBuckets.contains(where: { $0 > 0 }) {
                Chart(buckets) { bucket in
                    LineMark(
                        x: .value("Bucket", bucket.index),
                        y: .value("Requests", bucket.count)
                    )
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Bucket", bucket.index),
                        y: .value("Requests", bucket.count)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue.opacity(0.12))
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
            } else {
                ContentUnavailableView(
                    "No Requests",
                    systemImage: "chart.xyaxis.line",
                    description: Text("No traffic was recorded in the selected range.")
                )
            }
        }
    }
}

private struct ChartBucket: Identifiable {
    let index: Int
    let count: Int
    var id: Int { index }
}

private struct RequestTable: View {
    var rows: [DashboardRequestRow]
    var compact = false
    var emptyTitle = "No Requests"
    var emptyDescription = "Requests will appear here after Claude sends traffic through the gateway."
    @State private var selectedIDs = Set<DashboardRequestRow.ID>()

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                emptyTitle,
                systemImage: "tray",
                description: Text(emptyDescription)
            )
        } else {
            Table(rows, selection: $selectedIDs) {
                commonColumns
                if !compact {
                    TableColumn("Model", value: \.model)
                        .width(min: 180, ideal: 260, max: 520)
                }
            }
            .inspector(isPresented: inspectorBinding) {
                if let selectedRow {
                    RequestInspector(row: selectedRow)
                } else {
                    ContentUnavailableView("No Request Selected", systemImage: "sidebar.trailing")
                }
            }
        }
    }

    private var selectedRow: DashboardRequestRow? {
        guard let id = selectedIDs.first else { return nil }
        return rows.first { $0.id == id }
    }

    private var inspectorBinding: Binding<Bool> {
        Binding {
            !compact && selectedRow != nil
        } set: { isPresented in
            if !isPresented {
                selectedIDs.removeAll()
            }
        }
    }

    @TableColumnBuilder<DashboardRequestRow, Never>
    private var commonColumns: some TableColumnContent<DashboardRequestRow, Never> {
        TableColumn("Time", value: \.time)
            .width(min: 72, ideal: 82, max: 96)
        TableColumn("Method", value: \.method)
            .width(min: 62, ideal: 74, max: 90)
        TableColumn("Route", value: \.route)
            .width(min: 120, ideal: 160, max: 260)
        TableColumn("Status") { row in
            Text(row.status)
                .font(.body.monospacedDigit())
                .foregroundStyle(row.isIssue ? .red : .green)
        }
        .width(min: 64, ideal: 76, max: 92)
        TableColumn("Latency", value: \.latency)
            .width(min: 72, ideal: 82, max: 100)
    }
}

private struct RequestInspector: View {
    var row: DashboardRequestRow

    var body: some View {
        Form {
            Section("Request") {
                LabeledContent("Time", value: row.time)
                LabeledContent("Method", value: row.method)
                LabeledContent("Route", value: row.route)
                LabeledContent("Status") {
                    Text(row.status)
                        .foregroundStyle(row.isIssue ? .red : .green)
                        .monospacedDigit()
                }
                LabeledContent("Latency", value: row.latency)
            }

            Section("Model") {
                Text(row.model)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .inspectorColumnWidth(min: 260, ideal: 300, max: 360)
    }
}

private struct SettingsStack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct CardSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .padding(.horizontal, 2)

            CardSurface {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CardSurface<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SettingsSectionCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsRow<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(title)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 220, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 18)
    }
}

private struct SettingsActionBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ModelMappingPreviewRow: View {
    var model: String
    var target: String

    var body: some View {
        LabeledContent {
            Text(target)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        } label: {
            Text(model)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct PageHeader<Accessory: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var accessory: Accessory

    init(title: String, subtitle: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            accessory
        }
    }
}

private struct NativePage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct RangePicker: View {
    @Binding var selection: GatewayDashboardRange

    var body: some View {
        Picker("Range", selection: $selection) {
            ForEach(GatewayDashboardRange.allCases) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
        .labelsHidden()
    }
}

private struct SettingsStatusBanner: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        if !settings.statusMessage.isEmpty {
            InlineStatus(message: settings.statusMessage, isError: settings.statusIsError)
        }
    }
}

private struct InlineStatus: View {
    var message: String
    var isError: Bool
    var monospaced = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .orange : .green)
            Text(message)
                .font(monospaced ? .system(.caption, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SelectablePath: View {
    var path: String

    init(_ path: String) {
        self.path = path
    }

    var body: some View {
        Text(path)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }
}

private struct StatusDot: View {
    var isRunning: Bool

    var body: some View {
        Circle()
            .fill(isRunning ? Color.green : Color.secondary.opacity(0.55))
            .frame(width: 9, height: 9)
            .accessibilityLabel(isRunning ? "Running" : "Stopped")
    }
}

private extension View {
    func fullWidthControl() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum AppFormat {
    static func integer(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    static func compact(_ value: Int) -> String {
        let absolute = abs(value)
        if absolute < 1_000 {
            return "\(value)"
        }
        if absolute < 1_000_000 {
            return "\(trimmed(Double(value) / 1_000))k"
        }
        return "\(trimmed(Double(value) / 1_000_000))m"
    }

    static func percent(_ value: Double) -> String {
        "\(trimmed(value * 100))%"
    }

    static func latency(_ milliseconds: Double?) -> String {
        guard let milliseconds else { return "-" }
        if milliseconds < 1_000 {
            return "\(Int(milliseconds.rounded())) ms"
        }
        return "\(trimmed(milliseconds / 1_000)) s"
    }

    static func rate(_ value: Double) -> String {
        if value < 1 {
            return String(format: "%.2f", value)
        }
        if value < 10 {
            return trimmed(value)
        }
        return String(format: "%.0f", value)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let elapsed = max(0, Int(interval))
        let hours = elapsed / 3_600
        let minutes = (elapsed % 3_600) / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private static func trimmed(_ value: Double) -> String {
        let formatted = String(format: "%.1f", value)
        return formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
    }
}
