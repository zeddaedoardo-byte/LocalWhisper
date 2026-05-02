import XCTest
@testable import LocalWhisperFlow

final class PushToTalkStateMachineTests: XCTestCase {
    func testPressEmitsPressedOnce() {
        var stateMachine = PushToTalkStateMachine()

        XCTAssertEqual(stateMachine.update(controlIsPressed: true), .pressed)
        XCTAssertNil(stateMachine.update(controlIsPressed: true))
    }

    func testReleaseEmitsReleasedAfterPress() {
        var stateMachine = PushToTalkStateMachine()

        _ = stateMachine.update(controlIsPressed: true)

        XCTAssertEqual(stateMachine.update(controlIsPressed: false), .released)
        XCTAssertNil(stateMachine.update(controlIsPressed: false))
    }

    func testResetReturnsToNotPressed() {
        var stateMachine = PushToTalkStateMachine()

        _ = stateMachine.update(controlIsPressed: true)
        stateMachine.reset()

        XCTAssertEqual(stateMachine.update(controlIsPressed: true), .pressed)
    }
}
