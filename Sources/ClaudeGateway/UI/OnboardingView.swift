import AppKit
import GatewayProxyCore
import SwiftUI
import UniformTypeIdentifiers

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
                OnboardingStepList(selectedStep: selectedStep, steps: visibleSteps)
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
        .onChange(of: settings.activeProviderUsesDeepSeekCompatibilityProfile) { _, _ in
            normalizeSelectedStepIfNeeded()
        }
        .onChange(of: settings.visionSettingsAreValid) { _, _ in
            normalizeSelectedStepIfNeeded()
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
                Text("Claude Gateway Setup")
                    .font(.headline)
                Text("Step \(selectedStepNumber) of \(visibleSteps.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ProgressView(value: Double(selectedStepNumber), total: Double(visibleSteps.count))
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
            VStack(alignment: .leading, spacing: 16) {
                OnboardingFieldBlock(title: "Local Endpoint", detail: "Claude clients connect to this gateway endpoint on this Mac.") {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Address")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("127.0.0.1", text: $settings.host)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Listen Address")
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Port")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("4000", text: $settings.portText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                                .accessibilityLabel("Port")
                        }
                    }
                }

                OnboardingInfoRow(systemImage: "lock", title: "Local keys", detail: "Claude receives only the local gateway key. Provider keys stay in the local config file.")
                OnboardingInfoRow(systemImage: "list.bullet.rectangle", title: "Monitor traffic", detail: "Requests, issues, logs, and runtime status remain available in the main window.")

                OnboardingStatusNote(
                    systemImage: settings.localEndpointIsComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    text: localEndpointStatusText,
                    level: settings.localEndpointIsComplete ? .success : .warning
                )

                Button {
                    importConfig()
                } label: {
                    Label("Import Config", systemImage: "square.and.arrow.down")
                }
            }
        case .provider:
            VStack(alignment: .leading, spacing: 16) {
                if let index = primaryProviderIndex {
                    OnboardingFieldBlock(title: "Provider Base URL", detail: "Anthropic-compatible upstream endpoint.") {
                        TextField("https://provider.example.com/anthropic", text: $settings.providers[index].baseURL)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Provider Base URL")
                    }

                    OnboardingFieldBlock(title: "Compatibility Profile", detail: "Provider-specific defaults for routes, Claude Code prompt, and compatibility handling.") {
                        Picker("", selection: $settings.providers[index].compatibilityProfileID) {
                            ForEach(GatewayProviderProfileCatalog.profiles) { profile in
                                Text(profile.displayName).tag(profile.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260, alignment: .leading)
                        .accessibilityLabel("Compatibility Profile")
                        .onAppear {
                            applyInitialProfileDefaultsIfNeeded(providerAt: index)
                        }
                        .onChange(of: settings.providers[index].compatibilityProfileID) { _, profileID in
                            applyOnboardingCompatibilityProfile(profileID, providerAt: index)
                        }
                    }

                    OnboardingFieldBlock(title: "Provider Auth", detail: "Authentication mode used for upstream requests.") {
                        Picker("", selection: $settings.providers[index].auth.type) {
                            ForEach(GatewayProviderAuth.supportedTypes, id: \.self) { type in
                                Text(type).tag(type)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 220, alignment: .leading)
                        .accessibilityLabel("Provider Auth")
                    }

                    if settings.providers[index].auth.type == GatewayProviderAuth.customHeader {
                        OnboardingFieldBlock(title: "Auth Header", detail: "Header name used for custom provider authentication.") {
                            TextField("x-api-key", text: $settings.providers[index].auth.customHeaderName)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Auth Header")
                        }
                    }

                    if providerShouldShowAPIKey(settings.providers[index]) {
                        OnboardingFieldBlock(title: "Provider API Key", detail: "Required by the selected provider auth mode.") {
                            SecureField("Provider key", text: settings.bindingForProviderAPIKey(settings.providers[index].id))
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Provider API Key")
                        }
                    }
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
                    systemImage: providerCanContinue ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    text: providerStatusText,
                    level: providerCanContinue ? .success : .warning
                )
            }
        case .modelRoutes:
            VStack(alignment: .leading, spacing: 16) {
                OnboardingFieldBlock(title: "Default Route", detail: "Fallback upstream model for unmapped Claude model names.") {
                    VStack(alignment: .leading, spacing: 8) {
                        OnboardingProviderPicker(
                            selection: $settings.defaultRouteProviderID,
                            providers: settings.providers,
                            accessibilityLabel: "Default Route Provider"
                        )

                        TextField("provider-default-model", text: $settings.defaultRouteModel)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Default Route Upstream Model")
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Model Routes")
                        .font(.headline)

                    ForEach(settings.modelRoutes.indices, id: \.self) { index in
                        OnboardingRouteEditor(
                            route: $settings.modelRoutes[index],
                            providers: settings.providers,
                            canRemove: settings.modelRoutes.count > 1
                        ) {
                            settings.removeModelRoute(at: index)
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            settings.addModelRoute()
                        } label: {
                            Label("Add Route", systemImage: "plus")
                        }

                        Button {
                            settings.resetModelDefaults()
                        } label: {
                            Label("Reset Defaults", systemImage: "arrow.counterclockwise")
                        }
                    }
                }

                OnboardingStatusNote(
                    systemImage: modelRoutesReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    text: modelRoutesReady ? "Model routing is ready." : "Add at least one unique Claude alias and upstream model.",
                    level: modelRoutesReady ? .success : .warning
                )
            }
        case .vision:
            VStack(alignment: .leading, spacing: 16) {
                OnboardingInfoRow(
                    systemImage: "eye",
                    title: "Vision bridge for DeepSeek",
                    detail: "DeepSeek handles the Claude-compatible text route. Configure a separate vision provider here for image inputs."
                )

                OnboardingFieldBlock(title: "Vision Provider", detail: "Choose the provider used by the Vision MCP bridge.") {
                    Picker("", selection: $settings.visionProvider) {
                        ForEach(ProxyDiskSettings.supportedVisionProviders, id: \.self) { provider in
                            Text(provider).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240, alignment: .leading)
                    .accessibilityLabel("Vision Provider")
                }

                OnboardingFieldBlock(title: "Vision Model", detail: "Leave empty to use the selected provider's built-in default.") {
                    TextField("qwen3-vl-flash", text: $settings.visionProviderModel)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Vision Model")
                }

                OnboardingFieldBlock(title: "Vision Base URL", detail: "Optional custom http/https endpoint for the vision provider.") {
                    TextField("https://dashscope.aliyuncs.com/compatible-mode/v1", text: $settings.visionProviderBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Vision Base URL")
                }

                OnboardingFieldBlock(title: "Vision Provider API Key", detail: "Only required when your selected vision provider needs a key.") {
                    SecureField("Optional key", text: $settings.visionProviderAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Vision Provider API Key")
                }

                OnboardingStatusNote(
                    systemImage: settings.visionSettingsAreValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    text: visionStatusText,
                    level: settings.visionSettingsAreValid ? .success : .warning
                )
            }
        case .syncAndStart:
            VStack(alignment: .leading, spacing: 12) {
                OnboardingChecklistRow(systemImage: "square.and.arrow.down", title: "Save config", detail: "Writes the single local gateway config file.")
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

            if selectedStep != .welcome {
                Button {
                    moveBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(selectedStep == .verify && settings.isPersistingAndSyncing)
            }

            primaryFooterButton
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    @ViewBuilder
    private var primaryFooterButton: some View {
        Group {
            switch selectedStep {
            case .welcome:
                Button {
                    moveForward()
                } label: {
                    Label("Continue", systemImage: "arrow.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!settings.localEndpointIsComplete)
            case .provider:
                Button {
                    continueFromProviderStep()
                } label: {
                    Label("Continue", systemImage: "arrow.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!providerCanContinue)
            case .modelRoutes:
                Button {
                    moveForward()
                } label: {
                    Label("Continue", systemImage: "arrow.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!modelRoutesReady)
            case .vision:
                Button {
                    moveForward()
                } label: {
                    Label("Continue", systemImage: "arrow.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!settings.visionSettingsAreValid)
            case .syncAndStart:
                Button {
                    saveSyncAndStart()
                } label: {
                    Label("Save, Sync, and Start", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!settings.localEndpointIsComplete || !providerReady || !modelRoutesReady || !settings.visionSettingsAreValid || settings.isPersistingAndSyncing)
            case .verify:
                if settings.isPersistingAndSyncing {
                    Button {} label: {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Working...")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
                } else if hasTriggeredSync, settings.statusIsError {
                    Button {
                        selectedStep = firstIncompleteStep
                    } label: {
                        Label("Fix Setup", systemImage: "wrench.and.screwdriver")
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
        .frame(minWidth: 176, alignment: .trailing)
    }

    private var primaryProviderIndex: Array<GatewayProvider>.Index? {
        settings.providers.firstIndex { $0.id == settings.defaultProviderID } ?? settings.providers.indices.first
    }

    private var visibleSteps: [OnboardingStep] {
        OnboardingStep.steps(includeVision: shouldShowVisionStep)
    }

    private var shouldShowVisionStep: Bool {
        settings.activeProviderUsesDeepSeekCompatibilityProfile || !settings.visionSettingsAreValid
    }

    private var selectedStepNumber: Int {
        (visibleSteps.firstIndex(of: selectedStep) ?? 0) + 1
    }

    private var firstIncompleteStep: OnboardingStep {
        if !settings.localEndpointIsComplete { return .welcome }
        if !providerReady { return .provider }
        if !modelRoutesReady { return .modelRoutes }
        if visibleSteps.contains(.vision), !settings.visionSettingsAreValid { return .vision }
        return .syncAndStart
    }

    private var localEndpointStatusText: String {
        let host = settings.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let portText = settings.portText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            return "Add a listen address before continuing."
        }
        guard let port = Int(portText), (1...65535).contains(port) else {
            return "Port must be a number from 1 to 65535."
        }
        return "Endpoint preview: http://\(host):\(port)"
    }

    private var visionStatusText: String {
        guard settings.visionSettingsAreValid else {
            return "Vision Base URL must be empty or a valid http/https URL."
        }
        let provider = settings.visionProvider.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.visionProviderModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = settings.visionProviderAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider == "auto" {
            return key.isEmpty ? "Auto mode will use available environment/config keys; text routing is unaffected." : "Auto mode is ready with a configured vision key."
        }
        if key.isEmpty {
            return "\(provider) is selected; add a key now or configure one later before using image inputs."
        }
        return model.isEmpty ? "\(provider) is configured and will use its default vision model." : "\(provider) is configured with \(model)."
    }

    private var providerReady: Bool {
        guard let index = primaryProviderIndex else { return false }
        return providerIsReady(settings.providers[index])
    }

    private var providerCanContinue: Bool {
        guard let index = primaryProviderIndex else { return false }
        let provider = settings.providers[index]
        return providerIsReady(provider) || providerCanBecomeReadyAfterApplyingProfile(provider)
    }

    private var providerStatusText: String {
        guard let index = primaryProviderIndex else {
            return "Add a provider to continue."
        }
        let provider = settings.providers[index]
        if providerIsReady(provider) {
            return "Provider credentials are ready."
        }

        let profile = GatewayProviderProfileCatalog.profile(id: provider.compatibilityProfileID)
        if profileHasRecommendedDefaults(profile) {
            if profile.recommendedAuth.requiresAPIKey {
                let key = settings.providerAPIKeys[provider.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if key.isEmpty {
                    return "Add the provider API key required by \(profile.displayName)."
                }
            }
            if providerCanBecomeReadyAfterApplyingProfile(provider) {
                return "\(profile.displayName) defaults will be applied when you continue."
            }
        }

        let baseURL = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !validHTTPURL(baseURL) {
            return "Add a valid http or https provider base URL."
        }
        if provider.auth.type == GatewayProviderAuth.customHeader, !customAuthHeaderReady(provider.auth.customHeaderName) {
            return "Add a valid custom auth header name."
        }
        if provider.auth.requiresAPIKey {
            let key = settings.providerAPIKeys[provider.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if key.isEmpty {
                return "Add the provider API key required by this auth mode."
            }
        }
        return "Provider credentials are ready."
    }

    private var modelRoutesReady: Bool {
        let providerIDs = Set(settings.providers.map(\.id))
        guard providerIDs.contains(settings.defaultRouteProviderID) else { return false }
        guard !settings.defaultRouteModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !settings.modelRoutes.isEmpty else { return false }

        var aliases = Set<String>()
        for route in settings.modelRoutes {
            let alias = route.alias.trimmingCharacters(in: .whitespacesAndNewlines)
            let upstreamModel = route.upstreamModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !alias.isEmpty, !upstreamModel.isEmpty, providerIDs.contains(route.providerID) else {
                return false
            }
            guard !aliases.contains(alias) else { return false }
            aliases.insert(alias)
        }
        return true
    }

    private func providerIsReady(_ provider: GatewayProvider) -> Bool {
        let baseURL = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validHTTPURL(baseURL) else { return false }
        if provider.auth.type == GatewayProviderAuth.customHeader {
            guard customAuthHeaderReady(provider.auth.customHeaderName) else { return false }
        }
        guard provider.auth.requiresAPIKey else { return true }
        let key = settings.providerAPIKeys[provider.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !key.isEmpty
    }

    private func providerCanBecomeReadyAfterApplyingProfile(_ provider: GatewayProvider) -> Bool {
        let profile = GatewayProviderProfileCatalog.profile(id: provider.compatibilityProfileID)
        guard profileHasRecommendedDefaults(profile) else { return false }
        guard validHTTPURL(profile.recommendedBaseURL) else { return false }
        if profile.recommendedAuth.type == GatewayProviderAuth.customHeader {
            guard customAuthHeaderReady(profile.recommendedAuth.customHeaderName) else { return false }
        }
        guard profile.recommendedAuth.requiresAPIKey else { return true }
        let key = settings.providerAPIKeys[provider.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !key.isEmpty
    }

    private func providerShouldShowAPIKey(_ provider: GatewayProvider) -> Bool {
        if provider.auth.type != GatewayProviderAuth.none {
            return true
        }
        let profile = GatewayProviderProfileCatalog.profile(id: provider.compatibilityProfileID)
        return profileHasRecommendedDefaults(profile) && profile.recommendedAuth.requiresAPIKey
    }

    private func profileHasRecommendedDefaults(_ profile: GatewayProviderCompatibilityProfile) -> Bool {
        !profile.recommendedBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func customAuthHeaderReady(_ value: String) -> Bool {
        let header = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !header.isEmpty && !GatewayProvider.gatewayManagedHeaders.contains(header.lowercased())
    }

    private func validHTTPURL(_ value: String) -> Bool {
        guard let url = URL(string: value),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            url.host != nil
        else {
            return false
        }
        return true
    }

    private var displayStatusMessage: String {
        let message = settings.statusMessage
        for prefix in ["操作失败：", "操作失败: "] where message.hasPrefix(prefix) {
            return String(message.dropFirst(prefix.count))
        }
        return message.isEmpty ? "Setup could not complete." : message
    }

    private func continueFromProviderStep() {
        guard let index = primaryProviderIndex else { return }
        let provider = settings.providers[index]
        if providerCanBecomeReadyAfterApplyingProfile(provider) {
            settings.applyCompatibilityProfile(provider.compatibilityProfileID, toProviderAt: index)
        }
        if settings.localGatewayKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.generateLocalGatewayKey()
        }
        guard providerReady else { return }
        moveForward()
    }

    private func applyOnboardingCompatibilityProfile(_ profileID: String, providerAt index: Int) {
        guard settings.providers.indices.contains(index) else { return }
        settings.applyCompatibilityProfile(profileID, toProviderAt: index)
    }

    private func applyInitialProfileDefaultsIfNeeded(providerAt index: Int) {
        guard settings.providers.indices.contains(index) else { return }
        let provider = settings.providers[index]
        let profile = GatewayProviderProfileCatalog.profile(id: provider.compatibilityProfileID)
        let baseURL = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard profileHasRecommendedDefaults(profile), baseURL.isEmpty else { return }
        settings.applyCompatibilityProfile(profile.id, toProviderAt: index)
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
        guard let next = adjacentStep(offset: 1) else { return }
        selectedStep = next
    }

    private func moveBack() {
        guard let previous = adjacentStep(offset: -1) else { return }
        selectedStep = previous
    }

    private func adjacentStep(offset: Int) -> OnboardingStep? {
        guard let index = visibleSteps.firstIndex(of: selectedStep) else {
            return visibleSteps.first
        }
        let targetIndex = index + offset
        guard visibleSteps.indices.contains(targetIndex) else { return nil }
        return visibleSteps[targetIndex]
    }

    private func normalizeSelectedStepIfNeeded() {
        guard !visibleSteps.contains(selectedStep) else { return }
        selectedStep = firstIncompleteStep
    }

    private func dismissWithoutCompleting() {
        if coordinator.isInitialFlow {
            coordinator.skipInitialFlow()
        } else {
            coordinator.dismissPresented()
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        settings.importConfig(from: url)
        if !settings.statusIsError, settings.localEndpointIsComplete, providerReady, modelRoutesReady, settings.visionSettingsAreValid {
            selectedStep = .syncAndStart
        } else if !settings.statusIsError {
            selectedStep = firstIncompleteStep
        }
    }
}

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case provider
    case modelRoutes
    case vision
    case syncAndStart
    case verify

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .welcome:
            return "Overview"
        case .provider:
            return "Provider"
        case .modelRoutes:
            return "Models"
        case .vision:
            return "Vision"
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
        case .provider:
            return "key"
        case .modelRoutes:
            return "rectangle.stack"
        case .vision:
            return "eye"
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
        case .provider:
            return "Connect a provider"
        case .modelRoutes:
            return "Confirm model routes"
        case .vision:
            return "Configure vision"
        case .syncAndStart:
            return "Sync clients and start"
        case .verify:
            return "Verify setup"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            return "Claude Gateway runs locally and routes Claude-compatible requests to your configured provider."
        case .provider:
            return "Add provider credentials and keep a separate local bearer key for Claude clients."
        case .modelRoutes:
            return "Map Claude-visible model names to the upstream model names your provider accepts."
        case .vision:
            return "Add an optional image-capable provider for DeepSeek workflows that include images."
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

    static func steps(includeVision: Bool) -> [OnboardingStep] {
        includeVision
            ? [.welcome, .provider, .modelRoutes, .vision, .syncAndStart, .verify]
            : [.welcome, .provider, .modelRoutes, .syncAndStart, .verify]
    }
}

private struct OnboardingStepList: View {
    var selectedStep: OnboardingStep
    var steps: [OnboardingStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(steps) { step in
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

private struct OnboardingRouteEditor: View {
    @Binding var route: GatewayModelRoute
    var providers: [GatewayProvider]
    var canRemove: Bool
    var remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("claude-sonnet-4-6", text: $route.alias)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Claude Alias")

                Button(role: .destructive) {
                    remove()
                } label: {
                    Label("Remove", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .disabled(!canRemove)
                .help("Remove route")
            }

            OnboardingProviderPicker(
                selection: $route.providerID,
                providers: providers,
                accessibilityLabel: "Route Provider"
            )

            TextField("provider-model", text: $route.upstreamModel)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Route Upstream Model")
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct OnboardingProviderPicker: View {
    @Binding var selection: String
    var providers: [GatewayProvider]
    var accessibilityLabel: String

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(providers) { provider in
                Text(provider.nameForDisplay).tag(provider.id)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 260, alignment: .leading)
        .accessibilityLabel(accessibilityLabel)
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
