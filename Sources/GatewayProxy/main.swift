import Darwin
import Foundation

signal(SIGPIPE, SIG_IGN)

let environment = ProcessInfo.processInfo.environment
let settings = SettingsLoader.shared.load()
let secrets = SettingsLoader.shared.loadSecrets()
let host = environment["GATEWAY_HOST"] ?? settings.host
let port = Int(environment["GATEWAY_PORT"] ?? "") ?? settings.port
let masterKey = secrets.localGatewayKey
let serverFD = try openServerSocket(host: host, port: port)

print("Claude Gateway: http://\(host):\(port)")
print("Providers: \(settings.providers.map { $0.nameForDisplay }.joined(separator: ", "))")
print("Advertised models: \(settings.advertisedModels.joined(separator: ", "))")
print("Image attachment bridge: enabled; vision MCP endpoint: /v1/vision/describe")
fflush(stdout)

while true {
    let client = accept(serverFD, nil, nil)
    if client < 0 {
        if errno == EINTR {
            continue
        }
        break
    }
    DispatchQueue.global(qos: .userInitiated).async {
        HTTPConnection(
            fd: client,
            localMasterKey: masterKey
        ).handle()
    }
}
