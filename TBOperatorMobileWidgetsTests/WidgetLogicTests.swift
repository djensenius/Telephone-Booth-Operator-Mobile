//
//  WidgetLogicTests.swift
//  TBOperatorMobileWidgetsTests
//
//  Focused unit tests for the widget extension's pure, widget-local
//  logic: canonical deep-link URL construction, per-section display-state
//  mapping, and stale-transition date calculation that drives timeline
//  reloads.
//
//  These tests assume a source-composed iOS unit-test target that compiles
//  the production widget sources (except `TBOperatorMobileWidgetsBundle.swift`
//  and `CallInProgressLiveActivity.swift`) together with `Shared/Models` and
//  `Shared/Theme`, so the widget types are visible without `@testable import`.
//  All assertions use fixed dates to stay independent of the wall clock.
//

import Foundation
import WidgetKit
import XCTest

// MARK: - Deep links

final class WidgetDeepLinkTests: XCTestCase {
    func testStaticRoutesUseCanonicalHosts() throws {
        XCTAssertEqual(try XCTUnwrap(WidgetDeepLink.dashboard).absoluteString, "tboperator://dashboard")
        XCTAssertEqual(try XCTUnwrap(WidgetDeepLink.stats).absoluteString, "tboperator://stats")
        XCTAssertEqual(try XCTUnwrap(WidgetDeepLink.sessions).absoluteString, "tboperator://sessions")
        XCTAssertEqual(try XCTUnwrap(WidgetDeepLink.system).absoluteString, "tboperator://system")
        XCTAssertEqual(try XCTUnwrap(WidgetDeepLink.thermals).absoluteString, "tboperator://thermals")
    }

    func testReviewRouteCarriesFilterQuery() throws {
        let url = try XCTUnwrap(WidgetDeepLink.messagesReview)
        XCTAssertEqual(url.absoluteString, "tboperator://messages?filter=review")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let filter = components.queryItems?.first { $0.name == "filter" }?.value
        XCTAssertEqual(filter, "review")
    }

    func testSessionDetailUsesPluralHost() throws {
        let url = try XCTUnwrap(WidgetDeepLink.session(id: "abc123"))
        XCTAssertEqual(url.absoluteString, "tboperator://sessions/abc123")
    }

    func testMessageDetailUsesPluralHost() throws {
        let url = try XCTUnwrap(WidgetDeepLink.message(id: "9f8c2b10"))
        XCTAssertEqual(url.absoluteString, "tboperator://messages/9f8c2b10")
    }

    func testDetailIdentifiersArePercentEncoded() throws {
        let url = try XCTUnwrap(WidgetDeepLink.session(id: "id 7"))
        XCTAssertEqual(url.absoluteString, "tboperator://sessions/id%207")
    }

    func testStructuralIdentifiersAreRejected() {
        XCTAssertNil(WidgetDeepLink.message(id: "a/b"))
        XCTAssertNil(WidgetDeepLink.message(id: #"a\b"#))
        XCTAssertNil(WidgetDeepLink.message(id: "a?b"))
        XCTAssertNil(WidgetDeepLink.message(id: "a#b"))
        XCTAssertNil(WidgetDeepLink.message(id: "."))
        XCTAssertNil(WidgetDeepLink.message(id: ".."))
    }

    func testIdentifierIsTrimmedBeforeEncoding() throws {
        let url = try XCTUnwrap(WidgetDeepLink.session(id: "  abc  "))
        XCTAssertEqual(url.absoluteString, "tboperator://sessions/abc")
    }

    func testBlankIdentifierYieldsNil() {
        XCTAssertNil(WidgetDeepLink.session(id: ""))
        XCTAssertNil(WidgetDeepLink.session(id: "   "))
        XCTAssertNil(WidgetDeepLink.message(id: "\n\t "))
    }
}

// MARK: - Family layout sizing

final class WidgetLayoutSizeTests: XCTestCase {
    func testSystemFamiliesMapToProgressivelyLargerLayouts() {
        XCTAssertEqual(WidgetFamily.systemSmall.operatorLayoutSize, .small)
        XCTAssertEqual(WidgetFamily.systemMedium.operatorLayoutSize, .medium)
        XCTAssertEqual(WidgetFamily.systemLarge.operatorLayoutSize, .large)
        #if os(iOS) || os(macOS)
        XCTAssertEqual(WidgetFamily.systemExtraLarge.operatorLayoutSize, .extraLarge)
        #endif
    }

    #if os(iOS)
    func testAccessoryFamiliesShareAccessoryLayout() {
        XCTAssertEqual(WidgetFamily.accessoryInline.operatorLayoutSize, .accessory)
        XCTAssertEqual(WidgetFamily.accessoryCircular.operatorLayoutSize, .accessory)
        XCTAssertEqual(WidgetFamily.accessoryRectangular.operatorLayoutSize, .accessory)
    }
    #endif
}

// MARK: - Display-state mapping

final class WidgetDisplayStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testNoSnapshotState() {
        let state = WidgetSnapshotEntry.noSnapshot(at: now).summaryState
        guard case .noSnapshot = state else {
            XCTFail("expected .noSnapshot, got \(state)")
            return
        }
        XCTAssertNil(state.value)
        XCTAssertNil(state.asOf)
        XCTAssertNil(state.staleAsOf)
        XCTAssertFalse(state.isStale)
        XCTAssertFalse(state.isMissingSection)
    }

    func testMissingSectionState() {
        let state = WidgetSnapshotEntry.emptySections(at: now).summaryState
        guard case .missingSection = state else {
            XCTFail("expected .missingSection, got \(state)")
            return
        }
        XCTAssertTrue(state.isMissingSection)
        XCTAssertNil(state.value)
        XCTAssertFalse(state.isStale)
    }

    func testCurrentSectionState() {
        let entry = WidgetSnapshotEntry.summaryEntry(ageSeconds: 4 * 60, isPlaceholder: false, now: now)
        let state = entry.summaryState
        guard case let .current(summary, asOf) = state else {
            XCTFail("expected .current, got \(state)")
            return
        }
        XCTAssertEqual(summary.pendingMessages, 2)
        XCTAssertEqual(asOf, now.addingTimeInterval(-4 * 60))
        XCTAssertFalse(state.isStale)
        XCTAssertNil(state.staleAsOf)
        XCTAssertNotNil(state.value)
    }

    func testStaleSectionState() {
        let entry = WidgetSnapshotEntry.summaryEntry(ageSeconds: 45 * 60, isPlaceholder: false, now: now)
        let state = entry.summaryState
        guard case .stale = state else {
            XCTFail("expected .stale, got \(state)")
            return
        }
        XCTAssertTrue(state.isStale)
        XCTAssertEqual(state.asOf, now.addingTimeInterval(-45 * 60))
        XCTAssertEqual(state.staleAsOf, now.addingTimeInterval(-45 * 60))
        XCTAssertNotNil(state.value)
    }

    func testStaleThresholdIsInclusive() {
        let atThreshold = WidgetSnapshotEntry.summaryEntry(
            ageSeconds: WidgetSnapshot.cacheStaleInterval,
            isPlaceholder: false,
            now: now
        )
        XCTAssertTrue(atThreshold.summaryState.isStale)

        let justFresh = WidgetSnapshotEntry.summaryEntry(
            ageSeconds: WidgetSnapshot.cacheStaleInterval - 1,
            isPlaceholder: false,
            now: now
        )
        XCTAssertFalse(justFresh.summaryState.isStale)
    }

    func testPlaceholderEntriesNeverStale() {
        let entry = WidgetSnapshotEntry.summaryEntry(
            ageSeconds: 10 * 60 * 60,
            isPlaceholder: true,
            now: now
        )
        let state = entry.summaryState
        guard case .current = state else {
            XCTFail("placeholder entry should be current, got \(state)")
            return
        }
        XCTAssertFalse(state.isStale)
    }

    func testOldestSectionDateTracksIndependentlyStaleData() {
        let fresh = now.addingTimeInterval(-5 * 60)
        let stale = now.addingTimeInterval(-45 * 60)
        let entry = WidgetSnapshotEntry.allSections(
            refreshedAt: fresh,
            sourceUpdatedAt: fresh,
            now: now,
            activityRefreshedAt: stale
        )

        XCTAssertFalse(entry.summaryState.isStale)
        XCTAssertTrue(entry.activityState.isStale)
        XCTAssertEqual(entry.oldestSectionAsOf, stale)
    }
}

// MARK: - Stale-transition scheduling

final class WidgetStaleTransitionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let cache = WidgetSnapshot.cacheStaleInterval
    private let source = WidgetSnapshot.sourceStaleInterval

    func testTransitionsAreSortedFutureDates() {
        let entry = WidgetSnapshotEntry.allSections(refreshedAt: now, sourceUpdatedAt: now, now: now)
        let dates = entry.staleTransitionDates(after: now)
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertTrue(dates.allSatisfy { $0 > now })
        XCTAssertEqual(dates.count, 5)
    }

    func testSourceAgeTransitionIsEarliest() {
        let entry = WidgetSnapshotEntry.allSections(refreshedAt: now, sourceUpdatedAt: now, now: now)
        XCTAssertEqual(entry.staleTransitionDates(after: now).first, now.addingTimeInterval(source))
    }

    func testPastTransitionsAreFiltered() {
        let entry = WidgetSnapshotEntry.allSections(refreshedAt: now, sourceUpdatedAt: now, now: now)
        let cutoff = now.addingTimeInterval(source + 60)
        let dates = entry.staleTransitionDates(after: cutoff)
        XCTAssertEqual(dates.count, 4)
        XCTAssertTrue(dates.allSatisfy { $0 > cutoff })
        XCTAssertEqual(dates.first, now.addingTimeInterval(cache))
    }

    func testEarliestTransitionBeatsFifteenMinuteFallback() throws {
        let entry = WidgetSnapshotEntry.allSections(refreshedAt: now, sourceUpdatedAt: now, now: now)
        let fallback = now.addingTimeInterval(15 * 60)
        let next = try XCTUnwrap(entry.staleTransitionDates(after: now).first)
        XCTAssertLessThan(next, fallback)
    }

    func testProviderUsesInjectedSnapshotAndEarliestTransition() throws {
        let referenceDate = now
        let entry = WidgetSnapshotEntry.allSections(
            refreshedAt: referenceDate,
            sourceUpdatedAt: referenceDate,
            now: referenceDate
        )
        let snapshot = try XCTUnwrap(entry.snapshot)
        let provider = WidgetSnapshotProvider(
            readSnapshot: { snapshot },
            now: { referenceDate }
        )

        let timeline = provider.makeTimeline()

        XCTAssertEqual(timeline.entries.count, 1)
        XCTAssertEqual(timeline.entries.first?.date, referenceDate)
        XCTAssertEqual(timeline.entries.first?.snapshot, snapshot)
        let timelineEntry = try XCTUnwrap(timeline.entries.first)
        XCTAssertEqual(
            provider.nextReloadDate(for: timelineEntry),
            referenceDate.addingTimeInterval(source)
        )
    }

    func testProviderFallsBackToFifteenMinutesWithoutTransitions() throws {
        let referenceDate = now
        let provider = WidgetSnapshotProvider(
            readSnapshot: { nil },
            now: { referenceDate }
        )

        let timeline = provider.makeTimeline()

        let timelineEntry = try XCTUnwrap(timeline.entries.first)
        XCTAssertEqual(
            provider.nextReloadDate(for: timelineEntry),
            referenceDate.addingTimeInterval(15 * 60)
        )
    }

    func testMissingSectionsProduceNoTransitions() {
        let entry = WidgetSnapshotEntry.emptySections(at: now)
        XCTAssertTrue(entry.staleTransitionDates(after: now).isEmpty)
    }

    func testNoSnapshotProducesNoTransitions() {
        let entry = WidgetSnapshotEntry.noSnapshot(at: now)
        XCTAssertTrue(entry.staleTransitionDates(after: now).isEmpty)
    }

    func testPlaceholderProducesNoTransitions() {
        let stale = now.addingTimeInterval(-3600)
        let entry = WidgetSnapshotEntry.allSections(
            refreshedAt: stale,
            sourceUpdatedAt: stale,
            now: now,
            isPlaceholder: true
        )
        XCTAssertTrue(entry.staleTransitionDates(after: now).isEmpty)
    }
}

// MARK: - Fixtures

private extension WidgetSnapshotEntry {
    /// Entry carrying only a `Summary` refreshed `ageSeconds` before `now`.
    static func summaryEntry(ageSeconds: TimeInterval, isPlaceholder: Bool, now: Date) -> WidgetSnapshotEntry {
        let refreshed = now.addingTimeInterval(-ageSeconds)
        let summary = WidgetSnapshot.Summary(
            boothState: .idle,
            boothUpdatedAt: refreshed,
            pendingMessages: 2,
            receivedToday: 5,
            interactionsToday: 3,
            interactionsInProgress: 0,
            wsClients: 1,
            runtimeMode: nil,
            sourceGeneratedAt: refreshed,
            refreshedAt: refreshed
        )
        return WidgetSnapshotEntry(
            date: now,
            snapshot: WidgetSnapshot(summary: summary, writtenAt: refreshed),
            isPlaceholder: isPlaceholder
        )
    }

    /// Entry with every section populated, allowing the health section's
    /// source timestamp to differ from the cache refresh timestamp.
    static func allSections(
        refreshedAt: Date,
        sourceUpdatedAt: Date,
        now: Date,
        latestMessageRefreshedAt: Date? = nil,
        systemHealthRefreshedAt: Date? = nil,
        activityRefreshedAt: Date? = nil,
        isPlaceholder: Bool = false
    ) -> WidgetSnapshotEntry {
        let messageRefreshedAt = latestMessageRefreshedAt ?? refreshedAt
        let healthRefreshedAt = systemHealthRefreshedAt ?? refreshedAt
        let overviewRefreshedAt = activityRefreshedAt ?? refreshedAt
        let snapshot = WidgetSnapshot(
            summary: WidgetSnapshot.Summary(
                boothState: .idle,
                boothUpdatedAt: refreshedAt,
                pendingMessages: 1,
                receivedToday: 1,
                interactionsToday: 1,
                interactionsInProgress: 0,
                wsClients: 0,
                runtimeMode: nil,
                sourceGeneratedAt: refreshedAt,
                refreshedAt: refreshedAt
            ),
            latestMessage: WidgetSnapshot.LatestMessage(
                id: "m1",
                status: .received,
                occurredAt: messageRefreshedAt,
                refreshedAt: messageRefreshedAt
            ),
            systemHealth: WidgetSnapshot.SystemHealth(
                boothId: "booth",
                severity: .nominal,
                cpuTemperatureCelsius: 40,
                memoryUsedRatio: 0.3,
                routerTemperatureCelsius: 40,
                tailscaleConnected: true,
                sourceUpdatedAt: sourceUpdatedAt,
                refreshedAt: healthRefreshedAt
            ),
            activity: WidgetSnapshot.Activity(
                pickups: 1,
                messages: 1,
                buckets: [],
                rangeStart: overviewRefreshedAt.addingTimeInterval(-3600),
                rangeEnd: overviewRefreshedAt,
                refreshedAt: overviewRefreshedAt
            ),
            writtenAt: refreshedAt
        )
        return WidgetSnapshotEntry(date: now, snapshot: snapshot, isPlaceholder: isPlaceholder)
    }
}
