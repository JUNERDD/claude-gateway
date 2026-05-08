import AppKit
import SwiftUI

@MainActor
enum AppLifecycleState {
    static var isTerminating = false
}

@MainActor
enum MainWindowPresenter {
    static let identifier = NSUserInterfaceItemIdentifier("ClaudeDeepSeekGateway.mainWindow")

    static func showExistingMainWindow() {
        if let window = NSApp.windows.first(where: { $0.identifier == identifier }) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MainWindowBehavior: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = MainWindowAttachmentView(frame: .zero)
        view.onWindowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let view = view as? MainWindowAttachmentView {
            view.onWindowChanged = { [weak coordinator = context.coordinator] window in
                coordinator?.attach(to: window)
            }
            context.coordinator.attach(to: view.window)
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private weak var window: NSWindow?
        private weak var previousDelegate: NSWindowDelegate?

        func attach(to window: NSWindow?) {
            guard let window, self.window !== window else { return }
            detach()
            self.window = window
            previousDelegate = window.delegate
            window.identifier = MainWindowPresenter.identifier
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.standardWindowButton(.closeButton)?.target = self
            window.standardWindowButton(.closeButton)?.action = #selector(handleCloseButton(_:))
        }

        func detach() {
            if window?.delegate === self {
                window?.delegate = previousDelegate
            }
            window = nil
            previousDelegate = nil
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard !AppLifecycleState.isTerminating else { return true }
            sender.orderOut(nil)
            return false
        }

        @objc private func handleCloseButton(_ sender: Any?) {
            guard !AppLifecycleState.isTerminating else {
                window?.close()
                return
            }
            window?.orderOut(nil)
        }
    }
}

private final class MainWindowAttachmentView: NSView {
    var onWindowChanged: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?(window)
    }
}
