//
//  StatsSummary.swift
//  TelephoneBoothOperatorMobile
//
//  Mirrors the `StatsSummary` schema from the operator OpenAPI spec.
//  This is the primary payload polled by widgets and the dashboard.
//

import Foundation

public struct StatsSummary: Codable, Sendable, Hashable {
    public let booth: BoothStatus
    public let messages: Messages
    public let calls: Calls
    public let realtime: Realtime
    public let generatedAt: Date

    public struct Messages: Codable, Sendable, Hashable {
        public let pending: Int
        public let receivedToday: Int
        public let latestId: UUID?
    }

    public struct Calls: Codable, Sendable, Hashable {
        public let today: Int
        public let inProgress: Int
    }

    public struct Realtime: Codable, Sendable, Hashable {
        public let wsClients: Int
    }

    public init(
        booth: BoothStatus,
        messages: Messages,
        calls: Calls,
        realtime: Realtime,
        generatedAt: Date
    ) {
        self.booth = booth
        self.messages = messages
        self.calls = calls
        self.realtime = realtime
        self.generatedAt = generatedAt
    }
}

/// Placeholder summary used by SwiftUI previews and widget snapshots.
public extension StatsSummary {
    static let placeholder = StatsSummary(
        booth: BoothStatus(
            state: .idle,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ),
        messages: Messages(pending: 2, receivedToday: 7, latestId: nil),
        calls: Calls(today: 4, inProgress: 0),
        realtime: Realtime(wsClients: 1),
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

/// Shared, deterministic sample payloads for SwiftUI previews and App Review demo mode.
// swiftlint:disable:next type_body_length
public enum DemoData {
    public static let now = Date(timeIntervalSince1970: 1_779_800_000)
    public static let boothId = "booth-main"
    public static let bootId = "demo-boot-2026"

    public static let operatorProfile = OperatorMe(
        id: "demo-operator",
        name: "Demo Operator",
        email: "operator@example.com",
        groups: ["App Store Review", "Operators"],
        providerName: "Demo"
    )

    public static let boothStatus = BoothStatus(
        state: .recording,
        updatedAt: now.addingTimeInterval(-42),
        currentQuestionId: UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
        runtimeMode: .simulator
    )

    public static let statsSummary = StatsSummary(
        booth: boothStatus,
        messages: StatsSummary.Messages(
            pending: 3,
            receivedToday: 18,
            latestId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")
        ),
        calls: StatsSummary.Calls(today: 27, inProgress: 1),
        realtime: StatsSummary.Realtime(wsClients: 4),
        generatedAt: now
    )

    public static let statusHistory: [BoothStatus] = (0..<24).map { index in
        BoothStatus(
            state: index.isMultiple(of: 5) ? .recording : .idle,
            updatedAt: now.addingTimeInterval(TimeInterval(index - 24) * 900),
            runtimeMode: .simulator
        )
    }

    public static let sessions: [CallSession] = [
        CallSession(
            id: "demo-session-3",
            boothId: boothId,
            bootId: bootId,
            startedAt: now.addingTimeInterval(-9 * 60),
            endedAt: nil,
            digitsDialed: "7",
            outcome: nil,
            recordingId: "demo-recording-3",
            durationMs: nil,
            version: "demo"
        ),
        CallSession(
            id: "demo-session-2",
            boothId: boothId,
            bootId: bootId,
            startedAt: now.addingTimeInterval(-46 * 60),
            endedAt: now.addingTimeInterval(-42 * 60),
            digitsDialed: "4",
            outcome: .recordingCompleted,
            recordingId: "demo-recording-2",
            durationMs: 214_000,
            version: "demo"
        ),
        CallSession(
            id: "demo-session-1",
            boothId: boothId,
            bootId: bootId,
            startedAt: now.addingTimeInterval(-2 * 60 * 60),
            endedAt: now.addingTimeInterval(-2 * 60 * 60 + 95),
            digitsDialed: "2",
            outcome: .hungUpDuringPrompt,
            recordingId: nil,
            durationMs: 95_000,
            version: "demo"
        )
    ]

    public static let messages: [Message] = [
        message(
            id: "demo-message-3",
            status: .pending,
            text: "I remember calling my grandmother from the phone booth outside the train station.",
            secondsAgo: 12 * 60,
            durationMs: 48_000,
            recommendation: .review
        ),
        message(
            id: "demo-message-2",
            status: .approved,
            text: "The rotary click is still the sound of summer evenings to me.",
            secondsAgo: 48 * 60,
            durationMs: 22_000,
            recommendation: .approve
        ),
        message(
            id: "demo-message-1",
            status: .received,
            text: "Testing the booth from the App Store review demo. Everything is offline.",
            secondsAgo: 2 * 60 * 60,
            durationMs: 31_000,
            recommendation: nil
        )
    ]

    public static let questions: [Question] = [
        question(id: "demo-question-1", prompt: "What is your favorite telephone memory?", durationMs: 9_000),
        question(id: "demo-question-2", prompt: "Who would you call if this booth could reach the past?", durationMs: 11_000),
        question(id: "demo-question-3", prompt: "Leave a sound, story, or greeting for the next visitor.", durationMs: 8_000)
    ]

    public static let events: [BoothEventRecord] = [
        event(id: "demo-event-5", type: .recordingStarted, minutesAgo: 1, sessionId: "demo-session-3"),
        event(id: "demo-event-4", type: .digitDialed, minutesAgo: 2, sessionId: "demo-session-3"),
        event(id: "demo-event-3", type: .callStarted, minutesAgo: 3, sessionId: "demo-session-3"),
        event(id: "demo-event-2", type: .uploadCompleted, minutesAgo: 42, sessionId: "demo-session-2"),
        event(id: "demo-event-1", type: .systemSample, minutesAgo: 54, sessionId: nil)
    ]

    public static let systemEnvelope = BoothSystemSnapshotEnvelope(
        boothId: boothId,
        snapshot: BoothSystemSnapshot(
            cpu: BoothSystemSnapshot.CPUStats(
                usageRatio: 0.34,
                perCoreUsageRatio: [0.30, 0.38, 0.29, 0.39],
                physicalCores: 4,
                loadAvg1m: 0.72,
                loadAvg5m: 0.66,
                loadAvg15m: 0.58
            ),
            temperatureCelsius: 48.5,
            memory: BoothSystemSnapshot.MemoryStats(
                totalBytes: 8_589_934_592,
                usedBytes: 3_221_225_472,
                swapTotalBytes: 1_073_741_824,
                swapUsedBytes: 67_108_864
            ),
            disks: [
                BoothSystemSnapshot.DiskUsage(
                    mountPoint: "/",
                    filesystem: "ext4",
                    totalBytes: 63_927_418_880,
                    availableBytes: 42_949_672_960
                )
            ],
            networks: [
                BoothSystemSnapshot.NetworkInterface(
                    interface: "wlan0",
                    receiveBytesTotal: 1_245_000_000,
                    transmitBytesTotal: 842_000_000
                )
            ],
            uptimeSeconds: 186_400,
            process: BoothSystemSnapshot.ProcessStats(
                residentBytes: 114_294_784,
                virtualBytes: 492_830_720,
                openFds: 42,
                threads: 12,
                uptimeSeconds: 86_400
            ),
            audio: BoothSystemSnapshot.AudioStats(
                inputDevice: "Demo USB Audio",
                outputDevice: "Demo Handset",
                sampleRateHz: 48_000
            ),
            tailscale: BoothSystemSnapshot.TailscaleStats(
                connected: true,
                peerCount: 5,
                hostname: "telephone-booth-demo"
            ),
            throttling: BoothSystemSnapshot.ThrottlingFlags(),
            runtimeMode: .simulator,
            hostname: "telephone-booth-demo",
            osVersion: "Debian GNU/Linux 13",
            kernelVersion: "6.12.0-demo"
        ),
        receivedAt: now.addingTimeInterval(-18),
        version: "demo"
    )

    public static var transcription: Transcription {
        transcriptions(messageId: "demo-message-1").first!
    }

    public static func statsOverview(window: StatsWindow) -> StatsOverview {
        let rangeStart: Date?
        switch window {
        case .last24h:
            rangeStart = now.addingTimeInterval(-24 * 60 * 60)
        case .last7d:
            rangeStart = now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .last30d:
            rangeStart = now.addingTimeInterval(-30 * 24 * 60 * 60)
        case .all, .unknown:
            rangeStart = nil
        }

        return StatsOverview(
            window: window,
            rangeStart: rangeStart,
            rangeEnd: now,
            generatedAt: now,
            timezone: "UTC",
            calls: StatsOverview.Calls(
                total: 124,
                completed: 91,
                inProgress: 1,
                averageDurationMs: 92_000,
                longestDurationMs: 321_000,
                outcomes: ["recording_completed": 91, "hung_up_during_prompt": 18, "upload_failed": 2],
                perDay: [
                    .init(date: "2026-05-25", total: 12, completed: 9),
                    .init(date: "2026-05-26", total: 18, completed: 13),
                    .init(date: "2026-05-27", total: 20, completed: 14),
                    .init(date: "2026-05-28", total: 16, completed: 12),
                    .init(date: "2026-05-29", total: 22, completed: 17),
                    .init(date: "2026-05-30", total: 28, completed: 21),
                    .init(date: "2026-05-31", total: 8, completed: 5)
                ]
            ),
            messages: StatsOverview.Messages(
                total: 87,
                byStatus: ["received": 14, "pending": 3, "approved": 66, "rejected": 4],
                averageDurationMs: 39_000
            ),
            playback: StatsOverview.Playback(totalPlaybacks: 236),
            pickupsHangups: StatsOverview.PickupsHangups(
                pickups: 151,
                hangups: 27,
                digitsDialed: ["0": 4, "1": 9, "2": 12, "3": 8, "4": 19, "7": 31, "9": 6]
            ),
            uploads: StatsOverview.Uploads(succeeded: 84, failed: 3, failureRate: 0.034),
            topQuestions: questions.map {
                StatsOverview.TopQuestion(
                    questionId: UUID(uuidString: $0.id.replacingOccurrences(of: "demo-question-", with: "00000000-0000-0000-0000-00000000000")) ?? UUID(),
                    prompt: $0.prompt,
                    messageCount: 18,
                    lastUsedAt: now.addingTimeInterval(-90 * 60),
                    retiredAt: nil
                )
            },
            hourly: (0..<24).map {
                StatsOverview.HourlyBucket(hour: $0, calls: ($0 * 3) % 11, messages: ($0 * 2) % 8)
            },
            busiest: StatsOverview.Busiest(hour: 19, dayOfWeek: 6),
            lastActivityAt: now.addingTimeInterval(-12 * 60),
            boothBreakdown: [
                StatsOverview.BoothBreakdown(
                    boothId: boothId,
                    calls: 124,
                    messages: 87,
                    lastSeenAt: now.addingTimeInterval(-18)
                )
            ]
        )
    }

    public static func sessionDetail(id: String) -> CallSessionDetail {
        let session = sessions.first { $0.id == id } ?? sessions[0]
        return CallSessionDetail(
            id: session.id,
            boothId: session.boothId,
            bootId: session.bootId,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            digitsDialed: session.digitsDialed,
            outcome: session.outcome,
            recordingId: session.recordingId,
            durationMs: session.durationMs,
            version: session.version,
            events: events.filter { $0.sessionId == session.id }
        )
    }

    public static func message(id: String) -> Message {
        messages.first { $0.id == id } ?? messages[0]
    }

    public static func transcriptions(messageId: String) -> [Transcription] {
        [
            Transcription(
                id: "\(messageId)-transcription",
                messageId: messageId,
                provider: .openai,
                model: "demo-transcriber",
                status: .succeeded,
                text: message(id: messageId).latestTranscription?.text,
                language: "en",
                durationMs: 1_200,
                latencyMs: 860,
                error: nil,
                requestedById: operatorProfile.id,
                createdAt: now.addingTimeInterval(-11 * 60),
                completedAt: now.addingTimeInterval(-10 * 60)
            )
        ]
    }

    public static func moderation(messageId: String) -> Moderation {
        Moderation(
            id: "\(messageId)-moderation",
            messageId: messageId,
            transcriptionId: "\(messageId)-transcription",
            provider: .openai,
            model: "demo-moderator",
            status: .succeeded,
            flagged: false,
            recommendation: .approve,
            maxScore: 0.02,
            categories: ["safe": 0.98],
            reasonSummary: "Demo message is safe to approve.",
            latencyMs: 420,
            error: nil,
            createdAt: now.addingTimeInterval(-9 * 60)
        )
    }

    public static func eventStream(filters: EventStreamFilters) -> AsyncThrowingStream<BoothEventRecord, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for event in events where filters.type == nil || event.type == filters.type {
                    if Task.isCancelled { break }
                    continuation.yield(event)
                    try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func message(
        id: String,
        status: MessageStatus,
        text: String,
        secondsAgo: TimeInterval,
        durationMs: Int,
        recommendation: ModerationRecommendation?
    ) -> Message {
        let createdAt = now.addingTimeInterval(-secondsAgo)
        let transcription = Transcription(
            id: "\(id)-transcription",
            messageId: id,
            provider: .openai,
            model: "demo-transcriber",
            status: .succeeded,
            text: text,
            language: "en",
            durationMs: 1_000,
            latencyMs: 750,
            error: nil,
            requestedById: operatorProfile.id,
            createdAt: createdAt.addingTimeInterval(30),
            completedAt: createdAt.addingTimeInterval(36)
        )
        let moderation = recommendation.map {
            Moderation(
                id: "\(id)-moderation",
                messageId: id,
                transcriptionId: transcription.id,
                provider: .openai,
                model: "demo-moderator",
                status: .succeeded,
                flagged: $0 == .reject,
                recommendation: $0,
                maxScore: $0 == .approve ? 0.02 : 0.41,
                categories: ["demo": 1],
                reasonSummary: "Demo moderation result.",
                latencyMs: 430,
                error: nil,
                createdAt: createdAt.addingTimeInterval(44)
            )
        }
        return Message(
            id: id,
            status: status,
            questionId: questions.first?.id,
            notes: nil,
            createdAt: createdAt,
            receivedAt: createdAt.addingTimeInterval(8),
            audio: AudioRef(
                url: URL(string: "https://example.com/demo/\(id).m4a")!,
                sha256: "demo-\(id)",
                durationMs: durationMs
            ),
            latestTranscription: transcription,
            latestModeration: moderation
        )
    }

    private static func question(id: String, prompt: String, durationMs: Int) -> Question {
        Question(
            id: id,
            prompt: prompt,
            audio: AudioRef(
                url: URL(string: "https://example.com/demo/\(id).m4a")!,
                sha256: "demo-\(id)",
                durationMs: durationMs
            ),
            createdAt: now.addingTimeInterval(-86_400)
        )
    }

    private static func event(
        id: String,
        type: BoothEventType,
        minutesAgo: TimeInterval,
        sessionId: String?
    ) -> BoothEventRecord {
        BoothEventRecord(
            id: id,
            eventId: id,
            boothId: boothId,
            bootId: bootId,
            type: type,
            occurredAt: now.addingTimeInterval(-minutesAgo * 60),
            receivedAt: now.addingTimeInterval(-minutesAgo * 60 + 1),
            sessionId: sessionId,
            recordingId: sessionId?.replacingOccurrences(of: "session", with: "recording"),
            version: "demo"
        )
    }
}
