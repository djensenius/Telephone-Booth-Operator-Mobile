//
//  StatsOverviewTests.swift
//
//  Decode round-trips for /v1/stats/overview, ordered-display helpers,
//  and forward-compatible enum tolerance.
//

import XCTest
@testable import TBOperatorMobile

final class StatsOverviewTests: XCTestCase {

    // MARK: - StatsWindow

    func testStatsWindowRoundTripsKnownAndUnknown() throws {
        for known in StatsWindow.knownCases {
            let encoded = try JSONEncoder().encode(known)
            let decoded = try JSONDecoder().decode(StatsWindow.self, from: encoded)
            XCTAssertEqual(decoded, known)
        }
        let mystery = StatsWindow(rawValue: "future_window")
        XCTAssertEqual(mystery, .unknown("future_window"))
        let data = try JSONEncoder().encode(mystery)
        XCTAssertEqual(try JSONDecoder().decode(StatsWindow.self, from: data), mystery)
        XCTAssertEqual(mystery.rawValue, "future_window")
    }

    // MARK: - Full payload

    func testDecodesFullPayload() throws {
        let json = #"""
        {
          "window": "7d",
          "rangeStart": "2026-05-19T00:00:00Z", "rangeEnd": "2026-05-26T00:00:00Z",
          "generatedAt": "2026-05-26T00:00:00Z", "timezone": "UTC",
          "calls": {
            "total": 12, "completed": 9, "inProgress": 1,
            "averageDurationMs": 4321.5, "longestDurationMs": 9000,
            "outcomes": { "recording_completed": 9, "hung_up_before_dial": 2, "wild_new_outcome": 1 },
            "perDay": [{ "date": "2026-05-25", "total": 5, "completed": 4 },
              { "date": "2026-05-26", "total": 7, "completed": 5 }]
          },
          "messages": { "total": 6, "approved": 6, "allRecordings": 9,
            "byStatus": { "approved": 6, "pending": 2, "rejected": 1 },
            "averageDurationMs": 8500 },
          "playback": { "totalPlaybacks": 17 },
          "pickupsHangups": { "pickups": 12, "hangups": 11, "digitsDialed": { "1": 3, "5": 5 } },
          "uploads": { "succeeded": 9, "failed": 1, "failureRate": 0.1 },
          "topQuestions": [{
            "questionId": "11111111-1111-4111-8111-111111111111",
            "prompt": "What did the city sound like today?",
            "messageCount": 5, "lastUsedAt": "2026-05-26T00:00:00Z", "retiredAt": null
          }],
          "hourly": [{ "hour": 0, "calls": 0, "messages": 0 },
            { "hour": 10, "calls": 3, "messages": 2 }],
          "busiest": { "hour": 10, "dayOfWeek": 1 },
          "lastActivityAt": "2026-05-26T00:00:00Z",
          "boothBreakdown": [
            { "boothId": "booth-1", "calls": 8, "messages": null, "lastSeenAt": "2026-05-26T00:00:00Z" },
            { "boothId": "booth-2", "calls": 4, "messages": null, "lastSeenAt": "2026-05-25T00:00:00Z" }
          ]
        }
        """#
        let overview = try OperatorJSON.decoder.decode(StatsOverview.self, from: Data(json.utf8))
        XCTAssertEqual(overview.window, .last7d)
        XCTAssertEqual(overview.timezone, "UTC")
        XCTAssertEqual(overview.calls.total, 12)
        XCTAssertEqual(overview.calls.completed, 9)
        XCTAssertEqual(overview.calls.outcomes["wild_new_outcome"], 1)
        XCTAssertEqual(overview.completionRate, 9.0 / 12.0)
        XCTAssertEqual(overview.messages.byStatus["approved"], 6)
        XCTAssertEqual(overview.messages.approvedCount, 6)
        XCTAssertEqual(overview.messages.allRecordingsCount, 9)
        XCTAssertEqual(overview.playback.totalPlaybacks, 17)
        XCTAssertEqual(overview.pickupsHangups.digitsDialed["5"], 5)
        XCTAssertEqual(overview.uploads.failureRate, 0.1)
        XCTAssertEqual(overview.topQuestions.first?.prompt, "What did the city sound like today?")
        XCTAssertEqual(overview.busiest.hour, 10)
        XCTAssertEqual(overview.boothBreakdown.count, 2)
        XCTAssertNil(overview.boothBreakdown.first?.messages)
    }

    // MARK: - Empty payload

    func testDecodesEmptyPayload() throws {
        let json = #"""
        {
          "window": "24h",
          "rangeStart": null,
          "rangeEnd": "2026-05-26T00:00:00Z",
          "generatedAt": "2026-05-26T00:00:00Z",
          "timezone": "UTC",
          "calls": {
            "total": 0,
            "completed": 0,
            "inProgress": 0,
            "averageDurationMs": null,
            "longestDurationMs": null,
            "outcomes": {},
            "perDay": []
          },
          "messages": { "total": 0, "byStatus": {}, "averageDurationMs": null },
          "playback": { "totalPlaybacks": 0 },
          "pickupsHangups": { "pickups": 0, "hangups": 0, "digitsDialed": {} },
          "uploads": { "succeeded": 0, "failed": 0, "failureRate": null },
          "topQuestions": [],
          "hourly": [],
          "busiest": { "hour": null, "dayOfWeek": null },
          "lastActivityAt": null,
          "boothBreakdown": []
        }
        """#
        let overview = try OperatorJSON.decoder.decode(StatsOverview.self, from: Data(json.utf8))
        XCTAssertNil(overview.completionRate)
        XCTAssertNil(overview.rangeStart)
        XCTAssertNil(overview.uploads.failureRate)
        XCTAssertNil(overview.busiest.hour)
        XCTAssertNil(overview.lastActivityAt)
        XCTAssertEqual(overview.calls.outcomes, [:])
        XCTAssertEqual(overview.pickupsHangups.digitsDialed, [:])
    }

    // MARK: - Display helpers

    func testOutcomesInDisplayOrderPutsCanonicalFirstAndUnknownsLast() {
        let calls = StatsOverview.Calls(
            total: 4,
            completed: 2,
            inProgress: 0,
            averageDurationMs: nil,
            longestDurationMs: nil,
            outcomes: [
                "aborted": 1,
                "wild_z_outcome": 2,
                "recording_completed": 2,
                "wild_a_outcome": 1
            ],
            perDay: []
        )
        let overview = makeOverview(calls: calls)
        let ordered = overview.outcomesInDisplayOrder()
        XCTAssertEqual(ordered.map(\.key), [
            "recording_completed",
            "aborted",
            "wild_a_outcome", // sorted asc after canonical
            "wild_z_outcome"
        ])
        XCTAssertEqual(ordered.first?.count, 2)
    }

    func testStatusesInDisplayOrderUsesWorkflowOrder() {
        let messages = StatsOverview.Messages(
            total: 5,
            byStatus: ["approved": 2, "uploading": 1, "pending": 1, "rejected": 1],
            averageDurationMs: nil
        )
        let overview = makeOverview(messages: messages)
        let ordered = overview.statusesInDisplayOrder()
        XCTAssertEqual(ordered.map(\.key), ["uploading", "pending", "approved", "rejected"])
    }

    func testMessageCountsFallBackForRollingDeployment() {
        let messages = StatsOverview.Messages(
            total: 5,
            byStatus: ["approved": 5],
            averageDurationMs: nil
        )
        XCTAssertEqual(messages.approvedCount, 5)
        XCTAssertEqual(messages.allRecordingsCount, 5)
    }

    func testApprovedCountPrefersStatusForLegacyResponse() {
        let messages = StatsOverview.Messages(
            total: 9,
            byStatus: ["approved": 6, "pending": 2, "rejected": 1],
            averageDurationMs: nil
        )

        XCTAssertEqual(messages.approvedCount, 6)
        XCTAssertEqual(messages.allRecordingsCount, 9)
    }

    func testInstallationScopeQueryValues() {
        XCTAssertNil(InstallationScope.current.queryValue)
        XCTAssertEqual(InstallationScope.all.queryValue, "all")
        XCTAssertEqual(
            InstallationScope.installation("era-1").queryValue,
            "era-1"
        )
    }

    func testInstallationDecodesWithoutLanguageDuringDeployment() throws {
        let installation = try OperatorJSON.decoder.decode(
            Installation.self,
            from: Data(#"""
            {
              "id":"00000000-0000-4000-8000-000000000001",
              "name":"Opening",
              "notes":null,
              "location":null,
              "startedAt":"2026-08-14T12:00:00Z",
              "endedAt":null,
              "endedById":null,
              "summary":null,
              "createdAt":"2026-08-14T12:00:00Z",
              "isActive":true
            }
            """#.utf8)
        )
        XCTAssertNil(installation.defaultTranscriptionLanguage)
        XCTAssertTrue(installation.isActive)
    }

    func testDigitsDialedZeroFilledAlwaysHas10EntriesInOrder() {
        let hangups = StatsOverview.PickupsHangups(
            pickups: 5,
            hangups: 4,
            digitsDialed: ["1": 3, "9": 1]
        )
        let overview = makeOverview(pickupsHangups: hangups)
        let digits = overview.pickupsHangups.digitsDialedZeroFilled()
        XCTAssertEqual(digits.count, 10)
        XCTAssertEqual(digits.map(\.digit), ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"])
        XCTAssertEqual(digits[1].count, 3)
        XCTAssertEqual(digits[9].count, 1)
        XCTAssertEqual(digits[0].count, 0)
    }

    @MainActor
    func testFetchStatsOverviewRecoversDigitsAndKeepsOverviewWhenRecoveryFails() async throws {
        let appConfig = AppConfig.shared
        let previousDemoMode = appConfig.isDemoMode
        appConfig.isDemoMode = false
        defer { appConfig.isDemoMode = previousDemoMode }

        let auth = AuthManager.shared
        auth.signOut()
        XCTAssertTrue(auth.storeTokens(
            OIDCTokens(
                accessToken: "stats-access-\(UUID().uuidString)",
                refreshToken: "stats-refresh-\(UUID().uuidString)",
                idToken: nil,
                expiresIn: 3_600,
                tokenType: "Bearer"
            )
        ))
        defer { auth.signOut() }

        StatsDigitRecoveryURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StatsDigitRecoveryURLProtocol.self]
        let client = OperatorClient(
            config: appConfig,
            auth: auth,
            session: URLSession(configuration: configuration)
        )

        let overview = try await client.fetchStatsOverview(
            selection: .window(.last7d),
            installationScope: .installation("installation-1")
        )

        XCTAssertEqual(overview.pickupsHangups.digitsDialed["0"], 1)
        XCTAssertEqual(overview.pickupsHangups.digitsDialed["1"], 2)
        XCTAssertEqual(overview.pickupsHangups.digitsDialed["5"], 2)
        XCTAssertEqual(overview.pickupsHangups.digitsDialed["9"], 0)

        let requests = StatsDigitRecoveryURLProtocol.capturedURLs()
        XCTAssertEqual(requests.filter { $0.path == "/v1/stats/overview" }.count, 1)
        let eventRequests = requests.filter { $0.path == "/v1/events" }
        XCTAssertEqual(eventRequests.count, 2)
        let firstEventRequest = try XCTUnwrap(eventRequests.first)
        let firstQuery = try XCTUnwrap(URLComponents(
            url: firstEventRequest,
            resolvingAgainstBaseURL: false
        )?.queryItems)
        XCTAssertTrue(firstQuery.contains(URLQueryItem(name: "type", value: "digit_dialed")))
        XCTAssertTrue(firstQuery.contains(URLQueryItem(name: "installationId", value: "installation-1")))
        XCTAssertNotNil(firstQuery.first(where: { $0.name == "since" })?.value)
        XCTAssertNotNil(firstQuery.first(where: { $0.name == "until" })?.value)
        let lastEventRequest = try XCTUnwrap(eventRequests.last)
        let secondQuery = try XCTUnwrap(URLComponents(
            url: lastEventRequest,
            resolvingAgainstBaseURL: false
        )?.queryItems)
        XCTAssertTrue(secondQuery.contains(URLQueryItem(name: "cursor", value: "next-page")))

        let cached = try await client.fetchStatsOverview(
            selection: .window(.last7d),
            installationScope: .installation("installation-1")
        )
        XCTAssertEqual(cached.pickupsHangups.digitsDialed["1"], 2)
        XCTAssertEqual(
            StatsDigitRecoveryURLProtocol.capturedURLs().filter { $0.path == "/v1/events" }.count,
            2
        )

        StatsDigitRecoveryURLProtocol.reset(failEventRequests: true)
        let fallback = try await client.fetchStatsOverview(
            selection: .window(.last7d),
            installationScope: .installation("installation-2")
        )
        XCTAssertEqual(fallback.calls.total, 2)
        XCTAssertEqual(fallback.pickupsHangups.digitsDialed.values.reduce(0, +), 0)
        XCTAssertEqual(
            StatsDigitRecoveryURLProtocol.capturedURLs().filter { $0.path == "/v1/events" }.count,
            1
        )

        StatsDigitRecoveryURLProtocol.reset(reportedDigitCount: 8)
        let authoritative = try await client.fetchStatsOverview(
            selection: .window(.last7d),
            installationScope: .installation("installation-3")
        )
        XCTAssertEqual(authoritative.pickupsHangups.digitsDialed["1"], 8)
        XCTAssertEqual(
            StatsDigitRecoveryURLProtocol.capturedURLs().filter { $0.path == "/v1/events" }.count,
            0
        )
    }

    func testCompletionRateAndQuietForSeconds() {
        let calls = StatsOverview.Calls(
            total: 0,
            completed: 0,
            inProgress: 0,
            averageDurationMs: nil,
            longestDurationMs: nil,
            outcomes: [:],
            perDay: []
        )
        let overview = makeOverview(calls: calls, lastActivityAt: Date(timeIntervalSinceNow: -42))
        XCTAssertNil(overview.completionRate)
        if let seconds = overview.quietForSeconds {
            XCTAssertGreaterThanOrEqual(seconds, 42)
            XCTAssertLessThan(seconds, 45)
        } else {
            XCTFail("quietForSeconds should be non-nil")
        }
    }

    func testDayOfWeekLabelClampsToValidRange() {
        XCTAssertEqual(StatsOverview.dayOfWeekLabel(0), "Sunday")
        XCTAssertEqual(StatsOverview.dayOfWeekLabel(6), "Saturday")
        XCTAssertNil(StatsOverview.dayOfWeekLabel(-1))
        XCTAssertNil(StatsOverview.dayOfWeekLabel(99))
    }

    // MARK: - Helpers

    private func makeOverview(
        calls: StatsOverview.Calls = .init(
            total: 0, completed: 0, inProgress: 0,
            averageDurationMs: nil, longestDurationMs: nil,
            outcomes: [:], perDay: []
        ),
        messages: StatsOverview.Messages = .init(total: 0, byStatus: [:], averageDurationMs: nil),
        pickupsHangups: StatsOverview.PickupsHangups = .init(pickups: 0, hangups: 0, digitsDialed: [:]),
        lastActivityAt: Date? = nil
    ) -> StatsOverview {
        StatsOverview(
            window: .last7d,
            rangeStart: nil,
            rangeEnd: Date(),
            generatedAt: Date(),
            timezone: "UTC",
            calls: calls,
            messages: messages,
            playback: .init(totalPlaybacks: 0),
            pickupsHangups: pickupsHangups,
            uploads: .init(succeeded: 0, failed: 0, failureRate: nil),
            topQuestions: [],
            hourly: [],
            busiest: .init(hour: nil, dayOfWeek: nil),
            lastActivityAt: lastActivityAt,
            boothBreakdown: []
        )
    }
}

private final class StatsDigitRecoveryURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var requests: [URL] = []
    nonisolated(unsafe) private static var shouldFailEventRequests = false
    nonisolated(unsafe) private static var reportedDigitCount = 0
    private static let lock = NSLock()

    static func reset(failEventRequests: Bool = false, reportedDigitCount: Int = 0) {
        lock.lock()
        requests = []
        shouldFailEventRequests = failEventRequests
        self.reportedDigitCount = reportedDigitCount
        lock.unlock()
    }

    static func capturedURLs() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.lock.lock()
        Self.requests.append(url)
        Self.lock.unlock()

        let body: String
        let statusCode: Int
        switch url.path {
        case "/v1/stats/overview":
            body = Self.overviewResponseBody()
            statusCode = 200
        case "/v1/events":
            if Self.eventRequestsShouldFail() {
                body = #"{"error":"temporarily_unavailable"}"#
                statusCode = 503
            } else {
                let cursor = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "cursor" })?
                    .value
                body = cursor == nil
                    ? Self.firstEventPage
                    : #"{"items":[{"payload":{"digit":0}},{"payload":{"digit":5}}],"nextCursor":null}"#
                statusCode = 200
            }
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func eventRequestsShouldFail() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return shouldFailEventRequests
    }

    private static func overviewResponseBody() -> String {
        lock.lock()
        defer { lock.unlock() }
        return overviewResponse.replacingOccurrences(
            of: #""1": 0"#,
            with: #""1": \#(reportedDigitCount)"#
        )
    }

    private static let firstEventPage = #"""
    { "items": [
        { "payload": { "digit": 1 } }, { "payload": { "digit": 1 } },
        { "payload": { "digit": 5 } }, {}, { "payload": null },
        { "payload": "invalid" }, { "payload": { "digit": "1" } },
        { "payload": { "digit": 12 } }
      ], "nextCursor": "next-page" }
    """#

    private static let overviewResponse = #"""
    {
      "window": "7d", "rangeStart": "2026-08-12T12:00:00Z",
      "rangeEnd": "2026-08-19T12:00:00Z", "generatedAt": "2026-08-19T12:00:00Z",
      "timezone": "UTC",
      "calls": {
        "total": 2, "completed": 1, "inProgress": 0,
        "averageDurationMs": null, "longestDurationMs": null,
        "outcomes": { "recording_completed": 1 }, "perDay": []
      },
      "messages": { "total": 0, "byStatus": {}, "averageDurationMs": null },
      "playback": { "totalPlaybacks": 0 },
      "pickupsHangups": {
        "pickups": 2, "hangups": 2,
        "digitsDialed": { "0": 0, "1": 0, "2": 0, "3": 0, "4": 0,
          "5": 0, "6": 0, "7": 0, "8": 0, "9": 0 }
      },
      "uploads": { "succeeded": 0, "failed": 0, "failureRate": null },
      "topQuestions": [], "hourly": [],
      "busiest": { "hour": null, "dayOfWeek": null },
      "lastActivityAt": null, "boothBreakdown": []
    }
    """#
}
