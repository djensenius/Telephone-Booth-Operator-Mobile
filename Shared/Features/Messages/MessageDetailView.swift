//
//  MessageDetailView.swift
//  TelephoneBoothOperatorMobile
//
//  Single-message screen: status badge, FLAC audio playback, the
//  latest transcript (and full history collapsed below), the moderation
//  summary, and the human approve/reject decision.
//

#if !os(watchOS) && !os(tvOS)

import SwiftUI

public struct MessageDetailView: View {
    public let messageId: String

    @State private var message: Message?
    @State private var transcriptions: [Transcription] = []
    @State private var loading = false
    @State private var deciding = false
    @State private var decisionNotes = ""
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var showAllTranscripts = false

    private let client: OperatorClient
    private let onDecision: (Message) -> Void

    public init(
        messageId: String,
        client: OperatorClient = .shared,
        onDecision: @escaping (Message) -> Void = { _ in }
    ) {
        self.messageId = messageId
        self.client = client
        self.onDecision = onDecision
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                if let errorMessage {
                    BannerView(message: errorMessage, kind: .error)
                }
                if let statusMessage {
                    BannerView(message: statusMessage, kind: .info)
                }
                if let message {
                    audioCard(message)
                    if message.latestTranscription != nil || !transcriptions.isEmpty {
                        transcriptCard(message)
                    }
                    if message.latestModeration != nil {
                        moderationCard(message)
                    }
                    decisionCard(message)
                    metadataCard(message)
                } else if loading {
                    ProgressView().padding(Theme.Spacing.extraLarge)
                }
            }
            .padding(Theme.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Message")
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

    private func audioCard(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(text: "Audio")
            AudioPlayerView(
                audio: message.audio,
                label: "Recorded \(message.createdAt.formatted(date: .abbreviated, time: .shortened))"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
    }

    @ViewBuilder
    private func transcriptCard(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(text: "Transcript")
            if let latest = message.latestTranscription ?? transcriptions.first {
                TranscriptionRow(transcription: latest, emphasized: true)
            }
            if transcriptions.count > 1 {
                DisclosureGroup("History (\(transcriptions.count))", isExpanded: $showAllTranscripts) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                        ForEach(transcriptions.dropFirst()) { item in
                            TranscriptionRow(transcription: item, emphasized: false)
                        }
                    }
                    .padding(.top, Theme.Spacing.small)
                }
                .tint(Theme.Colors.accent)
                .font(Theme.Fonts.bodySmall)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
    }

    @ViewBuilder
    private func moderationCard(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader(text: "Moderation")
            if let moderation = message.latestModeration {
                if let rec = moderation.recommendation {
                    Label("AI recommendation: \(rec.displayName)", systemImage: "sparkles")
                        .font(Theme.Fonts.bodyMedium.weight(.semibold))
                        .foregroundStyle(recommendationColor(rec))
                }
                StatRow(label: "Provider", value: moderation.provider.displayName)
                if let flagged = moderation.flagged {
                    StatRow(label: "Flagged", value: flagged ? "Yes" : "No")
                }
                if let score = moderation.maxScore {
                    StatRow(label: "Max score", value: String(format: "%.2f", score))
                }
                if let reason = moderation.reasonSummary, !reason.isEmpty {
                    Text(reason)
                        .font(Theme.Fonts.bodySmall)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.top, Theme.Spacing.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
    }

    @ViewBuilder
    private func decisionCard(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(text: "Decision")

            if let rec = message.latestModeration?.recommendation {
                HStack(spacing: Theme.Spacing.small) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(recommendationColor(rec))
                    Text("AI recommends \(rec.displayName). The final decision is yours.")
                        .font(Theme.Fonts.bodySmall)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            switch message.status {
            case .uploading, .received:
                Text("A decision can be made once transcription and moderation have run.")
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
            case .pending, .approved, .rejected:
                if message.status == .approved || message.status == .rejected {
                    StatRow(label: "Current decision", value: message.status.displayName)
                }
                TextField("Notes (optional)", text: $decisionNotes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .font(Theme.Fonts.bodySmall)
                    .disabled(deciding)
                HStack(spacing: Theme.Spacing.medium) {
                    decisionButton(.approve, isCurrent: message.status == .approved)
                    decisionButton(.reject, isCurrent: message.status == .rejected)
                }
                if deciding {
                    ProgressView()
                }
            case .unknown:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
    }

    @ViewBuilder
    private func decisionButton(_ decision: MessageDecision, isCurrent: Bool) -> some View {
        let title = decision == .approve
            ? (isCurrent ? "Approved" : "Approve")
            : (isCurrent ? "Rejected" : "Reject")
        let icon = decision == .approve ? "checkmark.circle.fill" : "xmark.circle.fill"
        let tint = decision == .approve ? Theme.Colors.success : Theme.Colors.error

        if isCurrent {
            Button {
                Task { await decide(decision) }
            } label: {
                Label(title, systemImage: icon)
                    .font(Theme.Fonts.bodySmall.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .disabled(deciding)
        } else {
            Button {
                Task { await decide(decision) }
            } label: {
                Label(title, systemImage: icon)
                    .font(Theme.Fonts.bodySmall.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(tint)
            .disabled(deciding)
        }
    }

    private func recommendationColor(_ recommendation: ModerationRecommendation) -> Color {
        switch recommendation {
        case .approve: return Theme.Colors.success
        case .review: return Theme.Colors.warning
        case .reject: return Theme.Colors.error
        case .unknown: return Theme.Colors.textSecondary
        }
    }

    private func metadataCard(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader(text: "Metadata")
            StatRow(label: "Status", value: message.status.displayName)
            StatRow(
                label: "Created",
                value: message.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute().second())
            )
            if let received = message.receivedAt {
                StatRow(
                    label: "Received",
                    value: received.formatted(.dateTime.month(.abbreviated).day().hour().minute().second())
                )
            }
            if let questionId = message.questionId {
                StatRow(label: "Question", value: questionId)
            }
            if let notes = message.notes, !notes.isEmpty {
                Text(notes)
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
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
        async let messageTask: Message? = (try? await client.fetchMessage(id: messageId))
        async let listTask: TranscriptionList? = (try? await client.fetchTranscriptions(messageId: messageId))
        let (newMessage, newList) = await (messageTask, listTask)
        if let newMessage {
            message = newMessage
        } else if message == nil {
            errorMessage = "Couldn't load this message."
        }
        if let newList {
            transcriptions = newList.items
        }
    }

    private func decide(_ decision: MessageDecision) async {
        deciding = true
        errorMessage = nil
        statusMessage = nil
        defer { deciding = false }
        do {
            let updated = try await client.decideMessage(
                id: messageId,
                decision: decision,
                notes: decisionNotes
            )
            statusMessage = "Message \(updated.status.displayName.lowercased())."
            message = updated
            onDecision(updated)
            await PendingMessagesStore.shared.refresh(using: client)
            decisionNotes = ""
        } catch {
            let verb = decision == .approve ? "approve" : "reject"
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't \(verb) this message."
        }
    }
}

private struct TranscriptionRow: View {
    let transcription: Transcription
    let emphasized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                Text(transcription.provider.displayName)
                    .font(Theme.Fonts.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                if let model = transcription.model {
                    Text("· \(model)")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Text(transcription.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            if let text = transcription.text, !text.isEmpty {
                Text(text)
                    .font(emphasized ? Theme.Fonts.bodyLarge : Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .textSelection(.enabled)
            } else if transcription.status == .failed, let error = transcription.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.error)
            } else {
                Text(transcription.status.displayName)
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .italic()
            }
        }
    }
}

#endif
