import AppKit
import GatewayProxyCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: ProxySettingsStore
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                ConnectionSettingsPane(settings: settings)
                    .tabItem {
                        Label("Connection", systemImage: "network")
                    }

                ProviderSettingsPane(settings: settings)
                    .tabItem {
                        Label("Providers", systemImage: "server.rack")
                    }

                ModelSettingsPane(settings: settings)
                    .tabItem {
                        Label("Models", systemImage: "rectangle.stack")
                    }

                VisionSettingsPane(settings: settings)
                    .tabItem {
                        Label("Vision", systemImage: "eye")
                    }

                ClaudeSettingsPane(settings: settings)
                    .tabItem {
                        Label("Claude", systemImage: "laptopcomputer")
                    }

                UpdatesSettingsPane(updateChecker: updateChecker)
                    .tabItem {
                        Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                    }

                RuntimeSettingsPane(settings: settings)
                    .tabItem {
                        Label("Runtime", systemImage: "shippingbox")
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            SettingsFooter(settings: settings)
        }
        .frame(width: 720, height: 560)
    }
}

private struct ConnectionSettingsPane: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        NativeSettingsForm(settings: settings) {
            Section("Local Gateway") {
                SettingsTextFieldRow(
                    "Listen Address",
                    text: $settings.host,
                    placeholder: "127.0.0.1",
                    help: "Keep this on 127.0.0.1 unless another local process needs to reach the gateway."
                )

                SettingsTextFieldRow(
                    "Port",
                    text: $settings.portText,
                    placeholder: "4000",
                    help: "Claude clients will connect to this local port."
                )
            }

            Section("Local Authentication") {
                SettingsSecureFieldRow(
                    "Local Gateway Key",
                    text: $settings.localGatewayKey,
                    placeholder: "Bearer token",
                    help: "Claude clients use this local bearer token; it is separate from provider keys."
                ) {
                    Button {
                        settings.generateLocalGatewayKey()
                    } label: {
                        Label("Generate", systemImage: "key.fill")
                    }
                }
            }
        }
    }
}

private struct ProviderSettingsPane: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        NativeSettingsForm(settings: settings) {
            Section("Providers") {
                ForEach(settings.providers.indices, id: \.self) { index in
                    ProviderEditor(
                        provider: $settings.providers[index],
                        apiKey: settings.bindingForProviderAPIKey(settings.providers[index].id),
                        headersText: settings.bindingForProviderHeaders(settings.providers[index].id),
                        canRemove: settings.providers.count > 1,
                        applyProfile: { profileID in
                            settings.applyCompatibilityProfile(profileID, toProviderAt: index)
                        }
                    ) {
                        settings.removeProvider(id: settings.providers[index].id)
                    }
                }

                Button {
                    settings.addProvider()
                } label: {
                    Label("Add Provider", systemImage: "plus")
                }
            }
        }
    }
}

private struct ProviderEditor: View {
    @Binding var provider: GatewayProvider
    @Binding var apiKey: String
    @Binding var headersText: String
    var canRemove: Bool
    var applyProfile: (String) -> Void
    var remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(provider.nameForDisplay)
                    .font(.headline)
                Spacer()
                if canRemove {
                    Button(role: .destructive) {
                        remove()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }

            SettingsTextFieldRow("Provider ID", text: $provider.id, placeholder: "custom")
            SettingsTextFieldRow("Display Name", text: $provider.displayName, placeholder: "Custom Anthropic-compatible")
            SettingsTextFieldRow("Base URL", text: $provider.baseURL, placeholder: "https://provider.example.com/anthropic")

            VStack(alignment: .leading, spacing: 8) {
                SettingsControlRow("Compatibility Profile", controlAlignment: .trailing) {
                    Picker("", selection: $provider.compatibilityProfileID) {
                        ForEach(GatewayProviderProfileCatalog.profiles) { profile in
                            Text(profile.displayName).tag(profile.id)
                        }
                    }
                    .labelsHidden()
                }

                HStack {
                    Text(GatewayProviderProfileCatalog.profile(id: provider.compatibilityProfileID).detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        applyProfile(provider.compatibilityProfileID)
                    } label: {
                        Label("Apply Recommended Defaults", systemImage: "wand.and.stars")
                    }
                }
            }

            SettingsControlRow("Auth", controlAlignment: .trailing) {
                Picker("", selection: $provider.auth.type) {
                    ForEach(GatewayProviderAuth.supportedTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .labelsHidden()
            }

            if provider.auth.type == GatewayProviderAuth.customHeader {
                SettingsTextFieldRow("Auth Header", text: $provider.auth.customHeaderName, placeholder: "x-api-key")
            }

            if provider.auth.type != GatewayProviderAuth.none {
                SettingsSecureFieldRow("API Key", text: $apiKey, placeholder: "Provider key")
            }

            SettingsControlRow("Anthropic Beta Header", controlAlignment: .trailing) {
                Picker("", selection: $provider.anthropicBetaHeaderMode) {
                    ForEach(GatewayProvider.supportedAnthropicBetaHeaderModes, id: \.self) { mode in
                        Text(mode).tag(mode)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Default Headers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $headersText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 54)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("System Prompt Injection")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $provider.systemPromptInjection)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 88)
                Text("Appended to this provider's upstream system prompt. Keep it stable for prompt/context cache; avoid timestamps, random values, session IDs, or live status.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Generate Claude Code append prompt file", isOn: $provider.claudeCode.appendSystemPromptEnabled)
                SettingsTextFieldRow(
                    "Prompt Path",
                    text: $provider.claudeCode.appendSystemPromptPath,
                    placeholder: GatewayProviderClaudeCodeSettings.defaultAppendSystemPromptPath
                )
                TextEditor(text: $provider.claudeCode.appendSystemPromptText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 100)
                Text("Used only with Claude Code --append-system-prompt-file. It is not injected into upstream requests.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct ModelSettingsPane: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        NativeSettingsForm(settings: settings) {
            Section("Default Route") {
                RouteProviderPicker("Provider", selection: $settings.defaultRouteProviderID, providers: settings.providers)
                SettingsTextFieldRow("Upstream Model", text: $settings.defaultRouteModel, placeholder: "provider-model")
            }

            Section("Model Routes") {
                ForEach(settings.modelRoutes.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(settings.modelRoutes[index].alias.isEmpty ? "Route" : settings.modelRoutes[index].alias)
                                .font(.headline)
                            Spacer()
                            Button(role: .destructive) {
                                settings.removeModelRoute(at: index)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .disabled(settings.modelRoutes.count <= 1)
                        }
                        SettingsTextFieldRow("Claude Alias", text: $settings.modelRoutes[index].alias, placeholder: "claude-sonnet-4-6")
                        RouteProviderPicker("Provider", selection: $settings.modelRoutes[index].providerID, providers: settings.providers)
                        SettingsTextFieldRow("Upstream Model", text: $settings.modelRoutes[index].upstreamModel, placeholder: "provider-model")
                    }
                    .padding(.vertical, 6)
                }

                HStack {
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
        }
    }
}

private struct RouteProviderPicker: View {
    var label: String
    @Binding var selection: String
    var providers: [GatewayProvider]

    init(_ label: String, selection: Binding<String>, providers: [GatewayProvider]) {
        self.label = label
        _selection = selection
        self.providers = providers
    }

    var body: some View {
        SettingsControlRow(label, controlAlignment: .trailing) {
            Picker("", selection: $selection) {
                ForEach(providers) { provider in
                    Text(provider.nameForDisplay).tag(provider.id)
                }
            }
            .labelsHidden()
        }
    }
}

private struct VisionSettingsPane: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        NativeSettingsForm(settings: settings) {
            Section("Provider") {
                SettingsControlRow(
                    "Provider",
                    help: "Auto keeps the current provider behavior; choose a provider when routing vision requests explicitly.",
                    controlAlignment: .trailing
                ) {
                    Picker("", selection: $settings.visionProvider) {
                        ForEach(ProxyDiskSettings.supportedVisionProviders, id: \.self) { provider in
                            Text(provider).tag(provider)
                        }
                    }
                    .labelsHidden()
                }

                SettingsTextFieldRow(
                    "Vision Model",
                    text: $settings.visionProviderModel,
                    placeholder: "qwen3-vl-flash",
                    help: "Examples: qwen3-vl-flash, gemini-2.5-flash, or gpt-4o-mini."
                )

                SettingsTextFieldRow(
                    "Vision Base URL",
                    text: $settings.visionProviderBaseURL,
                    placeholder: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                    help: "Optional provider base URL for OpenAI-compatible vision endpoints."
                )
            }

            Section("Credential") {
                SettingsSecureFieldRow(
                    "Vision Provider API Key",
                    text: $settings.visionProviderAPIKey,
                    placeholder: "Optional key",
                    help: "Only needed when the selected vision provider requires an API key."
                )

                CredentialStatusRow(
                    label: "Vision Provider API Key",
                    value: settings.visionProviderAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Optional, not configured" : "Configured",
                    isAttention: false
                )
            }
        }
    }
}

private struct ClaudeSettingsPane: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        NativeSettingsForm(settings: settings) {
            Section("Client Snippet") {
                Text(settings.claudeConfigSnippet)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(settings.claudeConfigSnippet, forType: .string)
                } label: {
                    Label("Copy Config Snippet", systemImage: "doc.on.doc")
                }
            }

            Section("Claude Code Append Prompt") {
                Text(settings.claudeCodeAppendPromptCommand)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Text("This command uses the current default route provider's Claude Code prompt file. The default path is provider-neutral.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Last Sync") {
                ScrollView {
                    StatusText(
                        message: settings.claudeSyncStatusMessage.isEmpty ? "No sync has run in this session." : settings.claudeSyncStatusMessage,
                        isError: settings.claudeSyncStatusIsError,
                        monospaced: true
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.vertical, 2)
                }
                .frame(height: 96)
            }
        }
    }
}

private struct UpdatesSettingsPane: View {
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        Form {
            Section("Update Checking") {
                Toggle("Automatically check for updates", isOn: $updateChecker.autoCheckEnabled)

                HStack {
                    Button {
                        Task { await updateChecker.checkForUpdates() }
                    } label: {
                        if updateChecker.isChecking {
                            Label("Checking...", systemImage: "hourglass")
                        } else {
                            Label("Check Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(updateChecker.isChecking)

                    Spacer()
                }
                .padding(.vertical, 2)
            }

            Section("Status") {
                if updateChecker.isUpdateAvailable, let version = updateChecker.latestVersion {
                    LabeledContent("Latest Version") {
                        Text("v\(version)")
                            .foregroundStyle(.blue)
                            .fontWeight(.medium)
                    }
                    LabeledContent("Action") {
                        Link("Download from GitHub", destination: URL(string: "https://github.com/JUNERDD/claude-gateway/releases/latest")!)
                    }
                } else if updateChecker.latestVersion != nil {
                    LabeledContent("Status") {
                        Label("Up to date", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else if updateChecker.isChecking {
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Checking...")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    LabeledContent("Status") {
                        Text("Not checked yet")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = updateChecker.errorMessage {
                    LabeledContent("Error") {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                if let date = updateChecker.lastCheckDate {
                    LabeledContent("Last Checked") {
                        Text(date, style: .date)
                            .foregroundStyle(.secondary)
                        Text(date, style: .time)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RuntimeSettingsPane: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        NativeSettingsForm(settings: settings) {
            Section("Runtime") {
                LabeledContent("Status") {
                    Label(
                        settings.runtimeStatusIsError ? "Needs Attention" : "Runtime Ready",
                        systemImage: settings.runtimeStatusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .foregroundStyle(settings.runtimeStatusIsError ? .orange : .green)
                }

                if !settings.runtimeStatusMessage.isEmpty {
                    Text(settings.runtimeStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button {
                    settings.installBundledRuntime()
                    settings.load()
                } label: {
                    Label("Install or Repair", systemImage: "wrench.and.screwdriver")
                }
            }

            Section("Files") {
                LabeledContent("Config") {
                    SelectablePath(settings.configPathForDisplay)
                }

                HStack {
                    Button {
                        importConfig()
                    } label: {
                        Label("Import Config", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        exportConfig()
                    } label: {
                        Label("Export Config", systemImage: "square.and.arrow.up")
                    }
                }
            }
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
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "claude-gateway-config.json"
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.exportConfig(to: url)
    }
}

private struct NativeSettingsForm<Content: View>: View {
    @ObservedObject var settings: ProxySettingsStore
    @ViewBuilder var content: Content

    init(settings: ProxySettingsStore, @ViewBuilder content: () -> Content) {
        self.settings = settings
        self.content = content()
    }

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SettingsFooter: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        VStack(spacing: 10) {
            StatusText(
                message: settings.statusMessage.isEmpty ? " " : settings.statusMessage,
                isError: settings.statusIsError
            )
            .lineLimit(2)
            .truncationMode(.tail)
            .frame(height: 32, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .opacity(settings.statusMessage.isEmpty ? 0 : 1)

            HStack {
                Button {
                    settings.load()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }

                Spacer()

                if settings.isPersistingAndSyncing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Saving...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    settings.save()
                } label: {
                    Label("Save, Sync, and Start", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(settings.isPersistingAndSyncing)
            }
            .frame(height: 30)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(height: 98)
        .background(.bar)
    }
}

private struct CredentialStatusRow: View {
    var label: String
    var value: String
    var isAttention: Bool

    var body: some View {
        LabeledContent(label) {
            Label(value, systemImage: isAttention ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isAttention ? .orange : .secondary)
        }
    }
}

private struct SettingsTextFieldRow: View {
    var label: String
    @Binding var text: String
    var placeholder: String
    var help: String?

    init(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        help: String? = nil
    ) {
        self.label = label
        _text = text
        self.placeholder = placeholder
        self.help = help
    }

    var body: some View {
        SettingsControlRow(label, help: help) {
            TextField("", text: $text, prompt: Text(placeholder))
                .textFieldStyle(.roundedBorder)
                .frame(width: SettingsFieldLayout.controlWidth)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .accessibilityLabel(label)
        }
    }
}

private struct SettingsSecureFieldRow<Accessory: View>: View {
    var label: String
    @Binding var text: String
    var placeholder: String
    var help: String?
    @ViewBuilder var accessory: Accessory

    init(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        help: String? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.label = label
        _text = text
        self.placeholder = placeholder
        self.help = help
        self.accessory = accessory()
    }

    var body: some View {
        SettingsControlRow(label, help: help) {
            SecureField("", text: $text, prompt: Text(placeholder))
                .textFieldStyle(.roundedBorder)
                .frame(width: SettingsFieldLayout.controlWidth)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .accessibilityLabel(label)
        } accessory: {
            accessory
        }
    }
}

private enum SettingsFieldLayout {
    static let labelWidth: CGFloat = 190
    static let controlWidth: CGFloat = 280
    static let infoSize: CGFloat = 18
}

private struct SettingsControlRow<Control: View, Accessory: View>: View {
    let label: String
    let help: String?
    let controlAlignment: Alignment
    let control: Control
    let accessory: Accessory

    init(
        _ label: String,
        help: String? = nil,
        controlAlignment: Alignment = .leading,
        @ViewBuilder control: () -> Control,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.label = label
        self.help = help
        self.controlAlignment = controlAlignment
        self.control = control()
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 6) {
                Text(label)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                if let help {
                    SettingsFieldHelpIcon(text: help)
                        .frame(width: SettingsFieldLayout.infoSize, height: SettingsFieldLayout.infoSize)
                }

                Spacer(minLength: 0)
            }
            .frame(width: SettingsFieldLayout.labelWidth, alignment: .leading)

            Spacer(minLength: 16)

            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 0) {
                    control
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: SettingsFieldLayout.controlWidth, alignment: controlAlignment)

                accessory
            }
            .frame(maxWidth: SettingsFieldLayout.controlWidth + 140, alignment: .trailing)
            .layoutPriority(1)
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
    }
}

private extension SettingsControlRow where Accessory == EmptyView {
    init(
        _ label: String,
        help: String? = nil,
        controlAlignment: Alignment = .leading,
        @ViewBuilder control: () -> Control
    ) {
        self.init(label, help: help, controlAlignment: controlAlignment, control: control) {
            EmptyView()
        }
    }
}

private struct SettingsFieldHelpIcon: View {
    var text: String
    @State private var isTooltipVisible = false
    @State private var tooltipWorkItem: DispatchWorkItem?

    var body: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 12, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .help(text)
            .accessibilityLabel("Field help")
            .accessibilityValue(text)
            .onHover { isHovering in
                tooltipWorkItem?.cancel()

                if isHovering {
                    let workItem = DispatchWorkItem {
                        isTooltipVisible = true
                    }
                    tooltipWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
                } else {
                    isTooltipVisible = false
                }
            }
            .onDisappear {
                tooltipWorkItem?.cancel()
            }
            .popover(isPresented: $isTooltipVisible, arrowEdge: .trailing) {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(width: 260, alignment: .leading)
            }
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

private struct StatusText: View {
    var message: String
    var isError: Bool
    var monospaced = false

    var body: some View {
        Text(message)
            .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
            .foregroundStyle(isError ? .red : .secondary)
            .textSelection(.enabled)
    }
}
