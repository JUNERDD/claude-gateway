import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        TabView {
            ConnectionSettingsPane(settings: settings)
                .tabItem {
                    Label("Connection", systemImage: "network")
                }

            CredentialSettingsPane(settings: settings)
                .tabItem {
                    Label("Credentials", systemImage: "key")
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

            RuntimeSettingsPane(settings: settings)
                .tabItem {
                    Label("Runtime", systemImage: "shippingbox")
                }
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

            Section("Upstream") {
                SettingsTextFieldRow(
                    "DeepSeek Endpoint",
                    text: $settings.anthropicBaseURL,
                    placeholder: "https://api.deepseek.com/anthropic",
                    help: "Anthropic-compatible upstream endpoint used by the local gateway."
                )
            }
        }
    }
}

private struct CredentialSettingsPane: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        NativeSettingsForm(settings: settings) {
            Section("Secrets") {
                SettingsSecureFieldRow(
                    "DeepSeek API Key",
                    text: $settings.deepSeekAPIKey,
                    placeholder: "sk-...",
                    help: "Required for text requests forwarded to DeepSeek."
                )

                SettingsSecureFieldRow(
                    "Vision Provider API Key",
                    text: $settings.visionProviderAPIKey,
                    placeholder: "Optional key",
                    help: "Only needed when the selected vision provider requires an API key."
                )

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

            Section("Status") {
                CredentialStatusRow(
                    label: "DeepSeek",
                    value: settings.deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Required" : "Configured",
                    isAttention: settings.deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                CredentialStatusRow(
                    label: "Vision Provider",
                    value: settings.visionProviderAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Optional" : "Configured",
                    isAttention: false
                )
                CredentialStatusRow(
                    label: "Local Gateway",
                    value: settings.localGatewayKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Required" : "Generated",
                    isAttention: settings.localGatewayKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
    }
}

private struct ModelSettingsPane: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        NativeSettingsForm(settings: settings) {
            Section("Routing Targets") {
                SettingsTextFieldRow(
                    "Haiku Target",
                    text: $settings.haikuTargetModel,
                    placeholder: "deepseek-v4-flash",
                    help: "Used when the requested Claude model name contains haiku."
                )

                SettingsTextFieldRow(
                    "Default Target",
                    text: $settings.nonHaikuTargetModel,
                    placeholder: "deepseek-v4-pro[1m]",
                    help: "Used for all other Claude-visible models."
                )
            }

            Section("Advertised Models") {
                TextEditor(text: $settings.advertisedModelsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 150)

                LabeledContent("Count") {
                    Text("\(settings.advertisedModels.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Button {
                    settings.resetModelDefaults()
                } label: {
                    Label("Reset Defaults", systemImage: "arrow.counterclockwise")
                }
            }

            Section("Preview") {
                ForEach(Array(settings.advertisedModels.prefix(6).enumerated()), id: \.element) { index, model in
                    LabeledContent(model) {
                        Text(mappedTarget(for: model))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if index == 5, settings.advertisedModels.count > 6 {
                        Text("+ \(settings.advertisedModels.count - 6) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func mappedTarget(for model: String) -> String {
        model.localizedCaseInsensitiveContains("haiku") ? settings.haikuTargetModel : settings.nonHaikuTargetModel
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

            if !settings.claudeSyncStatusMessage.isEmpty {
                Section("Last Sync") {
                    StatusText(
                        message: settings.claudeSyncStatusMessage,
                        isError: settings.claudeSyncStatusIsError,
                        monospaced: true
                    )
                }
            }
        }
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

                LabeledContent("Secrets") {
                    SelectablePath(settings.secretsPathForDisplay)
                }
            }
        }
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

            if !settings.statusMessage.isEmpty {
                Section("Last Operation") {
                    StatusText(message: settings.statusMessage, isError: settings.statusIsError)
                }
            }

            Section {
                HStack {
                    Button {
                        settings.load()
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }

                    Spacer()

                    Button {
                        settings.save()
                    } label: {
                        Label("Save, Sync, and Start", systemImage: "square.and.arrow.down")
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .fixedSize(horizontal: true, vertical: false)
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
