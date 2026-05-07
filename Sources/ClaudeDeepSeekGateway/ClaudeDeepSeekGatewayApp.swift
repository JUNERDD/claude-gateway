import SwiftUI

@main
struct ClaudeDeepSeekGatewayApp: App {
    @StateObject private var proxySettings = ProxySettingsStore()
    @StateObject private var onboarding = OnboardingCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView(settings: proxySettings, onboarding: onboarding)
        }
        .defaultSize(width: 1512, height: 1040)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .help) {
                Button {
                    onboarding.showOnboarding()
                } label: {
                    Label("Show Onboarding", systemImage: "sparkles")
                }
            }
        }

        Settings {
            SettingsView(settings: proxySettings)
        }
    }
}
