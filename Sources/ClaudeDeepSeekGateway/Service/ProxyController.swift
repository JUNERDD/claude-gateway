import SwiftUI

// MARK: - Gateway service controller

@MainActor
final class ProxyController: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var runningSince: Date?

    let logStore = PersistentLogStore()
    private var runningPID: Int32?

    func clearLog() {
        logStore.clearPersistentLog {}
    }

    private func append(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        logStore.append(chunk)
    }

    func refreshStatus() {
        let pid = LaunchAgentManager.runningPID()
        isRunning = pid != nil

        if let pid {
            if runningPID != pid || runningSince == nil {
                let uptime = LaunchAgentManager.runningUptimeSeconds(pid: pid)
                runningSince = Date().addingTimeInterval(-(uptime ?? 0))
            }
            runningPID = pid
        } else {
            runningPID = nil
            runningSince = nil
        }
    }

    func start() {
        refreshStatus()

        do {
            let report = try BundledRuntimeInstaller.installOrRepair()
            append("—— 运行时检查：\(report.userMessage) ——\n")
        } catch {
            append("运行时安装/修复失败: \(error.localizedDescription)\n")
        }

        guard BundledRuntimeInstaller.hasUsableDeepSeekAPIKey() else {
            append("错误：未配置 DeepSeek API Key。请打开设置，填入 DEEPSEEK_API_KEY 并保存后再启动。\n")
            return
        }

        do {
            let syncReport = ClaudeDesktopConfigSync.syncCurrentDiskConfig()
            append("—— Claude Desktop 配置：\(syncReport.userMessage) ——\n")
            guard !isRunning else {
                append("—— 常驻服务已在运行 ——\n")
                return
            }
            let message = try LaunchAgentManager.start()
            append("—— \(message) ——\n")
            refreshStatus()
        } catch {
            append("启动失败: \(error.localizedDescription)\n")
        }
    }

    func stop() {
        append("—— 正在停止常驻服务 ——\n")
        append("—— \(LaunchAgentManager.stop()) ——\n")
        refreshStatus()
    }
}
