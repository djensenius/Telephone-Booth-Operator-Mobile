//
//  TBOperatorMobileTVTests.swift
//

import XCTest
@testable import TBOperatorMobileTV

final class TBOperatorMobileTVTests: XCTestCase {
    func testBoothWallUsesReadinessCopyForIdleState() {
        XCTAssertEqual(BoothState.idle.tvHeadline, "Ready for the next call")
        XCTAssertEqual(BoothState.idle.tvDisplayName, "Idle")
    }

    func testBoothWallUsesActionCopyForActiveState() {
        XCTAssertEqual(BoothState.recording.tvHeadline, "Recording a message")
        XCTAssertEqual(BoothState.recording.tvDisplayName, "Recording")
    }
}
