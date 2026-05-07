import Darwin
import Foundation

signal(SIGPIPE, SIG_IGN)

let environment = ProcessInfo.processInfo.environment
guard let deepSeekAPIKey = environment["DEEPSEEK_API_KEY"], !deepSeekAPIKey.isEmpty, deepSeekAPIKey != "replace_me" else {
    fputs("DEEPSEEK_API_KEY is required\n", stderr)
    exit(1)
}

let settings = SettingsLoader.shared.load()
let host = environment["GATEWAY_HOST"] ?? settings.host
let port = Int(environment["GATEWAY_PORT"] ?? "") ?? settings.port
let masterKey = environment["LOCAL_GATEWAY_KEY"] ?? ""
let serverFD = try openServerSocket(host: host, port: port)

print("Claude DeepSeek Gateway: http://\(host):\(port)")
print("Model rewrite: *haiku* -> \(settings.haikuTargetModel); other -> \(settings.nonHaikuTargetModel)")
print("Image attachment bridge: enabled; vision MCP endpoint: /v1/vision/describe")
print("Advertised models: \(settings.advertisedModels.joined(separator: ", "))")
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
            localMasterKey: masterKey,
            deepSeekAPIKey: deepSeekAPIKey
        ).handle()
    }
}
