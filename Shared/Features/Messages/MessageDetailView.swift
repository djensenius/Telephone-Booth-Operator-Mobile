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
    @State private var sourceLanguage = ""
    @State private var onDeviceProcessor = OnDeviceMessageProcessor()
    @State private var editingTranscript = false
    @State private var transcriptCorrection = ""
    @State private var transcriptCorrectionTranscriptionId: String?
    @State private var editingTranslation = false
    @State private var translationCorrection = ""
    @State private var translationCorrectionTranscriptionId: String?
    @State private var translationCorrectionSHA256: String?
    @State private var savingCorrection = false
    @State private var usesDemoData = false
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
                    appleIntelligenceCard(message)
                    if message.latestTranscription != nil || !transcriptions.isEmpty {
                        transcriptCard(message)
                    }
                    if message.latestTranscription?.translationStatus != nil {
                        translationCard(message)
                    }
                    if message.latestApplicableModeration != nil {
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
            usesDemoData = await client.usesDemoData
            await load()
        }
        .task(id: sourceLanguage) {
            await onDeviceProcessor.refreshAvailability(sourceLanguage: sourceLanguage)
        }
        .refreshableIfAvailable {
            await load()
        }
    }
    private func appleIntelligenceCard(_ message: Message) -> some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                SectionHeader(text: "Apple Intelligence")
                Text(
                    "Runs a fresh on-device transcription, English translation, and moderation "
                        + "suggestion, then saves all three to the Operator."
                )
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
                TextField("Source language (optional, e.g. fr-CA)", text: $sourceLanguage)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.Fonts.bodySmall)
                    .disabled(onDeviceProcessor.isRunning)
                if let status = onDeviceProcessor.stage.statusText {
                    HStack(spacing: Theme.Spacing.small) {
                        if onDeviceProcessor.isRunning {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(status)
                            .font(Theme.Fonts.bodySmall)
                            .foregroundStyle(
                                onDeviceProcessor.canRetryPersistence
                                    ? Theme.Colors.error
                                    : Theme.Colors.textSecondary
                            )
                    }
                }
                if usesDemoData {
                    Text("On-device processing is unavailable for demo messages.")
                        .font(Theme.Fonts.bodySmall)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else if onDeviceProcessor.isAvailable {
                    HStack(spacing: Theme.Spacing.medium) {
                        Button {
                            Task {
                                await onDeviceProcessor.process(
                                    message: message,
                                    sourceLanguage: sourceLanguage,
                                    client: client
                                )
                                await load()
                            }
                        } label: {
                            Label("Process with Apple Intelligence", systemImage: "apple.intelligence")
                                .font(Theme.Fonts.bodySmall.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.Colors.accent)
                        .disabled(onDeviceProcessor.isRunning)

                        if onDeviceProcessor.canRetryPersistence {
                            Button("Retry save") {
                                Task {
                                    await onDeviceProcessor.retryPersistence(client: client)
                                    await load()
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(onDeviceProcessor.isRunning)
                        }
                    }
                } else if onDeviceProcessor.stage != .checkingAvailability {
                    Text("Check the BCP-47 source language (for example, fr-CA) and device support.")
                        .font(Theme.Fonts.bodySmall)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.large)
            .glassCardBackground()
        }
}
private extension MessageDetailView {
    private func translationCard(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader(text: "English Translation")
            if let transcription = message.latestTranscription {
                if let translation = transcription.completedTranslation {
                    Text(translation)
                        .font(Theme.Fonts.bodyLarge)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .textSelection(.enabled)
                    if let provider = transcription.translationProvider {
                        StatRow(label: "Provider", value: provider.displayName)
                    }
                    if let model = transcription.translationModel {
                        StatRow(label: "Model", value: model)
                    }
                    if let language = transcription.translatedLanguage {
                        StatRow(label: "Language", value: language)
                    }
                    TextCorrectionControls(
                        isEditing: $editingTranslation,
                        text: $translationCorrection,
                        originalText: translation,
                        editTitle: "Edit translation",
                        saveTitle: "Save corrected translation",
                        disabled: usesDemoData || onDeviceProcessor.isRunning || savingCorrection,
                        onEdit: {
                            translationCorrectionTranscriptionId = transcription.id
                            translationCorrectionSHA256 =
                                ReviewTextSnapshot.sha256(transcription.translationSnapshotText)
                        },
                        save: { await saveTranslationCorrection(message) }
                    )
                } else if transcription.translationStatus == .pending {
                    Label("Translation is still running.", systemImage: "clock")
                        .font(Theme.Fonts.bodySmall)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else if transcription.translationStatus == .failed {
                    Label(
                        transcription.translationError ?? "Translation failed.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.error)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
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
                if latest.status == .succeeded, let text = latest.text {
                    TextCorrectionControls(
                        isEditing: $editingTranscript,
                        text: $transcriptCorrection,
                        originalText: text,
                        editTitle: "Edit transcript",
                        saveTitle: "Save corrected transcript",
                        disabled: usesDemoData || onDeviceProcessor.isRunning || savingCorrection,
                        onEdit: {
                            transcriptCorrectionTranscriptionId = latest.id
                        },
                        save: { await saveTranscriptCorrection(message) }
                    )
                }
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
            if let moderation = message.latestApplicableModeration {
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

            if let rec = message.latestApplicableModeration?.recommendation {
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
            if sourceLanguage.isEmpty {
                sourceLanguage = newMessage.latestTranscription?.language ?? ""
            }
        } else if message == nil {
            errorMessage = "Couldn't load this message."
        }
        if let newList {
            transcriptions = newList.items
        }
    }
    func decide(_ decision: MessageDecision) async {
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
    func saveTranscriptCorrection(_ current: Message) async {
        savingCorrection = true
        errorMessage = nil
        defer { savingCorrection = false }
        do {
            _ = try await client.submitTranscription(
                messageId: current.id,
                text: transcriptCorrection,
                language: current.latestTranscription?.language,
                model: nil,
                expectedLatestTranscriptionId: transcriptCorrectionTranscriptionId
            )
            editingTranscript = false
            transcriptCorrectionTranscriptionId = nil
            statusMessage = "Corrected transcript saved. Translation and moderation will refresh."
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't save the corrected transcript."
        }
    }

    func saveTranslationCorrection(_ current: Message) async {
        savingCorrection = true
        errorMessage = nil
        defer { savingCorrection = false }
        do {
            let updated = try await client.submitTranslation(
                messageId: current.id,
                body: MessageTranslationRequest(
                    expectedTranscriptionId: translationCorrectionTranscriptionId,
                    expectedTranslationSha256: translationCorrectionSHA256,
                    translatedText: translationCorrection,
                    translatedLanguage: "en"
                )
            )
            message = (message ?? current).replacingLatestTranscription(updated)
            transcriptions = transcriptions.map { $0.id == updated.id ? updated : $0 }
            editingTranslation = false
            translationCorrectionTranscriptionId = nil
            translationCorrectionSHA256 = nil
            statusMessage = "Corrected translation saved."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't save the corrected translation."
        }
    }
}

#endif
