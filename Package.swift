// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeDeepSeekGateway",
    platforms: [.macOS("14.4")],
    products: [
        .executable(name: "ClaudeDeepSeekGateway", targets: ["ClaudeDeepSeekGateway"]),
        .executable(name: "DeepSeekAliasProxy", targets: ["DeepSeekAliasProxy"]),
    ],
    targets: [
        .target(
            name: "DeepSeekAliasProxyCore",
            path: "Sources/DeepSeekAliasProxyCore"
        ),
        .executableTarget(
            name: "ClaudeDeepSeekGateway",
            path: "Sources/ClaudeDeepSeekGateway"
        ),
        .executableTarget(
            name: "DeepSeekAliasProxy",
            dependencies: ["DeepSeekAliasProxyCore"],
            path: "Sources/DeepSeekAliasProxy"
        ),
        .testTarget(
            name: "ClaudeDeepSeekGatewayTests",
            dependencies: ["ClaudeDeepSeekGateway", "DeepSeekAliasProxyCore"],
            path: "Tests/ClaudeDeepSeekGatewayTests"
        ),
    ]
)
