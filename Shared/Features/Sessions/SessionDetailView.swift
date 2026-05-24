//
//  SessionDetailView.swift
//  TelephoneBoothOperatorMobile
//
//  Single call session with its ordered event timeline. Available on
//  iOS / iPadOS / macOS / visionOS. watchOS + tvOS get tailored
//  experiences in later PRs.
//

#if !os(watchOS) && !os(tvOS)

import SwiftUI

public struct SessionDetailView: View {
    public let sessionId: String

    @State private var detail: CallSessionDetail?
    @State private var loading = false
    @State private var errorMessage: String?

    private let client: OperatorClient

    public init(sessionId: String, client: OperatorClient = .shared) {
        self.sessionId = sessionId
        self.client = client
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                if let errorMessage {
                    BannerView(message: errorMessage, kind: .error)
                }
                if let detail {
                    summaryCard(detail)
                    eventTimeline(detail.events)
                } else if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(Theme.Spacing.extraLarge)
                }
            }
            .padding(Theme.Spacing.large)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Session")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await load()
        }
        .refreshableIfAvailable {
            await load()
        }
    }

    private func summaryCard(_ detail: CallSessionDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader(text: "Summary")
            StatRow(label: "Booth", value: detail.boothId)
            StatRow(
                label: "Started",
                value: detail.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute().second())
            )
            if let endedAt = detail.endedAt {
                StatRow(
                    label: "Ended",
                    value: endedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute().second())
                )
            }
            if let digits = detail.digitsDialed, !digits.isEmpty {
                StatRow(label: "Digits dialed", value: digits)
            }
            if let outcome = detail.outcome {
                StatRow(label: "Outcome", value: outcome.displayName)
            }
            if let durationMs = detail.durationMs {
                StatRow(label: "Duration", value: formattedDuration(durationMs))
            }
            if let recordingId = detail.recordingId {
                StatRow(label: "Recording", value: recordingId)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
    }

    private func eventTimeline(_ events: [BoothEventRecord]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(text: "Events (\(events.count))")
            if events.isEmpty {
                Text("No events recorded for this session.")
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ForEach(events) { event in
                    EventRow(event: event)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
    }

    private func load() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            detail = try await client.fetchSession(id: sessionId)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't load this session."
        }
    }

    private func formattedDuration(_ durationMs: Int) -> String {
        let totalSeconds = Int((Double(durationMs) / 1000.0).rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return minutes > 0 ? String(format: "%dm %02ds", minutes, seconds) : "\(seconds)s"
    }
}

private struct EventRow: View {
    let event: BoothEventRecord

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.medium) {
            Image(systemName: icon(for: event.type))
                .foregroundStyle(color(for: event.type))
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.type.displayName)
                    .font(Theme.Fonts.bodyMedium.weight(.medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(event.occurredAt, format: .dateTime.hour().minute().second())
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.small)
    }

    private func icon(for type: BoothEventType) -> String {
        Self.eventIcons[type] ?? "dot.circle"
    }

    private static let eventIcons: [BoothEventType: String] = [
        .callStarted: "phone.arrow.up.right.fill",
        .callEnded: "phone.down.fill",
        .digitDialed: "number.square",
        .recordingStarted: "record.circle",
        .recordingStopped: "stop.circle",
        .uploadStarted: "icloud.and.arrow.up",
        .uploadCompleted: "checkmark.icloud.fill",
        .uploadFailed: "exclamationmark.icloud.fill",
        .error: "exclamationmark.triangle.fill",
        .log: "doc.text",
        .systemSample: "cpu"
    ]

    private func color(for type: BoothEventType) -> Color {
        switch type {
        case .error, .uploadFailed: return Theme.Colors.error
        case .callStarted, .recordingStarted, .uploadStarted: return Theme.Colors.accent
        case .uploadCompleted, .callEnded: return Theme.Colors.success
        default: return Theme.Colors.textSecondary
        }
    }
}

#endif
