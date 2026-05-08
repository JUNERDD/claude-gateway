import Foundation

// MARK: - 磁盘日志（完整历史仅在文件；界面只保留尾部以控内存）

struct PersistentLogTailSignature: Equatable {
    var fileSize: UInt64
    var modificationTime: TimeInterval
    var maxBytes: Int
}

struct PersistentLogTailRead {
    var text: String
    var signature: PersistentLogTailSignature
}

final class PersistentLogStore {
    let fileURL: URL
    private let queue = DispatchQueue(label: "local.zen.ClaudeGateway.log")
    private var writeHandle: FileHandle?

    init(fileURL overrideFileURL: URL? = nil) {
        let fileURL: URL
        if let overrideFileURL {
            fileURL = overrideFileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            fileURL = base
                .appendingPathComponent("ClaudeGateway", isDirectory: true)
                .appendingPathComponent("proxy.log")
        }
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700,
        ])
        self.fileURL = fileURL
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
        readTail(maxBytes: maxBytes, ifChangedFrom: nil) { read in
            completion(read?.text ?? "")
        }
    }

    /// 读取文件尾部；如果签名未变化则返回 nil，避免上层重复解析同一段日志。
    func readTail(
        maxBytes: Int = 512_000,
        ifChangedFrom previousSignature: PersistentLogTailSignature?,
        completion: @escaping (PersistentLogTailRead?) -> Void
    ) {
        queue.async { [self] in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: self.fileURL.path),
                let sizeNumber = attrs[.size] as? NSNumber
            else {
                let signature = PersistentLogTailSignature(fileSize: 0, modificationTime: 0, maxBytes: maxBytes)
                DispatchQueue.main.async {
                    completion(previousSignature == signature ? nil : PersistentLogTailRead(text: "", signature: signature))
                }
                return
            }
            let size = sizeNumber.uint64Value
            let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let signature = PersistentLogTailSignature(fileSize: size, modificationTime: modified, maxBytes: maxBytes)
            guard previousSignature != signature else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            guard size > 0 else {
                DispatchQueue.main.async { completion(PersistentLogTailRead(text: "", signature: signature)) }
                return
            }
            guard let fh = try? FileHandle(forReadingFrom: self.fileURL) else {
                DispatchQueue.main.async { completion(PersistentLogTailRead(text: "", signature: signature)) }
                return
            }
            defer { try? fh.close() }
            let readLen = min(size, UInt64(maxBytes))
            do {
                try fh.seek(toOffset: size - readLen)
                let data = try fh.read(upToCount: Int(readLen)) ?? Data()
                let s = String(decoding: data, as: UTF8.self)
                DispatchQueue.main.async {
                    completion(PersistentLogTailRead(text: s, signature: signature))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(PersistentLogTailRead(text: "", signature: signature))
                }
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
