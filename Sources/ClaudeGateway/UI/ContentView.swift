import AppKit
import Charts
import SwiftUI

private enum MainWindowLayout {
    static var toolbarOverlayCompensation: CGFloat {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 32 : 0
    }
}

struct ContentView: View {
    @ObservedObject var settings: ProxySettingsStore
    @ObservedObject var onboarding: OnboardingCoordinator
    @ObservedObject var runner: ProxyController
    @ObservedObject var navigation: GatewayNavigationStore
    @StateObject private var dashboard = GatewayDashboardStore()
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    @State private var didAutoStart = false
    @State private var selectedRange: GatewayDashboardRange = .oneMinute

    private let refreshTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        mainContent
        .frame(minWidth: 1120, minHeight: 760)
        .background(MainWindowBehavior())
        .onAppear {
            guard !didAutoStart else { return }
            didAutoStart = true
            settings.load()
            runner.refreshStatus()
            dashboard.reload(from: runner.logStore, range: selectedRange)
            if BundledRuntimeInstaller.hasUsableLocalGatewayKey() {
                runner.start()
                runner.refreshStatus()
            }
            onboarding.presentIfNeeded(requiresSetup: !settings.setupIsComplete)
            wireStatusBarManager()
        }
        .onReceive(refreshTimer) { _ in
            if onboarding.isPresented {
                return
            }
            runner.refreshStatus()
            dashboard.reload(from: runner.logStore, range: selectedRange)
            StatusBarManager.shared.updateStatus(running: runner.isRunning)
        }
        .onChange(of: selectedRange) { _, range in
            dashboard.reload(from: runner.logStore, range: range)
        }
        .sheet(isPresented: onboardingSheetBinding) {
            OnboardingView(settings: settings, coordinator: onboarding) {
                refreshGatewayState()
            }
        }
    }

    private var onboardingSheetBinding: Binding<Bool> {
        Binding {
            onboarding.isPresented
        } set: { isPresented in
            guard !isPresented else { return }
            onboarding.dismissPresented()
        }
    }

    private var mainContent: some View {
        NavigationSplitView {
            SidebarView(
                selectedSection: $navigation.selectedSection,
                settings: settings,
                runner: runner,
                snapshot: dashboard.snapshot
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            detailContent
                .navigationTitle(navigation.selectedSection.title)
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: MainWindowLayout.toolbarOverlayCompensation)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        ToolbarIconButton(
                            title: "Refresh",
                            detail: "Reload settings, service status, and recent gateway metrics.",
                            systemImage: "arrow.clockwise"
                        ) {
                            reloadFromDisk()
                        }

                        ToolbarIconButton(
                            title: "Save, Sync, and Start",
                            detail: "Save current settings, sync Claude configuration, and start or refresh the LaunchAgent.",
                            systemImage: "arrow.triangle.2.circlepath"
                        ) {
                            syncClaude()
                        }

                        ToolbarIconButton(
                            title: gatewayPowerTitle,
                            detail: gatewayPowerDetail,
                            systemImage: runner.isRunning ? "stop.fill" : "play.fill",
                            isDisabled: runner.isBusy
                        ) {
                            if runner.isRunning {
                                stopGateway()
                            } else {
                                startGateway()
                            }
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
                        .help("More Actions\nClear logs or open settings.")
                        .accessibilityLabel("More Actions")
                        .accessibilityHint("Open additional gateway actions.")
                    }
                }
                .toolbarBackground(.hidden, for: .windowToolbar)
        }
    }

    private var detailContent: some View {
        detailView
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .safeAreaInset(edge: .top, spacing: 0) {
            if shouldShowSettingsErrorBanner {
                SettingsStatusBanner(settings: settings, recoverySection: statusRecoverySection) { section in
                    navigation.selectedSection = section
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Color(nsColor: .windowBackgroundColor))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: shouldShowSettingsErrorBanner)
    }

    private var shouldShowSettingsErrorBanner: Bool {
        settings.statusIsError && !settings.statusMessage.isEmpty && !onboarding.isPresented
    }

    @ViewBuilder
    private var detailView: some View {
        switch navigation.selectedSection {
        case .overview:
            OverviewPage(
                settings: settings,
                runner: runner,
                snapshot: dashboard.snapshot,
                selectedRange: $selectedRange
            )
        case .requests:
            RequestsPage(snapshot: dashboard.snapshot, selectedRange: $selectedRange)
        case .issues:
            IssuesPage(snapshot: dashboard.snapshot)
        case .logs:
            LogsPage(runner: runner)
        case .configuration:
            ConfigurationPage(settings: settings)
        }
    }

    private var statusRecoverySection: GatewaySection? {
        guard settings.statusIsError else { return nil }

        let message = settings.statusMessage.lowercased()
        if message.contains("provider api key") || message.contains("local gateway key") || message.contains("密钥") {
            return .configuration
        }
        if message.contains("endpoint") || message.contains("url") || message.contains("端口") || message.contains("监听地址") {
            return .configuration
        }
        if message.contains("model") || message.contains("模型") {
            return .configuration
        }
        return nil
    }

    private var gatewayPowerTitle: String {
        if runner.isStarting {
            return "Starting Gateway"
        }
        if runner.isStopping {
            return "Stopping Gateway"
        }
        return runner.isRunning ? "Stop Gateway" : "Start Gateway"
    }

    private var gatewayPowerHelp: String {
        "\(gatewayPowerTitle)\n\(gatewayPowerDetail)"
    }

    private var gatewayPowerDetail: String {
        if runner.isStarting {
            return "The local gateway is starting."
        }
        if runner.isStopping {
            return "The local gateway is stopping."
        }
        if runner.isRunning {
            return "Stop the local gateway LaunchAgent."
        }
        return "Start the local gateway using saved settings."
    }

    private func startGateway() {
        runner.start()
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
        refreshGatewayState()
    }

    private func reloadFromDisk() {
        settings.load()
        refreshGatewayState()
    }

    private func clearLogs() {
        runner.clearLog()
        dashboard.clear(range: selectedRange)
    }

    private func refreshGatewayState() {
        runner.refreshStatus()
        dashboard.reload(from: runner.logStore, range: selectedRange)
    }

    private func wireStatusBarManager() {
        AppTerminationController.onPrepareTermination = { [weak onboarding] in
            onboarding?.dismissPresented()
        }
        let manager = StatusBarManager.shared
        manager.onStartGateway = { [weak runner] in
            runner?.start()
            runner?.refreshStatus()
        }
        manager.onStopGateway = { [weak runner] in
            runner?.stop()
            runner?.refreshStatus()
        }
        manager.onOpenSection = { [weak navigation] section in
            navigation?.selectedSection = section
            openWindow(id: "main")
            MainWindowPresenter.showExistingMainWindow()
            DispatchQueue.main.async {
                MainWindowPresenter.showExistingMainWindow()
            }
        }
    }
}

@MainActor
final class GatewayNavigationStore: ObservableObject {
    @Published var selectedSection: GatewaySection = .overview
}

enum GatewaySection: String, CaseIterable, Identifiable {
    case overview
    case requests
    case issues
    case logs
    case configuration

    var id: String { rawValue }

    static let monitor: [GatewaySection] = [.overview, .requests, .issues, .logs]
    static let configurationSections: [GatewaySection] = [.configuration]

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
        case .configuration:
            return "Configuration"
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
        case .configuration:
            return "slider.horizontal.3"
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
                ForEach(GatewaySection.configurationSections) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .contentMargins(.top, 8, for: .scrollContent)
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

private struct ToolbarIconButton: View {
    var title: String
    var detail: String
    var systemImage: String
    var isDisabled = false
    var action: () -> Void

    @State private var isTooltipVisible = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Button {
            isTooltipVisible = false
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .disabled(isDisabled)
        .help("\(title)\n\(detail)")
        .accessibilityLabel(title)
        .accessibilityHint(detail)
        .onHover(perform: handleHover)
        .onDisappear {
            hoverTask?.cancel()
            hoverTask = nil
        }
        .popover(isPresented: $isTooltipVisible, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(width: 240, alignment: .leading)
        }
    }

    private func handleHover(_ isHovering: Bool) {
        hoverTask?.cancel()
        if isHovering {
            hoverTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled else { return }
                isTooltipVisible = true
            }
        } else {
            isTooltipVisible = false
        }
    }
}

private struct OverviewPage: View {
    @ObservedObject var settings: ProxySettingsStore
    @ObservedObject var runner: ProxyController
    var snapshot: GatewayDashboardSnapshot
    @Binding var selectedRange: GatewayDashboardRange

    var body: some View {
        NativePage {
            PageHeader(
                title: "Gateway Overview",
                subtitle: "Monitor local traffic and keep Claude configured for the local gateway."
            ) {
                RangePicker(selection: $selectedRange)
            }

            StatusSummaryGroup(
                settings: settings,
                runner: runner,
                snapshot: snapshot
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
        }
    }
}

private struct StatusSummaryGroup: View {
    @ObservedObject var settings: ProxySettingsStore
    @ObservedObject var runner: ProxyController
    var snapshot: GatewayDashboardSnapshot

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
                        detail: settings.primaryProviderBaseURL,
                        systemImage: "network",
                        tint: .blue
                    )
                }

                GridRow {
                    SummaryCell(
                        title: "Models",
                        value: "\(settings.advertisedModels.count) advertised",
                        detail: "Explicit provider routes are editable in Models",
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

                    SummaryCell(
                        title: "Log Tail",
                        value: "\(snapshot.requestRows.count) loaded",
                        detail: "Recent traffic is available in Requests and Logs",
                        systemImage: "doc.text.magnifyingglass",
                        tint: .secondary
                    )
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

    var body: some View {
        NativePage {
            PageHeader(
                title: "Logs",
                subtitle: "Structured and plain proxy events from the persistent log file."
            )

            LogTimelineView(runner: runner)
                .frame(minHeight: 560)
        }
    }
}

private struct ConfigurationPage: View {
    @ObservedObject var settings: ProxySettingsStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NativePage {
            PageHeader(
                title: "Configuration",
                subtitle: "Review gateway readiness, inspect what Claude will use, and jump into focused settings only when something needs editing."
            ) {
                Button {
                    openSettings()
                } label: {
                    Label("Open Settings", systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
                .help("Open the focused configuration editor.")
            }

            ConfigurationReadinessBanner(settings: settings)

            HStack(alignment: .top, spacing: 18) {
                ConfigurationChecklist(settings: settings)
                    .frame(maxWidth: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 18) {
                    CardSection(title: "Claude Client", systemImage: "laptopcomputer") {
                        VStack(alignment: .leading, spacing: 12) {
                            ConfigurationFactRow(label: "Gateway URL", value: "http://\(settings.host):\(settings.portText)")
                            ConfigurationFactRow(label: "Visible Models", value: "\(settings.advertisedModels.count)")
                            ConfigurationFactRow(label: "Default Target", value: settings.defaultTargetDescription)

                            HStack(spacing: 8) {
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(settings.claudeConfigSnippet, forType: .string)
                                } label: {
                                    Label("Copy Snippet", systemImage: "doc.on.doc")
                                }

                                Button {
                                    openSettings()
                                } label: {
                                    Label("Edit Client Settings", systemImage: "slider.horizontal.3")
                                }
                            }
                        }
                    }

                    CardSection(title: "Runtime", systemImage: "shippingbox") {
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
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }

            CardSection(title: "Files", systemImage: "folder") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Config") {
                        SelectablePath(settings.configPathForDisplay)
                    }
                }
            }
        }
    }
}

private struct ConfigurationReadinessBanner: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: isReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 30, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isReady ? .green : .orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(isReady ? "Gateway configuration is ready" : "Configuration needs attention")
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(isReady ? "Claude can use the local gateway after sync." : "Open Settings to finish required connection, credential, or model fields.")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .layoutPriority(1)

            Spacer()

            Text("\(completedCount)/\(items.count)")
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(isReady ? .green : .orange)
                .frame(minWidth: 48, alignment: .trailing)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isReady ? Color.green : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke((isReady ? Color.green : Color.orange).opacity(0.35), lineWidth: 1)
        }
    }

    private var items: [ConfigurationChecklistItem] {
        ConfigurationChecklistItem.make(settings: settings)
    }

    private var completedCount: Int {
        items.filter(\.isComplete).count
    }

    private var isReady: Bool {
        items.allSatisfy(\.isComplete)
    }
}

private struct ConfigurationChecklist: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        CardSection(title: "Setup Checklist", systemImage: "checklist") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                    }
                    ConfigurationChecklistRow(item: item)
                }
            }
        }
    }

    private var items: [ConfigurationChecklistItem] {
        ConfigurationChecklistItem.make(settings: settings)
    }
}

private struct ConfigurationChecklistRow: View {
    var item: ConfigurationChecklistItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(item.isComplete ? .green : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Text(item.status)
                .font(.caption.weight(.medium))
                .foregroundStyle(item.isComplete ? Color.secondary : Color.orange)
                .lineLimit(1)
        }
        .padding(.vertical, 12)
    }
}

private struct ConfigurationChecklistItem: Identifiable, Hashable {
    var title: String
    var detail: String
    var status: String
    var isComplete: Bool

    var id: String { title }

    @MainActor
    static func make(settings: ProxySettingsStore) -> [ConfigurationChecklistItem] {
        let host = settings.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = settings.portText.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = settings.primaryProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let localKey = settings.localGatewayKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultTarget = settings.defaultRouteModel.trimmingCharacters(in: .whitespacesAndNewlines)

        return [
            ConfigurationChecklistItem(
                title: "Connection",
                detail: host.isEmpty || port.isEmpty ? "Local listener is incomplete." : "\(host):\(port) forwards to \(endpoint)",
                status: host.isEmpty || port.isEmpty || endpoint.isEmpty ? "Required" : "Ready",
                isComplete: !host.isEmpty && !port.isEmpty && !endpoint.isEmpty
            ),
            ConfigurationChecklistItem(
                title: "Credentials",
                detail: "Provider credentials and the local gateway key protect traffic at different boundaries.",
                status: !settings.providerCredentialsReady || localKey.isEmpty ? "Required" : "Ready",
                isComplete: settings.providerCredentialsReady && !localKey.isEmpty
            ),
            ConfigurationChecklistItem(
                title: "Model Routing",
                detail: "\(settings.advertisedModels.count) Claude-visible models use explicit provider routes.",
                status: settings.advertisedModels.isEmpty || defaultTarget.isEmpty ? "Required" : "Ready",
                isComplete: !settings.advertisedModels.isEmpty && !defaultTarget.isEmpty
            ),
            ConfigurationChecklistItem(
                title: "Vision Provider",
                detail: settings.visionProviderAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Optional image preprocessing is available without blocking text traffic." : "\(settings.visionProvider) key is configured.",
                status: "Optional",
                isComplete: true
            ),
            ConfigurationChecklistItem(
                title: "Runtime",
                detail: settings.runtimeStatusMessage.isEmpty ? "Runtime status has not reported yet." : settings.runtimeStatusMessage,
                status: settings.runtimeStatusIsError ? "Repair" : "Ready",
                isComplete: !settings.runtimeStatusIsError
            ),
        ]
    }
}

private struct ConfigurationFactRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value.isEmpty ? "-" : value)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
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
                CompactEmptyState(
                    title: "No Requests",
                    systemImage: "chart.xyaxis.line",
                    description: "No traffic was recorded in the selected range."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
            CompactEmptyState(
                title: emptyTitle,
                systemImage: "tray",
                description: emptyDescription
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
                    CompactEmptyState(
                        title: "No Request Selected",
                        systemImage: "sidebar.trailing",
                        description: "Select a request to inspect its details."
                    )
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

private struct CompactEmptyState: View {
    var title: String
    var systemImage: String
    var description: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(description)
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
    var subtitle: String?
    @ViewBuilder var content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
    var recoverySection: GatewaySection?
    var openRecoverySection: (GatewaySection) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: settings.statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(displayMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.tail)
            }
            .layoutPriority(1)

            Spacer(minLength: 16)

            if let recoverySection {
                Button {
                    openRecoverySection(recoverySection)
                } label: {
                    Label("Open \(recoverySection.title)", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }

            Button {
                settings.dismissStatusMessage()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(settings.statusIsError ? 0.16 : 0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(tint.opacity(settings.statusIsError ? 0.55 : 0.35), lineWidth: 1)
        }
    }

    private var title: String {
        settings.statusIsError ? "Action Required" : "Settings Updated"
    }

    private var displayMessage: String {
        let message = settings.statusMessage
        for prefix in ["操作失败：", "操作失败: "] where message.hasPrefix(prefix) {
            return String(message.dropFirst(prefix.count))
        }
        return message
    }

    private var tint: Color {
        settings.statusIsError ? .red : .green
    }
}

private struct InlineStatus: View {
    var message: String
    var isError: Bool
    var monospaced = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(tint)
            Text(message)
                .font(monospaced ? .system(.caption, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(tint.opacity(isError ? 0.14 : 0.1), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(isError ? 0.45 : 0.3), lineWidth: 1)
        }
    }

    private var tint: Color {
        isError ? .red : .green
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
