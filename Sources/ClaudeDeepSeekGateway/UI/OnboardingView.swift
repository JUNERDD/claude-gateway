import SwiftUI

struct OnboardingView: View {
    @ObservedObject var settings: ProxySettingsStore
    @ObservedObject var coordinator: OnboardingCoordinator
    var onSyncCompleted: () -> Void

    @State private var selectedStep: OnboardingStep = .welcome
    @State private var hasTriggeredSync = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            HStack(spacing: 0) {
                OnboardingStepList(selectedStep: selectedStep)
                    .frame(width: 190, alignment: .top)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(selectedStep.title)
                            .font(.title2.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)

                        Text(selectedStep.subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        stepContent
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.never)
            }

            Divider()

            footerControls
        }
        .frame(width: 720, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: settings.isPersistingAndSyncing) { wasSyncing, isSyncing in
            guard wasSyncing, !isSyncing, hasTriggeredSync else { return }
            onSyncCompleted()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude DeepSeek Gateway Setup")
                    .font(.headline)
                Text("Step \(selectedStep.rawValue + 1) of \(OnboardingStep.allCases.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ProgressView(value: Double(selectedStep.rawValue + 1), total: Double(OnboardingStep.allCases.count))
                .progressViewStyle(.linear)
                .frame(width: 150)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch selectedStep {
        case .welcome:
            VStack(alignment: .leading, spacing: 12) {
                OnboardingInfoRow(systemImage: "network", title: "Local endpoint", detail: "Claude connects to http://\(settings.host):\(settings.portText) on this Mac.")
                OnboardingInfoRow(systemImage: "lock", title: "Separate secrets", detail: "Claude receives only the local gateway key. Your DeepSeek key remains in local app-managed secrets.")
                OnboardingInfoRow(systemImage: "list.bullet.rectangle", title: "Monitor traffic", detail: "Requests, issues, logs, and runtime status remain available in the main window.")
            }
        case .secureKeys:
            VStack(alignment: .leading, spacing: 16) {
                OnboardingFieldBlock(title: "DeepSeek API Key", detail: "Required for text requests forwarded to DeepSeek.") {
                    SecureField("sk-...", text: $settings.deepSeekAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("DeepSeek API Key")
                }

                OnboardingFieldBlock(title: "Local Gateway Key", detail: "Bearer token used by local Claude clients.") {
                    HStack(spacing: 8) {
                        SecureField("Bearer token", text: $settings.localGatewayKey)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Local Gateway Key")

                        Button {
                            settings.generateLocalGatewayKey()
                        } label: {
                            Label("Generate", systemImage: "key.fill")
                        }
                    }
                }

                OnboardingStatusNote(
                    systemImage: deepSeekKeyReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    text: deepSeekKeyReady ? "Required credentials are ready." : "Paste a DeepSeek API key to continue, or skip setup for now.",
                    level: deepSeekKeyReady ? .success : .warning
                )
            }
        case .syncAndStart:
            VStack(alignment: .leading, spacing: 12) {
                OnboardingChecklistRow(systemImage: "square.and.arrow.down", title: "Save settings and secrets", detail: "Writes local config and secrets files.")
                OnboardingChecklistRow(systemImage: "laptopcomputer", title: "Sync Claude clients", detail: "Updates Claude Desktop and Claude Code gateway configuration.")
                OnboardingChecklistRow(systemImage: "play.fill", title: "Start background service", detail: "Starts the LaunchAgent so Claude can reach the gateway.")

                OnboardingStatusNote(
                    systemImage: "network",
                    text: "Endpoint preview: http://\(settings.host):\(settings.portText)",
                    level: .plain
                )
            }
        case .verify:
            verifyContent
        }
    }

    @ViewBuilder
    private var verifyContent: some View {
        if settings.isPersistingAndSyncing {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Saving, syncing, and starting...")
                        .font(.headline)
                }

                Text("Runtime files are checked, Claude client settings are refreshed, and the LaunchAgent is started.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if hasTriggeredSync, settings.statusIsError {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingStatusNote(systemImage: "exclamationmark.triangle.fill", text: displayStatusMessage, level: .warning)
                Text("Fix the required fields, then run setup again.")
                    .foregroundStyle(.secondary)
            }
        } else if hasTriggeredSync, !settings.statusMessage.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                OnboardingStatusNote(systemImage: "checkmark.circle.fill", text: "Gateway setup is complete.", level: .success)
                OnboardingInfoRow(systemImage: "arrow.clockwise", title: "Restart Claude clients", detail: "Fully quit and reopen Claude Desktop, or start a new Claude Code session.")
                OnboardingInfoRow(systemImage: "list.bullet.rectangle", title: "Watch requests", detail: "Traffic will appear in Requests and Logs after Claude sends a message.")
            }
        } else {
            OnboardingStatusNote(systemImage: "checkmark.circle", text: "Ready to run setup.", level: .plain)
        }
    }

    private var footerControls: some View {
        HStack(spacing: 12) {
            Button {
                dismissWithoutCompleting()
            } label: {
                Text(coordinator.isInitialFlow ? "Skip for Now" : "Close")
            }

            Spacer()

            if selectedStep != .welcome, selectedStep != .verify || !settings.isPersistingAndSyncing {
                Button {
                    moveBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }

            primaryFooterButton
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    @ViewBuilder
    private var primaryFooterButton: some View {
        switch selectedStep {
        case .welcome:
            Button {
                moveForward()
            } label: {
                Label("Continue", systemImage: "arrow.right")
            }
            .buttonStyle(.borderedProminent)
        case .secureKeys:
            Button {
                if settings.localGatewayKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    settings.generateLocalGatewayKey()
                }
                moveForward()
            } label: {
                Label("Continue", systemImage: "arrow.right")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!deepSeekKeyReady)
        case .syncAndStart:
            Button {
                saveSyncAndStart()
            } label: {
                Label("Save, Sync, and Start", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!deepSeekKeyReady || settings.isPersistingAndSyncing)
        case .verify:
            if settings.isPersistingAndSyncing {
                Button("Working...") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            } else if hasTriggeredSync, settings.statusIsError {
                Button {
                    selectedStep = .secureKeys
                } label: {
                    Label("Fix Credentials", systemImage: "key")
                }
                .buttonStyle(.borderedProminent)
            } else if hasTriggeredSync, !settings.statusMessage.isEmpty {
                Button {
                    settings.dismissStatusMessage()
                    coordinator.completeInitialFlow()
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    selectedStep = .syncAndStart
                } label: {
                    Label("Run Setup", systemImage: "arrow.right")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var deepSeekKeyReady: Bool {
        !settings.deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayStatusMessage: String {
        let message = settings.statusMessage
        for prefix in ["操作失败：", "操作失败: "] where message.hasPrefix(prefix) {
            return String(message.dropFirst(prefix.count))
        }
        return message.isEmpty ? "Setup could not complete." : message
    }

    private func saveSyncAndStart() {
        hasTriggeredSync = true
        selectedStep = .verify
        settings.syncClaudeDesktopConfig()
        if !settings.isPersistingAndSyncing {
            onSyncCompleted()
        }
    }

    private func moveForward() {
        guard let next = selectedStep.next else { return }
        selectedStep = next
    }

    private func moveBack() {
        guard let previous = selectedStep.previous else { return }
        selectedStep = previous
    }

    private func dismissWithoutCompleting() {
        if coordinator.isInitialFlow {
            coordinator.skipInitialFlow()
        } else {
            coordinator.dismissPresented()
        }
    }
}

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case secureKeys
    case syncAndStart
    case verify

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .welcome:
            return "Overview"
        case .secureKeys:
            return "Credentials"
        case .syncAndStart:
            return "Sync & Start"
        case .verify:
            return "Verify"
        }
    }

    var systemImage: String {
        switch self {
        case .welcome:
            return "network"
        case .secureKeys:
            return "key"
        case .syncAndStart:
            return "arrow.triangle.2.circlepath"
        case .verify:
            return "checkmark.seal"
        }
    }

    var title: String {
        switch self {
        case .welcome:
            return "Set up the local gateway"
        case .secureKeys:
            return "Add credentials"
        case .syncAndStart:
            return "Sync clients and start"
        case .verify:
            return "Verify setup"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            return "Claude DeepSeek Gateway runs locally and routes Claude-compatible requests to DeepSeek."
        case .secureKeys:
            return "Add the required DeepSeek key and keep a separate local bearer key for Claude clients."
        case .syncAndStart:
            return "Save settings, update Claude Desktop and Claude Code, then start the gateway service."
        case .verify:
            return "Confirm setup completed before switching back to the dashboard."
        }
    }

    var previous: OnboardingStep? {
        Self(rawValue: rawValue - 1)
    }

    var next: OnboardingStep? {
        Self(rawValue: rawValue + 1)
    }
}

private struct OnboardingStepList: View {
    var selectedStep: OnboardingStep

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(OnboardingStep.allCases) { step in
                HStack(spacing: 10) {
                    Image(systemName: step.systemImage)
                        .font(.body.weight(.medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(selectedStep == step ? Color.accentColor : .secondary)
                        .frame(width: 20)

                    Text(step.label)
                        .font(.callout.weight(selectedStep == step ? .semibold : .regular))
                        .foregroundStyle(selectedStep == step ? .primary : .secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selectedStep == step ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer()
        }
        .padding(14)
    }
}

private struct OnboardingInfoRow: View {
    var systemImage: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct OnboardingChecklistRow: View {
    var systemImage: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct OnboardingFieldBlock<Content: View>: View {
    var title: String
    var detail: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content
        }
    }
}

private struct OnboardingStatusNote: View {
    enum Level {
        case plain
        case success
        case warning
    }

    var systemImage: String
    var text: String
    var level: Level

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 22)

            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(level == .plain ? 0.08 : 0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(level == .plain ? 0.18 : 0.28), lineWidth: 1)
        }
    }

    private var tint: Color {
        switch level {
        case .plain:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        }
    }
}
