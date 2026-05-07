import SwiftUI

@main
struct ClaudeDeepSeekGatewayApp: App {
    @StateObject private var proxySettings = ProxySettingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView(settings: proxySettings)
        }
        .defaultSize(width: 1512, height: 1040)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView(settings: proxySettings)
        }
    }
}
