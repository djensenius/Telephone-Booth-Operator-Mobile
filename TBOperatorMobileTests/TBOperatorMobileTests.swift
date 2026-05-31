//
//  TBOperatorMobileTests.swift
//

import XCTest
@testable import TBOperatorMobile

final class TBOperatorMobileTests: XCTestCase {

    // MARK: - StatsSummary round-trip

    func testStatsSummaryRoundTrip() throws {
        let json = """
        {
          "booth": {
            "state": "playingMessage",
            "updatedAt": "2026-05-23T14:32:11.250Z",
            "currentQuestionId": "11111111-1111-1111-1111-111111111111",
            "currentMessageId": "22222222-2222-2222-2222-222222222222",
            "lastError": null
          },
          "messages": {
            "pending": 3,
            "receivedToday": 12,
            "latestId": "33333333-3333-3333-3333-333333333333"
          },
          "calls": {
            "today": 8,
            "inProgress": 1
          },
          "realtime": {
            "wsClients": 4
          },
          "generatedAt": "2026-05-23T14:32:11.250Z"
        }
        """
        let data = Data(json.utf8)

        let summary = try OperatorJSON.decoder.decode(StatsSummary.self, from: data)
        XCTAssertEqual(summary.booth.state, .playingMessage)
        XCTAssertTrue(summary.booth.state.isCallActive)
        XCTAssertEqual(summary.messages.pending, 3)
        XCTAssertEqual(summary.messages.receivedToday, 12)
        XCTAssertEqual(summary.calls.today, 8)
        XCTAssertEqual(summary.calls.inProgress, 1)
        XCTAssertEqual(summary.realtime.wsClients, 4)

        let reencoded = try OperatorJSON.encoder.encode(summary)
        let again = try OperatorJSON.decoder.decode(StatsSummary.self, from: reencoded)
        XCTAssertEqual(summary, again)
    }

    func testStatsSummaryHandlesBasicISODates() throws {
        let json = """
        {
          "booth": { "state": "idle", "updatedAt": "2026-05-23T14:32:11Z" },
          "messages": { "pending": 0, "receivedToday": 0, "latestId": null },
          "calls": { "today": 0, "inProgress": 0 },
          "realtime": { "wsClients": 0 },
          "generatedAt": "2026-05-23T14:32:11Z"
        }
        """
        let data = Data(json.utf8)

        let summary = try OperatorJSON.decoder.decode(StatsSummary.self, from: data)
        XCTAssertEqual(summary.booth.state, .idle)
        XCTAssertNil(summary.booth.currentQuestionId)
    }

    func testOperatorMeRoundTrip() throws {
        let json = """
        {
          "id": "auth0|operator-1",
          "name": "Ada Lovelace",
          "email": "ada@example.com",
          "groups": ["telephone-booth-operators"],
          "picture": "https://example.com/avatar.png",
          "providerName": "Authentik"
        }
        """
        let data = Data(json.utf8)

        let profile = try OperatorJSON.decoder.decode(OperatorMe.self, from: data)
        XCTAssertEqual(profile.id, "auth0|operator-1")
        XCTAssertEqual(profile.email, "ada@example.com")
        XCTAssertEqual(profile.picture?.host, "example.com")
        XCTAssertEqual(profile.groups, ["telephone-booth-operators"])
    }

    // MARK: - BoothState helpers

    func testBoothStateCallActiveFlags() {
        let active: [BoothState] = [
            .dialing, .playingQuestion, .beep, .recording, .uploading,
            .playingMessage, .playingInstructions
        ]
        let inactive: [BoothState] = [.idle, .dialTone, .error]
        for state in active {
            XCTAssertTrue(state.isCallActive, "\(state) should be call-active")
        }
        for state in inactive {
            XCTAssertFalse(state.isCallActive, "\(state) should not be call-active")
        }
    }

    // MARK: - AppConfig URL building

    @MainActor
    func testAppConfigBuildsPathURLs() {
        let url = AppConfig.shared.url(forPath: "/v1/stats/summary")
        XCTAssertEqual(url.path, "/v1/stats/summary")
        XCTAssertEqual(url.scheme, AppConfig.shared.apiBaseURL.scheme)
    }

    @MainActor
    func testAppConfigBuildsPathURLsWithoutLeadingSlash() {
        let url = AppConfig.shared.url(forPath: "v1/auth/me")
        XCTAssertEqual(url.path, "/v1/auth/me")
    }

    // MARK: - CallSession decoding

    func testCallSessionDecodesAllFields() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "boothId": "booth-a",
          "bootId": "11111111-1111-1111-1111-111111111111",
          "startedAt": "2026-05-23T14:30:00Z",
          "endedAt": "2026-05-23T14:32:11Z",
          "digitsDialed": "1234",
          "outcome": "recording_completed",
          "recordingId": "rec-9001",
          "durationMs": 131000
        }
        """
        let data = Data(json.utf8)
        let session = try OperatorJSON.decoder.decode(CallSession.self, from: data)
        XCTAssertEqual(session.outcome, .recordingCompleted)
        XCTAssertTrue(session.outcome?.isSuccess == true)
        XCTAssertEqual(session.durationMs, 131_000)
        XCTAssertEqual(session.digitsDialed, "1234")
    }

    func testCallSessionDecodesOptionalNulls() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000002",
          "boothId": "booth-a",
          "bootId": "11111111-1111-1111-1111-111111111111",
          "startedAt": "2026-05-23T14:30:00Z",
          "endedAt": null,
          "digitsDialed": null,
          "outcome": null,
          "recordingId": null,
          "durationMs": null
        }
        """
        let data = Data(json.utf8)
        let session = try OperatorJSON.decoder.decode(CallSession.self, from: data)
        XCTAssertNil(session.outcome)
        XCTAssertNil(session.durationMs)
    }

    func testSessionListPageDecodesCursor() throws {
        let json = """
        {
          "items": [],
          "nextCursor": "abc123"
        }
        """
        let data = Data(json.utf8)
        let page = try OperatorJSON.decoder.decode(SessionListPage.self, from: data)
        XCTAssertEqual(page.nextCursor, "abc123")
        XCTAssertTrue(page.items.isEmpty)
    }

    // MARK: - System snapshot

    func testSystemSnapshotComputesMemoryRatio() {
        let snapshot = BoothSystemSnapshot(
            cpu: .init(
                usageRatio: 0.42,
                loadAvg1m: 0.5,
                loadAvg5m: 0.6,
                loadAvg15m: 0.7
            ),
            temperatureCelsius: 47.5,
            memory: .init(
                totalBytes: 8_000_000_000,
                usedBytes: 3_000_000_000
            ),
            uptimeSeconds: 12_345,
            tailscale: .init(connected: true)
        )
        XCTAssertEqual(snapshot.memoryUsedRatio ?? 0, 0.375, accuracy: 0.0001)
    }

    func testSystemSnapshotMemoryRatioGuardsAgainstZeroTotal() {
        let snapshot = BoothSystemSnapshot(
            memory: .init(
                totalBytes: 0,
                usedBytes: 1_000
            )
        )
        XCTAssertNil(snapshot.memoryUsedRatio)
    }

    // MARK: - Booth event

    func testBoothEventTypeDisplayName() {
        XCTAssertEqual(BoothEventType.callStarted.displayName, "Call Started")
        XCTAssertEqual(BoothEventType.recordingStopped.displayName, "Recording Stopped")
        XCTAssertEqual(BoothEventType.error.displayName, "Error")
    }

    // MARK: - DurationFormatter

    func testDurationFormatterReturnsNilForMissingOrNonPositive() {
        XCTAssertNil(DurationFormatter.shortString(milliseconds: nil))
        XCTAssertNil(DurationFormatter.shortString(milliseconds: 0))
        XCTAssertNil(DurationFormatter.shortString(milliseconds: -500))
    }

    func testDurationFormatterFormatsSeconds() {
        XCTAssertEqual(DurationFormatter.shortString(milliseconds: 45_000), "45s")
        XCTAssertEqual(DurationFormatter.shortString(milliseconds: 500), "1s")
    }

    func testDurationFormatterFormatsMinutesAndSeconds() {
        XCTAssertEqual(DurationFormatter.shortString(milliseconds: 131_000), "2m 11s")
        XCTAssertEqual(DurationFormatter.shortString(milliseconds: 600_000), "10m 00s")
    }

    // MARK: - Message decoding

    func testMessageDecodesWithLatestTranscriptionAndModeration() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "status": "approved",
          "questionId": "22222222-2222-2222-2222-222222222222",
          "notes": "Sounds good.",
          "createdAt": "2026-05-23T14:30:00Z",
          "receivedAt": "2026-05-23T14:30:42Z",
          "audio": {
            "url": "https://example.com/audio.flac",
            "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "durationMs": 12300
          },
          "latestTranscription": {
            "id": "33333333-3333-3333-3333-333333333333",
            "messageId": "11111111-1111-1111-1111-111111111111",
            "provider": "openai",
            "model": "whisper-1",
            "status": "succeeded",
            "text": "Hello, operator.",
            "language": "en",
            "durationMs": 12300,
            "latencyMs": 850,
            "error": null,
            "requestedById": null,
            "createdAt": "2026-05-23T14:31:00Z",
            "completedAt": "2026-05-23T14:31:01Z"
          },
          "latestModeration": {
            "id": "44444444-4444-4444-4444-444444444444",
            "messageId": "11111111-1111-1111-1111-111111111111",
            "transcriptionId": "33333333-3333-3333-3333-333333333333",
            "provider": "openai",
            "model": "omni-moderation-latest",
            "status": "succeeded",
            "flagged": false,
            "recommendation": "approve",
            "maxScore": 0.05,
            "categories": {"hate": 0.01},
            "reasonSummary": null,
            "latencyMs": 120,
            "error": null,
            "createdAt": "2026-05-23T14:31:02Z"
          }
        }
        """
        let data = Data(json.utf8)
        let message = try OperatorJSON.decoder.decode(Message.self, from: data)
        XCTAssertEqual(message.status, .approved)
        XCTAssertEqual(message.audio.durationMs, 12_300)
        XCTAssertEqual(message.latestTranscription?.text, "Hello, operator.")
        XCTAssertEqual(message.latestTranscription?.provider, .openai)
        XCTAssertEqual(message.latestModeration?.recommendation, .approve)
        XCTAssertEqual(message.latestModeration?.flagged, false)
    }

    func testMessageDecodesWithoutTranscription() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "status": "received",
          "questionId": null,
          "notes": null,
          "createdAt": "2026-05-23T14:30:00Z",
          "receivedAt": null,
          "audio": {
            "url": "https://example.com/audio.flac",
            "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            "durationMs": null
          },
          "latestTranscription": null,
          "latestModeration": null
        }
        """
        let data = Data(json.utf8)
        let message = try OperatorJSON.decoder.decode(Message.self, from: data)
        XCTAssertNil(message.latestTranscription)
        XCTAssertNil(message.latestModeration)
        XCTAssertNil(message.audio.durationMs)
    }

    func testAiProviderDisplayNames() {
        XCTAssertEqual(AiProvider.openai.displayName, "OpenAI")
        XCTAssertEqual(AiProvider.macApp.displayName, "Mac app")
        XCTAssertEqual(AiProvider.disabled.displayName, "Disabled")
    }

    func testMessageStatusRoundTrip() throws {
        for status in MessageStatus.knownCases {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(MessageStatus.self, from: data)
            XCTAssertEqual(status, decoded)
        }
    }

    // MARK: - Question decoding

    func testQuestionDecodesFromOperatorJSON() throws {
        let json = """
        {
          "id": "44444444-4444-4444-4444-444444444444",
          "prompt": "Tell me about your favourite phone call.",
          "audio": {
            "url": "https://example.com/q.flac",
            "sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
            "durationMs": 4321
          },
          "createdAt": "2026-05-23T14:32:11.250Z",
          "retiredAt": null
        }
        """
        let question = try OperatorJSON.decoder.decode(Question.self, from: Data(json.utf8))
        XCTAssertEqual(question.id, "44444444-4444-4444-4444-444444444444")
        XCTAssertEqual(question.prompt, "Tell me about your favourite phone call.")
        XCTAssertEqual(question.audio.durationMs, 4321)
        XCTAssertNil(question.retiredAt)
    }

    func testQuestionListPaging() throws {
        let json = """
        {
          "items": [
            {
              "id": "55555555-5555-5555-5555-555555555555",
              "prompt": "What did the dial tone sound like?",
              "audio": {
                "url": "https://example.com/q1.flac",
                "sha256": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
                "durationMs": 2200
              },
              "createdAt": "2026-05-23T14:30:00.000Z",
              "retiredAt": null
            }
          ],
          "nextCursor": "55555555-5555-5555-5555-555555555556"
        }
        """
        let page = try OperatorJSON.decoder.decode(QuestionList.self, from: Data(json.utf8))
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.nextCursor, "55555555-5555-5555-5555-555555555556")
    }

    // MARK: - Event list decoding

    func testEventListDecodesNestedRecords() throws {
        let json = """
        {
          "items": [
            {
              "id": "66666666-6666-6666-6666-666666666666",
              "eventId": "evt-1",
              "boothId": "booth-a",
              "bootId": "boot-z",
              "type": "call_started",
              "occurredAt": "2026-05-23T14:32:00.000Z",
              "receivedAt": "2026-05-23T14:32:00.500Z",
              "sessionId": "77777777-7777-7777-7777-777777777777",
              "recordingId": null,
              "payload": { "anything": "ignored" }
            }
          ],
          "nextCursor": null
        }
        """
        let page = try OperatorJSON.decoder.decode(EventList.self, from: Data(json.utf8))
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.type, .callStarted)
        XCTAssertNil(page.nextCursor)
    }

    // MARK: - EventStreamFilters

    func testEventStreamFiltersEquality() {
        let one = EventStreamFilters(boothId: "booth-a", sessionId: nil, type: .callStarted)
        let two = EventStreamFilters(boothId: "booth-a", sessionId: nil, type: .callStarted)
        let three = EventStreamFilters(boothId: "booth-b", sessionId: nil, type: .callStarted)
        XCTAssertEqual(one, two)
        XCTAssertNotEqual(one, three)
    }

    // MARK: - WidgetSnapshot

    func testWidgetSnapshotFromStatsSummary() {
        let stats = StatsSummary.placeholder
        let snapshot = WidgetSnapshot(stats: stats)
        XCTAssertEqual(snapshot.boothState, stats.booth.state)
        XCTAssertEqual(snapshot.boothUpdatedAt, stats.booth.updatedAt)
        XCTAssertEqual(snapshot.pendingMessages, stats.messages.pending)
        XCTAssertEqual(snapshot.receivedToday, stats.messages.receivedToday)
        XCTAssertEqual(snapshot.callsToday, stats.calls.today)
        XCTAssertEqual(snapshot.callsInProgress, stats.calls.inProgress)
        XCTAssertEqual(snapshot.wsClients, stats.realtime.wsClients)
        XCTAssertEqual(snapshot.generatedAt, stats.generatedAt)
    }

    func testWidgetSnapshotRoundTrip() throws {
        let snapshot = WidgetSnapshot.placeholder
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(snapshot, decoded)
    }
}
