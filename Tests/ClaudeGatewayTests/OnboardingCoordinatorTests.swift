import XCTest
@testable import ClaudeGateway

@MainActor
final class OnboardingCoordinatorTests: XCTestCase {
    func testInitialFlowPresentsOnceUntilSkipped() throws {
        let defaults = try freshDefaults()
        let coordinator = OnboardingCoordinator(defaults: defaults)

        XCTAssertFalse(coordinator.hasDismissedInitialFlow)

        coordinator.presentIfNeeded()

        XCTAssertTrue(coordinator.isPresented)
        XCTAssertEqual(coordinator.presentationMode, .initial)

        coordinator.skipInitialFlow()

        XCTAssertFalse(coordinator.isPresented)
        XCTAssertTrue(coordinator.hasDismissedInitialFlow)

        let nextLaunchCoordinator = OnboardingCoordinator(defaults: defaults)
        nextLaunchCoordinator.presentIfNeeded()

        XCTAssertFalse(nextLaunchCoordinator.isPresented)
    }

    func testHelpReplayPresentsEvenAfterInitialFlowWasDismissed() throws {
        let defaults = try freshDefaults()
        let coordinator = OnboardingCoordinator(defaults: defaults)

        coordinator.presentIfNeeded()
        coordinator.skipInitialFlow()
        coordinator.showOnboarding()

        XCTAssertTrue(coordinator.isPresented)
        XCTAssertEqual(coordinator.presentationMode, .replay)
        XCTAssertFalse(coordinator.isInitialFlow)
    }

    func testCompletingInitialFlowDismissesFutureAutomaticPresentation() throws {
        let defaults = try freshDefaults()
        let coordinator = OnboardingCoordinator(defaults: defaults)

        coordinator.presentIfNeeded()
        coordinator.completeInitialFlow()

        XCTAssertFalse(coordinator.isPresented)
        XCTAssertTrue(coordinator.hasDismissedInitialFlow)

        coordinator.presentIfNeeded()

        XCTAssertFalse(coordinator.isPresented)
    }

    private func freshDefaults() throws -> UserDefaults {
        let suiteName = "ClaudeGatewayTests.Onboarding.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
