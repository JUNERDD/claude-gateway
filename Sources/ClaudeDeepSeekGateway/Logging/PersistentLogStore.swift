import Foundation

// MARK: - 磁盘日志（完整历史仅在文件；界面只保留尾部以控内存）

final class PersistentLogStore {
    let fileURL: URL
    private let queue = DispatchQueue(label: "local.zen.ClaudeDeepSeekGateway.log")
    private var writeHandle: FileHandle?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent("ClaudeDeepSeekGateway", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700,
        ])
        fileURL = dir.appendingPathComponent("proxy.log")
    }

    var pathForDisplay: String {
        let home = NSHomeDirectory()
        let p = fileURL.path
        if p.hasPrefix(home) {
            return "~" + String(p.dropFirst(home.count))
        }
        return p
    }

    /// 追加写入磁盘（全量持久化）
    func append(_ string: String) {
        guard let data = string.data(using: .utf8), !data.isEmpty else { return }
        queue.async { [self] in
            do {
                try self.ensureWriteHandle()
                try self.writeHandle?.seekToEnd()
                try self.writeHandle?.write(contentsOf: data)
            } catch {
                // 写入失败时避免拖垮主流程，仅忽略（可后续加 OSLog）
            }
        }
    }

    /// 删除日志文件并关闭写句柄（「清空」与之一致）
    func clearPersistentLog(completion: @escaping () -> Void) {
        queue.async { [self] in
            do {
                try self.writeHandle?.close()
            } catch {}
            self.writeHandle = nil
            do {
                try FileManager.default.createDirectory(
                    at: self.fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                if FileManager.default.fileExists(atPath: self.fileURL.path) {
                    let handle = try FileHandle(forWritingTo: self.fileURL)
                    try handle.truncate(atOffset: 0)
                    try handle.close()
                } else {
                    FileManager.default.createFile(atPath: self.fileURL.path, contents: nil)
                }
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: self.fileURL.path)
            } catch {
                // 清理日志失败不应影响主流程；下一次写入会再次尝试创建文件。
            }
            DispatchQueue.main.async(execute: completion)
        }
    }

    /// 启动时把文件尾部载入界面（仅展示，不全读大文件）
    func readTail(maxBytes: Int = 512_000, completion: @escaping (String) -> Void) {
        queue.async { [self] in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: self.fileURL.path),
                let size = attrs[.size] as? NSNumber, size.intValue > 0
            else {
                DispatchQueue.main.async { completion("") }
                return
            }
            guard let fh = try? FileHandle(forReadingFrom: self.fileURL) else {
                DispatchQueue.main.async { completion("") }
                return
            }
            defer { try? fh.close() }
            let len = size.intValue
            let readLen = min(len, maxBytes)
            do {
                try fh.seek(toOffset: UInt64(len - readLen))
                let data = try fh.read(upToCount: readLen) ?? Data()
                let s = String(decoding: data, as: UTF8.self)
                DispatchQueue.main.async { completion(s) }
            } catch {
                DispatchQueue.main.async { completion("") }
            }
        }
    }

    private func ensureWriteHandle() throws {
        if writeHandle != nil, FileManager.default.fileExists(atPath: fileURL.path) { return }
        if writeHandle != nil {
            try? writeHandle?.close()
            writeHandle = nil
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }
        writeHandle = try FileHandle(forWritingTo: fileURL)
        try writeHandle?.seekToEnd()
    }
}
