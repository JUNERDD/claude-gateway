import XCTest
@testable import ClaudeGateway

final class LaunchAgentManagerTests: XCTestCase {
    func testParseMacOSProcessElapsedTime() {
        XCTAssertEqual(LaunchAgentManager.parseProcessElapsedTime("00:05"), 5)
        XCTAssertEqual(LaunchAgentManager.parseProcessElapsedTime("01:02:03"), 3_723)
        XCTAssertEqual(LaunchAgentManager.parseProcessElapsedTime("2-03:04:05"), 183_845)
        XCTAssertEqual(LaunchAgentManager.parseProcessElapsedTime("  10:11  "), 611)
    }

    func testParseMacOSProcessElapsedTimeRejectsInvalidValues() {
        XCTAssertNil(LaunchAgentManager.parseProcessElapsedTime(""))
        XCTAssertNil(LaunchAgentManager.parseProcessElapsedTime("abc"))
        XCTAssertNil(LaunchAgentManager.parseProcessElapsedTime("1:2:3:4"))
        XCTAssertNil(LaunchAgentManager.parseProcessElapsedTime("x-01:02:03"))
    }
}
