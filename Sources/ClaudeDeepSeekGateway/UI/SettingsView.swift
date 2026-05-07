import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                GatewaySettingsPane(settings: settings)
                    .tabItem {
                        Label("Gateway", systemImage: "network")
                    }

                CredentialSettingsPane(settings: settings)
                    .tabItem {
                        Label("密钥", systemImage: "key.fill")
                    }

                ModelSettingsPane(settings: settings)
                    .tabItem {
                        Label("模型", systemImage: "rectangle.stack")
                    }

                ClaudeIntegrationPane(settings: settings)
                    .tabItem {
                        Label("Claude", systemImage: "arrow.triangle.2.circlepath")
                    }

                RuntimeSettingsPane(settings: settings)
                    .tabItem {
                        Label("运行时", systemImage: "wrench.and.screwdriver")
                    }
            }
            .padding(.top, 8)

            Divider()

            SettingsFooter(settings: settings)
        }
        .frame(width: 780, height: 700)
    }
}

private struct GatewaySettingsPane: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        SettingsPaneScroll {
            SettingsGroup(
                title: "Gateway",
                subtitle: "本地监听地址决定 Claude Desktop 和 Claude Code 连接到哪里。"
            ) {
                SettingsGrid {
                    GridRow {
                        SettingsLabel("监听地址")
                        TextField("127.0.0.1", text: $settings.host)
                            .textFieldStyle(.roundedBorder)
                    }

                    GridRow {
                        SettingsLabel("端口")
                        TextField("4000", text: $settings.portText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }

                    GridRow {
                        SettingsLabel("DeepSeek endpoint")
                        TextField("https://api.deepseek.com/anthropic", text: $settings.anthropicBaseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            SettingsGroup(
                title: "启动行为",
                subtitle: "保存动作会写入配置、同步 Claude 客户端，并更新 LaunchAgent。主窗口仍然保留手动启动和停止入口。"
            ) {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text("如果只想预览或复制配置片段，请使用 Claude 面板，不需要先保存。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct CredentialSettingsPane: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        SettingsPaneScroll {
            SettingsGroup(
                title: "Authentication",
                subtitle: "DeepSeek API Key 只写入本机 secrets 文件；本地 Gateway Key 用于保护本机代理。"
            ) {
                SettingsGrid {
                    GridRow {
                        SettingsLabel("DeepSeek API Key")
                        SecureField("sk-...", text: $settings.deepSeekAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    GridRow {
                        SettingsLabel("本地 Gateway Key")
                        HStack(spacing: 8) {
                            SecureField("Claude Desktop 使用这个 bearer key", text: $settings.localGatewayKey)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                settings.generateLocalGatewayKey()
                            } label: {
                                Label("生成", systemImage: "key.fill")
                            }
                        }
                    }
                }
            }

            SettingsGroup(title: "安全边界", subtitle: "默认只监听 127.0.0.1，避免局域网其他设备访问。") {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.green)
                    Text("本地 Gateway Key 与 DeepSeek API Key 分离，Claude 客户端只会看到本地 bearer token。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct ModelSettingsPane: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        SettingsPaneScroll {
            SettingsGroup(
                title: "Model Mapping",
                subtitle: "请求模型名只要包含 haiku 就转到 Haiku 目标；其他模型转到默认目标。"
            ) {
                SettingsGrid {
                    GridRow {
                        SettingsLabel("Haiku 目标")
                        TextField("deepseek-v4-flash", text: $settings.haikuTargetModel)
                            .textFieldStyle(.roundedBorder)
                    }

                    GridRow {
                        SettingsLabel("其他模型目标")
                        TextField("deepseek-v4-pro[1m]", text: $settings.nonHaikuTargetModel)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            SettingsGroup(
                title: "Claude Desktop Models",
                subtitle: "每行一个 Claude Desktop 可见模型名。这里决定 /v1/models 返回值，也就是菜单里能看到的 Models。"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $settings.advertisedModelsText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 170)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )

                    HStack {
                        Text("\(settings.advertisedModels.count) 个可见模型")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            settings.resetModelDefaults()
                        } label: {
                            Label("恢复默认模型", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
            }
        }
    }
}

private struct ClaudeIntegrationPane: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        SettingsPaneScroll {
            SettingsGroup(
                title: "Claude Client Sync",
                subtitle: "完全退出 Claude Desktop 并开启 Developer Mode 后，可用同步按钮写入 configLibrary；同时会合并 ~/.claude/settings.json。"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(settings.claudeConfigSnippet)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )

                    HStack(spacing: 8) {
                        Button {
                            settings.syncClaudeDesktopConfig()
                        } label: {
                            Label("保存、同步并启动", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .help("保存当前设置，同步 Claude Desktop / Claude Code 配置，并启动或刷新 LaunchAgent")

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(settings.claudeConfigSnippet, forType: .string)
                        } label: {
                            Label("复制配置片段", systemImage: "doc.on.doc")
                        }
                    }

                    if !settings.claudeSyncStatusMessage.isEmpty {
                        StatusMessageView(
                            message: settings.claudeSyncStatusMessage,
                            isError: settings.claudeSyncStatusIsError,
                            monospaced: true
                        )
                    }
                }
            }
        }
    }
}

private struct RuntimeSettingsPane: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        SettingsPaneScroll {
            SettingsGroup(
                title: "Runtime",
                subtitle: "应用会安装本地 gateway 二进制、启动脚本、默认配置和 LaunchAgent 支持文件。"
            ) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: settings.runtimeStatusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(settings.runtimeStatusIsError ? .yellow : .green)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(settings.runtimeStatusIsError ? "需要处理" : "运行时就绪")
                            .font(.headline)
                        Text(settings.runtimeStatusMessage.isEmpty ? "运行时状态未知。" : settings.runtimeStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    Button {
                        settings.installBundledRuntime()
                        settings.load()
                    } label: {
                        Label("安装/修复", systemImage: "wrench.and.screwdriver")
                    }
                }
                .padding(.vertical, 4)
            }

            SettingsGroup(title: "文件位置", subtitle: "这些路径用于排查配置和密钥写入状态。") {
                VStack(alignment: .leading, spacing: 8) {
                    FilePathRow(label: "配置", path: settings.configPathForDisplay)
                    FilePathRow(label: "密钥", path: settings.secretsPathForDisplay)
                }
            }
        }
    }
}

private struct SettingsFooter: View {
    @ObservedObject var settings: ProxySettingsStore

    var body: some View {
        VStack(spacing: 8) {
            if !settings.statusMessage.isEmpty {
                StatusMessageView(message: settings.statusMessage, isError: settings.statusIsError)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("配置：\(settings.configPathForDisplay)")
                    Text("密钥：\(settings.secretsPathForDisplay)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

                Spacer()

                Button {
                    settings.load()
                } label: {
                    Label("重新载入", systemImage: "arrow.clockwise")
                }

                Button {
                    settings.save()
                } label: {
                    Label("保存并启动 Gateway", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut(.defaultAction)
                .help("保存当前设置，同步 Claude 客户端配置，并启动或刷新 LaunchAgent")
            }
        }
        .padding(16)
        .background(.regularMaterial)
    }
}

private struct SettingsPaneScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: Content

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

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        )
    }
}

private struct SettingsGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            content
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsLabel: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }
}

private struct FilePathRow: View {
    var label: String
    var path: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
            Text(path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

private struct StatusMessageView: View {
    var message: String
    var isError: Bool
    var monospaced = false

    var body: some View {
        Text(message)
            .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
            .foregroundStyle(isError ? .red : .secondary)
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
            )
    }
}
