//
//  MessageDetailView.swift
//  TelephoneBoothOperatorMobile
//
//  Single-message screen: status badge, FLAC audio playback, the
//  latest transcript (and full history collapsed below), and a button
//  to re-run the transcription/moderation pipeline.
//

#if !os(watchOS) && !os(tvOS)

import SwiftUI

public struct MessageDetailView: View {
    public let messageId: String

    @State private var message: Message?
    @State private var transcriptions: [Transcription] = []
    @State private var loading = false
    @State private var transcribing = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var showAllTranscripts = false

    private let client: OperatorClient

    public init(messageId: String, client: OperatorClient = .shared) {
        self.messageId = messageId
        self.client = client
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
                    transcriptCard(message)
                    moderationCard(message)
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
            AudioPlayerView(audio: message.audio)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
    }

    @ViewBuilder
    private func transcriptCard(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack {
                SectionHeader(text: "Transcript")
                Spacer()
                Button {
                    Task { await transcribe() }
                } label: {
                    if transcribing {
                        ProgressView()
                    } else {
                        Label("Re-transcribe", systemImage: "arrow.clockwise")
                            .font(Theme.Fonts.bodySmall.weight(.semibold))
                    }
                }
                .buttonStyle(.bordered)
                .tint(Theme.Colors.accent)
                .disabled(transcribing)
            }
            if let latest = message.latestTranscription {
                TranscriptionRow(transcription: latest, emphasized: true)
            } else {
                Text("No transcription yet.")
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
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
        if let moderation = message.latestModeration {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                SectionHeader(text: "Moderation")
                if let rec = moderation.recommendation {
                    StatRow(label: "Recommendation", value: rec.displayName)
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.large)
            .glassCardBackground()
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

    private func transcribe() async {
        transcribing = true
        errorMessage = nil
        statusMessage = nil
        defer { transcribing = false }
        do {
            let newest = try await client.transcribeMessage(id: messageId)
            statusMessage = "Transcription \(newest.status.displayName.lowercased())."
            // Refresh the full message + list so the UI shows the new latest
            // transcript and any moderation update the operator just made.
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't re-run transcription."
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
