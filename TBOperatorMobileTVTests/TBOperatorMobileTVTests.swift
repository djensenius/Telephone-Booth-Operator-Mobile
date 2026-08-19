//
//  TBOperatorMobileTVTests.swift
//

import XCTest
@testable import TBOperatorMobileTV

final class TBOperatorMobileTVTests: XCTestCase {
    func testBoothWallUsesNeutralCopyBeforeFirstStatus() {
        let state: BoothState? = nil
        XCTAssertEqual(state.tvHeadline, "Waiting for booth status")
        XCTAssertEqual(state.tvSymbol, "wave.3.right.circle")
    }

    func testBoothWallUsesReadinessCopyForIdleState() {
        XCTAssertEqual(BoothState.idle.tvHeadline, "Ready for the next call")
        XCTAssertEqual(BoothState.idle.tvDisplayName, "Idle")
    }

    func testBoothWallUsesActionCopyForActiveState() {
        XCTAssertEqual(BoothState.recording.tvHeadline, "Recording a message")
        XCTAssertEqual(BoothState.recording.tvDisplayName, "Recording")
    }
}
