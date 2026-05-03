import XCTest
@testable import LocalWhisper

final class PushToTalkStateMachineTests: XCTestCase {
    func testPressEmitsPressedOnce() {
        var stateMachine = PushToTalkStateMachine()

        XCTAssertEqual(stateMachine.update(triggerIsPressed: true), .pressed)
        XCTAssertNil(stateMachine.update(triggerIsPressed: true))
    }

    func testReleaseEmitsReleasedAfterPress() {
        var stateMachine = PushToTalkStateMachine()

        _ = stateMachine.update(triggerIsPressed: true)

        XCTAssertEqual(stateMachine.update(triggerIsPressed: false), .released)
        XCTAssertNil(stateMachine.update(triggerIsPressed: false))
    }

    func testResetReturnsToNotPressed() {
        var stateMachine = PushToTalkStateMachine()

        _ = stateMachine.update(triggerIsPressed: true)
        stateMachine.reset()

        XCTAssertEqual(stateMachine.update(triggerIsPressed: true), .pressed)
    }
}
