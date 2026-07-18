//
//  TVScreensaverPlaylistTests.swift
//  TBOperatorMobileTVTests
//
//  Covers the screensaver's "only show status while something is happening"
//  contract: idle/unknown never produce a status spotlight, every active
//  state does, and zero-value in-progress metrics are omitted from the
//  playlist.
//

import XCTest
@testable import TBOperatorMobileTV

final class TVScreensaverPlaylistTests: XCTestCase {
    private let activeStates = BoothState.knownCases.filter { $0 != .idle }

    // MARK: - isHappening

    func testIdleAndUnknownAreNotHappening() {
        XCTAssertFalse(TVScreensaverPlaylist.isHappening(.idle))
        XCTAssertFalse(TVScreensaverPlaylist.isHappening(.unknown("mystery")))
    }

    func testEveryActiveStateIsHappening() {
        for state in activeStates {
            XCTAssertTrue(
                TVScreensaverPlaylist.isHappening(state),
                "\(state.rawValue) should count as happening"
            )
        }
    }

    // MARK: - statusSpotlight

    func testStatusSpotlightIsNilForIdleAndUnknown() {
        XCTAssertNil(TVScreensaverPlaylist.statusSpotlight(for: .idle))
        XCTAssertNil(TVScreensaverPlaylist.statusSpotlight(for: .unknown("mystery")))
    }

    func testStatusSpotlightExistsForEveryActiveState() {
        for state in activeStates {
            guard let spotlight = TVScreensaverPlaylist.statusSpotlight(for: state) else {
                XCTFail("\(state.rawValue) should yield a status spotlight")
                continue
            }
            guard case .status = spotlight.kind else {
                XCTFail("\(state.rawValue) spotlight should be a .status card")
                continue
            }
            XCTAssertEqual(spotlight.id, "status")
        }
    }

    func testErrorStatusDoesNotClaimAnActiveCall() {
        guard case let .status(_, detail)? = TVScreensaverPlaylist.statusSpotlight(for: .error)?.kind else {
            return XCTFail("error should yield a status spotlight")
        }
        XCTAssertNotEqual(detail, "Call in progress", "an error is not an active call")
    }

    // MARK: - build()

    func testBuildOmitsStatusCardWhenIdle() {
        let idle = BoothStatus(state: .idle, updatedAt: Date())
        let items = TVScreensaverPlaylist.build(status: idle, stats: nil, overview: nil)
        XCTAssertFalse(items.contains { $0.id == "status" })
    }

    func testBuildIncludesStatusCardWhenActive() {
        let recording = BoothStatus(state: .recording, updatedAt: Date())
        let items = TVScreensaverPlaylist.build(status: recording, stats: nil, overview: nil)
        XCTAssertTrue(items.contains { $0.id == "status" })
    }

    func testBuildOmitsInProgressCardWhenZero() {
        let stats = makeStats(inProgress: 0)
        let items = TVScreensaverPlaylist.build(status: nil, stats: stats, overview: nil)
        XCTAssertFalse(items.contains { $0.id == "in-progress" })
    }

    func testBuildIncludesInProgressCardWhenNonZero() {
        let stats = makeStats(inProgress: 2)
        let items = TVScreensaverPlaylist.build(status: nil, stats: stats, overview: nil)
        XCTAssertTrue(items.contains { $0.id == "in-progress" })
    }

    // MARK: - Helpers

    private func makeStats(inProgress: Int) -> StatsSummary {
        let base = StatsSummary.placeholder
        return StatsSummary(
            booth: base.booth,
            messages: base.messages,
            calls: .init(today: base.calls.today, inProgress: inProgress),
            realtime: base.realtime,
            generatedAt: base.generatedAt
        )
    }
}
