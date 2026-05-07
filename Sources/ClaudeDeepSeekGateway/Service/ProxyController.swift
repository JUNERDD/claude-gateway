import SwiftUI

// MARK: - Gateway service controller

private struct ProxyServiceStatus {
    var pid: Int32?
    var uptime: TimeInterval?
}

private func currentProxyServiceStatus() -> ProxyServiceStatus {
    let pid = LaunchAgentManager.runningPID()
    return ProxyServiceStatus(
        pid: pid,
        uptime: pid.flatMap { LaunchAgentManager.runningUptimeSeconds(pid: $0) }
    )
}

@MainActor
final class ProxyController: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var runningSince: Date?
    @Published var isStarting: Bool = false
    @Published var isStopping: Bool = false

    let logStore = PersistentLogStore()
    private var runningPID: Int32?
    private var statusRefreshTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?

    var isBusy: Bool {
        isStarting || isStopping
    }

    func clearLog() {
        logStore.clearPersistentLog {}
    }

    func refreshStatus() {
        guard statusRefreshTask == nil else { return }
        statusRefreshTask = Task { [weak self] in
            let status = await Task.detached(priority: .utility) {
                currentProxyServiceStatus()
            }.value
            guard let self else { return }
            self.apply(status)
            self.statusRefreshTask = nil
        }
    }

    private func apply(_ status: ProxyServiceStatus) {
        let pid = status.pid
        isRunning = pid != nil

        if let pid {
            if runningPID != pid || runningSince == nil {
                runningSince = Date().addingTimeInterval(-(status.uptime ?? 0))
            }
            runningPID = pid
        } else {
            runningPID = nil
            runningSince = nil
        }
    }

    func start() {
        guard startTask == nil else { return }
        guard !isRunning else { return }
        isStarting = true
        startTask = Task { [weak self, logStore] in
            let status = await Task.detached(priority: .userInitiated) {
                Self.startService(logStore: logStore)
            }.value
            guard let self else { return }
            self.apply(status)
            self.isStarting = false
            self.startTask = nil
        }
    }

    private nonisolated static func startService(logStore: PersistentLogStore) -> ProxyServiceStatus {
        if !BundledRuntimeInstaller.runtimeLooksInstalled() {
            do {
                let report = try BundledRuntimeInstaller.installOrRepair()
                logStore.append("—— 运行时检查：\(report.userMessage) ——\n")
            } catch {
                logStore.append("运行时安装/修复失败: \(error.localizedDescription)\n")
            }
        }

        guard BundledRuntimeInstaller.hasUsableDeepSeekAPIKey() else {
            logStore.append("错误：未配置 DeepSeek API Key。请打开设置，填入 DEEPSEEK_API_KEY 并保存后再启动。\n")
            return currentProxyServiceStatus()
        }

        do {
            guard LaunchAgentManager.runningPID() == nil else {
                logStore.append("—— 常驻服务已在运行 ——\n")
                return currentProxyServiceStatus()
            }
            let message = try LaunchAgentManager.start()
            logStore.append("—— \(message) ——\n")
        } catch {
            logStore.append("启动失败: \(error.localizedDescription)\n")
        }
        return currentProxyServiceStatus()
    }

    func stop() {
        guard stopTask == nil else { return }
        guard isRunning else { return }
        isStopping = true
        stopTask = Task { [weak self, logStore] in
            let status = await Task.detached(priority: .userInitiated) {
                logStore.append("—— 正在停止常驻服务 ——\n")
                logStore.append("—— \(LaunchAgentManager.stop()) ——\n")
                return currentProxyServiceStatus()
            }.value
            guard let self else { return }
            self.apply(status)
            self.isStopping = false
            self.stopTask = nil
        }
    }
}
