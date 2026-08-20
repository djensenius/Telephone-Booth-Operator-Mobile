//
//  WidgetSnapshotTests.swift
//  TBOperatorMobileTests
//

import XCTest
@testable import TBOperatorMobile

final class WidgetSnapshotModelTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)

    func testLegacySnapshotDecodesIntoSummarySection() throws {
        let data = Data(
            """
            {
              "boothState": "recording",
              "boothUpdatedAt": "2033-05-18T03:33:20Z",
              "pendingMessages": 3,
              "receivedToday": 8,
              "callsToday": 5,
              "callsInProgress": 1,
              "wsClients": 2,
              "generatedAt": "2033-05-18T03:33:20Z"
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.summary?.boothState, .recording)
        XCTAssertEqual(snapshot.summary?.pendingMessages, 3)
        XCTAssertEqual(snapshot.summary?.interactionsToday, 5)
        XCTAssertNil(snapshot.latestMessage)
        XCTAssertNil(snapshot.systemHealth)
        XCTAssertNil(snapshot.activity)
    }

    func testStatsSummaryUsesCombinedReviewCount() {
        let stats = StatsSummary(
            booth: StatsSummary.placeholder.booth,
            messages: .init(
                pending: 2,
                awaitingModeration: 5,
                receivedToday: 7,
                latestId: nil
            ),
            calls: .init(today: 4, inProgress: 0),
            interactions: .init(today: 9, inProgress: 1),
            realtime: .init(wsClients: 1),
            generatedAt: referenceDate
        )

        let snapshot = WidgetSnapshot(stats: stats)

        XCTAssertEqual(snapshot.pendingMessages, 5)
        XCTAssertEqual(snapshot.interactionsToday, 9)
    }

    func testEncodedLatestMessageContainsNoMessageBodyData() throws {
        let message = try XCTUnwrap(DemoData.messages.first)
        let snapshot = WidgetSnapshot(
            latestMessage: .init(message: message, refreshedAt: referenceDate),
            writtenAt: referenceDate
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let encoded = try XCTUnwrap(
            String(data: encoder.encode(snapshot), encoding: .utf8)
        )

        XCTAssertFalse(encoded.contains("latestTranscription"))
        XCTAssertFalse(encoded.contains("translation"))
        XCTAssertFalse(encoded.contains("reasonSummary"))
        XCTAssertFalse(encoded.contains("\"notes\""))
        XCTAssertFalse(encoded.contains("\"audio\""))
        XCTAssertFalse(encoded.contains("url"))
    }

    func testStalenessBoundaryIsInclusive() {
        let snapshot = WidgetSnapshot(writtenAt: referenceDate)
        XCTAssertFalse(
            snapshot.isStale(
                sectionDate: referenceDate,
                at: referenceDate.addingTimeInterval(WidgetSnapshot.cacheStaleInterval - 1)
            )
        )
        XCTAssertTrue(
            snapshot.isStale(
                sectionDate: referenceDate,
                at: referenceDate.addingTimeInterval(WidgetSnapshot.cacheStaleInterval)
            )
        )
    }

    func testSystemHealthElevatesStaleTelemetry() {
        let envelope = BoothSystemSnapshotEnvelope(
            boothId: "booth-a",
            snapshot: BoothSystemSnapshot(
                cpu: .init(physicalCores: 4, loadAvg1m: 0.5),
                temperatureCelsius: 45,
                memory: .init(totalBytes: 1_000, usedBytes: 400),
                tailscale: .init(connected: true)
            ),
            receivedAt: referenceDate
        )
        let health = WidgetSnapshot.SystemHealth(
            envelope: envelope,
            components: [],
            refreshedAt: referenceDate
        )

        XCTAssertEqual(health.severity, .nominal)
        XCTAssertEqual(
            health.effectiveSeverity(
                at: referenceDate.addingTimeInterval(WidgetSnapshot.sourceStaleInterval)
            ),
            .warning
        )
    }

    func testSystemHealthTreatsDisconnectedTailscaleAsCritical() {
        let envelope = BoothSystemSnapshotEnvelope(
            boothId: "booth-a",
            snapshot: BoothSystemSnapshot(tailscale: .init(connected: false)),
            receivedAt: referenceDate
        )

        let health = WidgetSnapshot.SystemHealth(
            envelope: envelope,
            components: [],
            refreshedAt: referenceDate
        )

        XCTAssertEqual(health.severity, .critical)
    }

    func testActivityUsesInteractionFallbackAndCapsBuckets() {
        let overview = DemoData.statsOverview(window: .last24h)
        let activity = WidgetSnapshot.Activity(
            overview: overview,
            refreshedAt: referenceDate
        )

        XCTAssertEqual(activity.pickups, overview.interactionMetrics.total)
        XCTAssertEqual(activity.messages, overview.messages.allRecordingsCount)
        XCTAssertLessThanOrEqual(activity.buckets.count, 24)
        XCTAssertEqual(
            activity.buckets.map(\.pickups),
            Array(overview.hourly.prefix(24)).map(\.interactionCount)
        )
    }

    func testFileStoreRoundTripAndClear() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotFileStore(directoryURL: directory)

        XCTAssertTrue(try store.write(.placeholder))
        XCTAssertEqual(try store.read(), .placeholder)
        XCTAssertFalse(try store.write(.placeholder))
        XCTAssertTrue(try store.clear())
        XCTAssertNil(try store.read())
        XCTAssertFalse(try store.clear())
    }

    func testFileStoreRepairsCorruptSnapshotOnNextWrite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotFileStore(directoryURL: directory)
        try Data("not-json".utf8).write(to: store.snapshotURL)

        XCTAssertThrowsError(try store.read())
        XCTAssertTrue(try store.write(.placeholder))
        XCTAssertEqual(try store.read(), .placeholder)
    }
}

final class WidgetRefreshCoordinatorTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)

    func testStatsUpdatePreservesOtherSections() async throws {
        let harness = try makeCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        _ = try harness.store.write(.placeholder)
        let stats = StatsSummary(
            booth: StatsSummary.placeholder.booth,
            messages: StatsSummary.placeholder.messages,
            calls: .init(today: 1, inProgress: 0),
            interactions: .init(today: 12, inProgress: 2),
            realtime: StatsSummary.placeholder.realtime,
            generatedAt: referenceDate
        )

        let result = await harness.coordinator.apply(stats: stats)
        let written = try XCTUnwrap(harness.store.read())

        XCTAssertEqual(result, .newData)
        XCTAssertEqual(written.interactionsToday, 12)
        XCTAssertEqual(written.latestMessage, WidgetSnapshot.placeholder.latestMessage)
        XCTAssertEqual(written.systemHealth, WidgetSnapshot.placeholder.systemHealth)
        XCTAssertEqual(written.activity, WidgetSnapshot.placeholder.activity)
    }

    func testFullRefreshClearsSuccessfulEmptyMessageAndPreservesFailedSystem() async throws {
        let harness = try makeCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        _ = try harness.store.write(.placeholder)
        let client = FakeWidgetDataClient(
            messages: MessageList(items: []),
            failingEndpoints: [.system, .components]
        )

        let result = await harness.coordinator.refresh(using: client)
        let written = try XCTUnwrap(harness.store.read())

        XCTAssertEqual(result, .newData)
        XCTAssertNil(written.latestMessage)
        XCTAssertEqual(written.systemHealth, WidgetSnapshot.placeholder.systemHealth)
        XCTAssertNotNil(written.summary)
        XCTAssertNotNil(written.activity)
    }

    func testFullRefreshPreservesSystemHealthWhenComponentsFail() async throws {
        let harness = try makeCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let existingHealth = WidgetSnapshot.SystemHealth(
            boothId: "booth-a",
            severity: .warning,
            cpuTemperatureCelsius: 42,
            memoryUsedRatio: 0.4,
            routerTemperatureCelsius: 63,
            tailscaleConnected: true,
            sourceUpdatedAt: referenceDate.addingTimeInterval(-60),
            refreshedAt: referenceDate.addingTimeInterval(-60)
        )
        _ = try harness.store.write(
            WidgetSnapshot(
                systemHealth: existingHealth,
                writtenAt: referenceDate.addingTimeInterval(-60)
            )
        )
        let client = FakeWidgetDataClient(
            system: BoothSystemSnapshotEnvelope(
                boothId: "booth-a",
                snapshot: BoothSystemSnapshot(
                    cpu: .init(physicalCores: 4, loadAvg1m: 0.5),
                    temperatureCelsius: 48,
                    memory: .init(totalBytes: 1_000, usedBytes: 500),
                    tailscale: .init(connected: true)
                ),
                receivedAt: referenceDate
            ),
            failingEndpoints: [.components]
        )

        let result = await harness.coordinator.refresh(using: client)
        let written = try XCTUnwrap(harness.store.read())

        XCTAssertEqual(result, .newData)
        XCTAssertEqual(written.systemHealth?.cpuTemperatureCelsius, 42)
        XCTAssertEqual(written.systemHealth?.memoryUsedRatio, 0.4)
        XCTAssertEqual(written.systemHealth?.routerTemperatureCelsius, 63)
        XCTAssertEqual(
            written.systemHealth?.sourceUpdatedAt,
            referenceDate.addingTimeInterval(-60)
        )
    }

    func testClearRemovesPersistedSnapshot() async throws {
        let harness = try makeCoordinator()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        _ = try harness.store.write(.placeholder)

        let cleared = await harness.coordinator.clear()
        XCTAssertTrue(cleared)
        XCTAssertNil(try harness.store.read())
    }

    private func makeCoordinator() throws -> CoordinatorHarness {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let store = WidgetSnapshotFileStore(directoryURL: directory)
        let referenceDate = self.referenceDate
        let coordinator = WidgetRefreshCoordinator(
            readSnapshot: { try? store.read() },
            writeSnapshot: { snapshot in
                do {
                    _ = try store.write(snapshot)
                    return true
                } catch {
                    return false
                }
            },
            clearSnapshot: {
                do {
                    _ = try store.clear()
                    return true
                } catch {
                    return false
                }
            },
            now: { referenceDate }
        )
        return CoordinatorHarness(
            coordinator: coordinator,
            store: store,
            directory: directory
        )
    }
}

private struct CoordinatorHarness {
    let coordinator: WidgetRefreshCoordinator
    let store: WidgetSnapshotFileStore
    let directory: URL
}

private struct FakeWidgetDataClient: WidgetDataFetching {
    enum Endpoint: Sendable, Hashable {
        case summary
        case messages
        case system
        case components
        case activity
    }

    enum Failure: Error, Sendable {
        case requested
    }

    var summary = DemoData.statsSummary
    var messages = MessageList(items: Array(DemoData.messages.prefix(1)))
    var system: BoothSystemSnapshotEnvelope? = DemoData.systemEnvelope
    var components = DemoData.systemComponentSources
    var activity = DemoData.statsOverview(window: .last24h)
    var failingEndpoints: Set<Endpoint> = []

    func fetchStatsSummary(timeZone: TimeZone) async throws -> StatsSummary {
        try result(summary, endpoint: .summary)
    }

    func fetchStatsOverview(window: StatsWindow) async throws -> StatsOverview {
        try result(activity, endpoint: .activity)
    }

    func fetchMessages(
        status: MessageStatus?,
        since: Date?,
        limit: Int
    ) async throws -> MessageList {
        try result(messages, endpoint: .messages)
    }

    func fetchCurrentSystemEnvelope(
        boothId: String?
    ) async throws -> BoothSystemSnapshotEnvelope? {
        try result(system, endpoint: .system)
    }

    func fetchCurrentSystemComponents() async throws -> [SystemComponentCurrentEnvelope] {
        try result(components, endpoint: .components)
    }

    private func result<Value>(
        _ value: Value,
        endpoint: Endpoint
    ) throws -> Value {
        if failingEndpoints.contains(endpoint) { throw Failure.requested }
        return value
    }
}
