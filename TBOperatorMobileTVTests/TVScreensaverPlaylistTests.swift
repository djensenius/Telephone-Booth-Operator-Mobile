//
//  TVScreensaverPlaylistTests.swift
//  TBOperatorMobileTVTests
//
//  Covers the screensaver's "only show status while something is happening"
//  contract: idle/unknown never produce a status spotlight, every active
//  state does, and zero-value stats are omitted from the playlist.
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

    func testBuildOmitsAllZeroSummaryStats() {
        let items = TVScreensaverPlaylist.build(status: nil, stats: makeStats(), overview: nil)
        XCTAssertTrue(items.isEmpty)
    }

    func testBuildIncludesAllNonZeroSummaryStats() {
        let stats = makeStats(callsToday: 1, inProgress: 2, pending: 3, receivedToday: 4)
        let items = TVScreensaverPlaylist.build(status: nil, stats: stats, overview: nil)
        XCTAssertEqual(
            Set(items.map(\.id)),
            Set(["calls-today", "in-progress", "pending", "received"])
        )
    }

    func testBuildOmitsAllZeroOverviewStats() {
        let overview = makeOverview(
            totalInteractions: 0,
            perDay: [.init(date: "2026-08-19", total: 0, completed: 0)]
        )
        let items = TVScreensaverPlaylist.build(status: nil, stats: nil, overview: overview)
        XCTAssertTrue(items.isEmpty)
    }

    func testBuildIncludesAllNonZeroOverviewStats() {
        let overview = makeOverview(
            totalInteractions: 4,
            messagesLeft: 2,
            wrongNumbers: 3,
            totalPlaybacks: 2,
            perDay: [
                .init(date: "2026-08-18", total: 0, completed: 0),
                .init(date: "2026-08-19", total: 1, completed: 1)
            ]
        )
        let items = TVScreensaverPlaylist.build(status: nil, stats: nil, overview: overview)
        XCTAssertEqual(
            Set(items.map(\.id)),
            Set(["pickups", "messages-left", "wrong-numbers", "playbacks", "calls-chart"])
        )
        guard case let .callsChart(days)? = items.first(where: { $0.id == "calls-chart" })?.kind else {
            return XCTFail("expected a calls chart")
        }
        XCTAssertEqual(days, overview.interactionMetrics.perDay)
    }

    // MARK: - Helpers

    private func makeStats(
        callsToday: Int = 0,
        inProgress: Int = 0,
        pending: Int = 0,
        receivedToday: Int = 0
    ) -> StatsSummary {
        let base = StatsSummary.placeholder
        return StatsSummary(
            booth: base.booth,
            messages: .init(
                pending: pending,
                awaitingModeration: pending,
                receivedToday: receivedToday,
                latestId: nil
            ),
            calls: .init(today: callsToday, inProgress: inProgress),
            interactions: .init(today: callsToday, inProgress: inProgress),
            realtime: base.realtime,
            generatedAt: base.generatedAt
        )
    }

    private func makeOverview(
        totalInteractions: Int = 0,
        messagesLeft: Int = 0,
        wrongNumbers: Int = 0,
        totalPlaybacks: Int = 0,
        perDay: [StatsOverview.PerDay] = []
    ) -> StatsOverview {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return StatsOverview(
            window: .last7d,
            rangeStart: date,
            rangeEnd: date,
            generatedAt: date,
            timezone: "UTC",
            calls: .init(
                total: totalInteractions,
                completed: messagesLeft,
                inProgress: 0,
                averageDurationMs: nil,
                longestDurationMs: nil,
                outcomes: ["recording_completed": messagesLeft],
                perDay: perDay
            ),
            interactions: .init(
                total: totalInteractions,
                inProgressNow: 0,
                noSelection: 0,
                messagesLeft: messagesLeft,
                averageDurationMs: nil,
                longestDurationMs: nil,
                outcomes: ["recording_completed": messagesLeft],
                perDay: perDay
            ),
            actions: .init(
                digitsDialed: ["1": messagesLeft, "3": wrongNumbers],
                leaveMessageSelections: messagesLeft,
                listenMessageSelections: 0,
                instructionSelections: 0,
                wrongNumberAttempts: wrongNumbers,
                messagePlaybackStarts: totalPlaybacks,
                instructionPlaybackStarts: 0
            ),
            messages: .init(total: 0, byStatus: [:], averageDurationMs: nil),
            playback: .init(totalPlaybacks: totalPlaybacks),
            pickupsHangups: .init(pickups: totalInteractions, hangups: 0, digitsDialed: [:]),
            uploads: .init(succeeded: 0, failed: 0, failureRate: nil),
            topQuestions: [],
            hourly: [],
            busiest: .init(hour: nil, dayOfWeek: nil),
            lastActivityAt: nil,
            boothBreakdown: []
        )
    }
}
