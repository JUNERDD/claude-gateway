import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        StatusBarManager.shared.setup()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        MainWindowPresenter.showExistingMainWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppLifecycleState.isTerminating = true
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLifecycleState.isTerminating = true
        StatusBarManager.shared.teardown()
    }
}

@main
struct ClaudeDeepSeekGatewayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var proxySettings = ProxySettingsStore()
    @StateObject private var onboarding = OnboardingCoordinator()
    @StateObject private var runner = ProxyController()
    @StateObject private var navigation = GatewayNavigationStore()

    var body: some Scene {
        Window("Claude DeepSeek Gateway", id: "main") {
            ContentView(
                settings: proxySettings,
                onboarding: onboarding,
                runner: runner,
                navigation: navigation
            )
        }
        .defaultSize(width: 1512, height: 1040)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(replacing: .appTermination) {
                Button("Quit Claude DeepSeek Gateway") {
                    AppLifecycleState.isTerminating = true
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }

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
