import XCTest
@testable import ClaudeGateway

@MainActor
final class AppTerminationControllerTests: XCTestCase {
    override func tearDown() {
        AppLifecycleState.isTerminating = false
        AppTerminationController.onPrepareTermination = nil
        super.tearDown()
    }

    func testPrepareForTerminationMarksLifecycleAsTerminating() {
        AppLifecycleState.isTerminating = false

        AppTerminationController.prepareForTermination()

        XCTAssertTrue(AppLifecycleState.isTerminating)
    }

    func testPrepareForTerminationInvokesPrepareCallback() {
        var callbackInvoked = false
        AppTerminationController.onPrepareTermination = {
            callbackInvoked = true
        }

        AppTerminationController.prepareForTermination()

        XCTAssertTrue(callbackInvoked)
    }
}
