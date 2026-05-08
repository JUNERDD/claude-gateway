// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeGateway",
    platforms: [.macOS("14.4")],
    products: [
        .executable(name: "ClaudeGateway", targets: ["ClaudeGateway"]),
        .executable(name: "GatewayProxy", targets: ["GatewayProxy"]),
    ],
    targets: [
        .target(
            name: "GatewayProxyCore",
            path: "Sources/GatewayProxyCore"
        ),
        .executableTarget(
            name: "ClaudeGateway",
            dependencies: ["GatewayProxyCore"],
            path: "Sources/ClaudeGateway"
        ),
        .executableTarget(
            name: "GatewayProxy",
            dependencies: ["GatewayProxyCore"],
            path: "Sources/GatewayProxy"
        ),
        .testTarget(
            name: "ClaudeGatewayTests",
            dependencies: ["ClaudeGateway", "GatewayProxy", "GatewayProxyCore"],
            path: "Tests/ClaudeGatewayTests"
        ),
    ]
)
