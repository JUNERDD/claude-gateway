import Darwin
import Foundation

enum LaunchAgentManager {
    static let label = "local.zen.ClaudeDeepSeekGateway.proxy"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    private static var domain: String {
        "gui/\(getuid())"
    }

    private static var serviceTarget: String {
        "\(domain)/\(label)"
    }

    private static var logURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("ClaudeDeepSeekGateway/proxy.log")
    }

    static func start() throws -> String {
        try writePlist()
        _ = runLaunchctl(["bootout", serviceTarget])

        let bootstrap = runLaunchctl(["bootstrap", domain, plistURL.path])
        guard bootstrap.exitCode == 0 else {
            throw NSError(domain: "LaunchAgentManager", code: Int(bootstrap.exitCode), userInfo: [
                NSLocalizedDescriptionKey: bootstrap.output.isEmpty ? "launchctl bootstrap 失败" : bootstrap.output,
            ])
        }

        let kickstart = runLaunchctl(["kickstart", "-k", serviceTarget])
        guard kickstart.exitCode == 0 else {
            throw NSError(domain: "LaunchAgentManager", code: Int(kickstart.exitCode), userInfo: [
                NSLocalizedDescriptionKey: kickstart.output.isEmpty ? "launchctl kickstart 失败" : kickstart.output,
            ])
        }

        Thread.sleep(forTimeInterval: 0.6)
        if let pid = runningPID() {
            return "常驻服务已启动 (PID \(pid))。"
        }
        return "常驻服务已交给 launchd 启动。"
    }

    static func stop() -> String {
        let result = runLaunchctl(["bootout", serviceTarget])
        if result.exitCode == 0 {
            return "常驻服务已停止。"
        }
        if result.output.localizedCaseInsensitiveContains("No such process")
            || result.output.localizedCaseInsensitiveContains("not found")
        {
            return "常驻服务未运行。"
        }
        return "停止常驻服务失败：\(result.output)"
    }

    static func runningPID() -> Int32? {
        let result = runLaunchctl(["print", serviceTarget])
        guard result.exitCode == 0 else { return nil }
        for rawLine in result.output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("pid = ") else { continue }
            let value = line.dropFirst("pid = ".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return Int32(value)
        }
        return nil
    }

    static func runningUptimeSeconds(pid: Int32) -> TimeInterval? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", "\(pid)", "-o", "etimes="]

        let out = Pipe()
        process.standardOutput = out

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let value = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = TimeInterval(value) else { return nil }
        return seconds
    }

    private static func writePlist() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700,
        ])

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                "/bin/zsh",
                "-lc",
                "exec \"$HOME/bin/claude-deepseek-gateway-proxy.sh\"",
            ],
            "RunAtLoad": true,
            "KeepAlive": [
                "SuccessfulExit": false,
            ],
            "ThrottleInterval": 10,
            "WorkingDirectory": home,
            "StandardOutPath": logURL.path,
            "StandardErrorPath": logURL.path,
            "EnvironmentVariables": [
                "HOME": home,
                "USER": NSUserName(),
                "PATH": "\(home)/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                "NO_COLOR": "1",
            ],
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plistURL.path)
    }

    private static func runLaunchctl(_ arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (1, error.localizedDescription)
        }

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outData + errData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus, output)
    }
}
