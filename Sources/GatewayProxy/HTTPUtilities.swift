import Darwin
import Foundation

func sanitizedResponseHeaders(_ response: HTTPURLResponse?) -> [String: String] {
    guard let response else { return [:] }
    var result: [String: String] = [:]
    for (key, value) in response.allHeaderFields {
        let name = String(describing: key)
        let lower = name.lowercased()
        guard !["set-cookie", "authorization", "x-api-key"].contains(lower) else { continue }
        result[name] = String(describing: value)
    }
    return result
}

func writeAll(_ fd: Int32, _ data: Data) {
    data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else { return }
        var written = 0
        while written < data.count {
            let result = Darwin.write(fd, baseAddress.advanced(by: written), data.count - written)
            if result <= 0 {
                return
            }
            written += result
        }
    }
}

func reasonPhrase(_ status: Int) -> String {
    switch status {
    case 200: return "OK"
    case 400: return "Bad Request"
    case 401: return "Unauthorized"
    case 404: return "Not Found"
    case 502: return "Bad Gateway"
    default: return "OK"
    }
}

func openServerSocket(host: String, port: Int) throws -> Int32 {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "socket() failed"])
    }

    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(port).bigEndian
    if inet_pton(AF_INET, host, &address.sin_addr) != 1 {
        close(fd)
        throw NSError(domain: "GatewayProxy", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid bind host \(host)"])
    }

    let bindResult = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else {
        let code = errno
        close(fd)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey: "bind(\(host):\(port)) failed"])
    }

    guard listen(fd, SOMAXCONN) == 0 else {
        let code = errno
        close(fd)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey: "listen() failed"])
    }

    return fd
}
