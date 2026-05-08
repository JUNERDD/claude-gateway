import AppKit
import SwiftUI

@MainActor
final class StatusBarManager: ObservableObject {
    static let shared = StatusBarManager()

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?

    var onStartGateway: (() -> Void)?
    var onStopGateway: (() -> Void)?
    var onOpenSection: ((GatewaySection) -> Void)?

    @Published var isRunning: Bool = false

    private init() {}

    private enum StatusBarIcon {
        static let stopped = "network.slash"
        static let running = "network"
        static let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
    }

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.behavior = .terminationOnRemoval
        item.autosaveName = "ClaudeGatewayMenuBar"

        let image = NSImage(
            systemSymbolName: StatusBarIcon.stopped,
            accessibilityDescription: "Gateway Stopped"
        )?.withSymbolConfiguration(StatusBarIcon.symbolConfig)
        image?.isTemplate = true

        item.button?.image = image
        statusItem = item
        buildMenu(running: false)
    }

    func teardown() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
        statusMenu = nil
    }

    func updateStatus(running: Bool) {
        guard isRunning != running else { return }
        isRunning = running

        let symbolName = running ? StatusBarIcon.running : StatusBarIcon.stopped
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: running ? "Gateway Running" : "Gateway Stopped"
        )?.withSymbolConfiguration(StatusBarIcon.symbolConfig)
        image?.isTemplate = true

        statusItem?.button?.image = image
        // Let the template image auto-adapt to light/dark mode for both states

        buildMenu(running: running)
    }

    private func buildMenu(running: Bool) {
        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(
            title: running
                ? "Gateway Running"
                : "Gateway Stopped",
            action: nil,
            keyEquivalent: ""
        )
        statusMenuItem.attributedTitle = NSAttributedString(
            string: statusMenuItem.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        if running {
            let stopItem = NSMenuItem(
                title: "Stop Gateway",
                action: #selector(handleStopGateway),
                keyEquivalent: ""
            )
            stopItem.target = self
            stopItem.image = NSImage(
                systemSymbolName: "stop.fill",
                accessibilityDescription: nil
            )
            menu.addItem(stopItem)
        } else {
            let startItem = NSMenuItem(
                title: "Start Gateway",
                action: #selector(handleStartGateway),
                keyEquivalent: ""
            )
            startItem.target = self
            startItem.image = NSImage(
                systemSymbolName: "play.fill",
                accessibilityDescription: nil
            )
            menu.addItem(startItem)
        }

        menu.addItem(.separator())

        for section in GatewaySection.allCases {
            let item = NSMenuItem(
                title: section.title,
                action: #selector(handlePageSwitch(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.image = NSImage(
                systemSymbolName: section.systemImage,
                accessibilityDescription: nil
            )
            item.representedObject = section
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Open Settings...",
            action: #selector(handleOpenSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: nil
        )
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: "Quit Claude Gateway",
            action: #selector(handleQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.image = NSImage(
            systemSymbolName: "xmark.square",
            accessibilityDescription: nil
        )
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusMenu = menu
    }

    @objc private func handleStartGateway() {
        onStartGateway?()
    }

    @objc private func handleStopGateway() {
        onStopGateway?()
    }

    @objc private func handlePageSwitch(_ sender: NSMenuItem) {
        guard let section = sender.representedObject as? GatewaySection else { return }
        onOpenSection?(section)
    }

    @objc private func handleOpenSettings() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @objc private func handleQuit() {
        AppLifecycleState.isTerminating = true
        NSApp.terminate(nil)
    }
}
