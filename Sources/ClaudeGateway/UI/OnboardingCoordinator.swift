import Foundation
import SwiftUI

@MainActor
final class OnboardingCoordinator: ObservableObject {
    static let initialFlowDismissedKey = "ClaudeGateway.onboarding.initialFlowDismissed"

    @Published var isPresented = false
    @Published private(set) var presentationMode: OnboardingPresentationMode?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasDismissedInitialFlow: Bool {
        defaults.bool(forKey: Self.initialFlowDismissedKey)
    }

    var isInitialFlow: Bool {
        presentationMode == .initial
    }

    func presentIfNeeded() {
        guard !hasDismissedInitialFlow else { return }
        presentationMode = .initial
        isPresented = true
    }

    func showOnboarding() {
        presentationMode = .replay
        isPresented = true
    }

    func skipInitialFlow() {
        markInitialFlowDismissed()
        dismissPresented()
    }

    func completeInitialFlow() {
        if presentationMode == .initial {
            markInitialFlowDismissed()
        }
        dismissPresented()
    }

    func dismissPresented() {
        isPresented = false
        presentationMode = nil
    }

    private func markInitialFlowDismissed() {
        defaults.set(true, forKey: Self.initialFlowDismissedKey)
    }
}

enum OnboardingPresentationMode: Equatable {
    case initial
    case replay
}
