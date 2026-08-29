// swiftlint:disable file_length
//
//  MessageDetailView.swift
//  TelephoneBoothOperatorMobile
//
//  Single-message screen with playback, transcript history, moderation,
//  and the human approve/reject decision.
//

#if !os(watchOS) && !os(tvOS)
import SwiftUI

private enum MessageInstallationLookup: Sendable {
    case notRequired
    case available(currentInstallationId: String?)
    case unavailable
}

public struct MessageDetailView: View {
    @Environment(\.dismiss) private var dismiss
    public let messageId: String
    @State private var message: Message?
    @State private var transcriptions: [Transcription] = []
    @State private var loading = false
    @State private var questionMetadata = MessageQuestionMetadata()
    @State private var deciding = false
    @State private var decisionNotes = ""
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var showAllTranscripts = false
    @State private var sourceLanguage = ""
    @State private var onDeviceProcessor = OnDeviceMessageProcessor()
    @State private var editingTranscript = false
    @State private var transcriptCorrection = ""
    @State private var transcriptCorrectionSnapshot: Transcription?
    @State private var editingTranslation = false
    @State private var translationCorrection = ""
    @State private var translationCorrectionTranscriptionId: String?
    @State private var translationCorrectionSHA256: String?
    @State private var savingCorrection = false
    @State private var usesDemoData = false
    @State private var deleting = false
    @State private var showDeleteConfirmation = false
    @State private var notificationScope: DeliveredNotificationScope?
    @State private var readOnlyReason: String?
    @State private var installationAccessRevision: UInt = 0
    @State private var latestInstallationUpdate: Installation?
    private let client: OperatorClient
    private let socket: StatusSocket
    private let enforceInstallationReadOnly: Bool
    private let onMessageUpdate: (Message) -> Void
    private let shouldDismissAfterDecision: (Message) -> Bool
    private let onMessageDelete: (String) -> Void
    public init(
        messageId: String,
        client: OperatorClient = .shared,
        readOnlyReason: String? = nil,
        enforceInstallationReadOnly: Bool = false,
        socket: StatusSocket? = nil,
        onMessageUpdate: @escaping (Message) -> Void = { _ in },
        shouldDismissAfterDecision: @escaping (Message) -> Bool = { _ in false },
        onMessageDelete: @escaping (String) -> Void = { _ in }
    ) {
        self.messageId = messageId
        self.client = client
        self.socket = socket ?? (client.demoMode ? .demo : .shared)
        self.enforceInstallationReadOnly = enforceInstallationReadOnly
        self.onMessageUpdate = onMessageUpdate
        self.shouldDismissAfterDecision = shouldDismissAfterDecision
        self.onMessageDelete = onMessageDelete
        _readOnlyReason = State(initialValue: readOnlyReason)
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
                if let readOnlyReason {
                    BannerView(message: readOnlyReason, kind: .info)
                }
                if let message {
                    audioCard(message)
                    if readOnlyReason == nil {
                        appleIntelligenceCard(message)
                    }
                    if message.latestTranscription != nil || !transcriptions.isEmpty {
                        transcriptCard(message)
                    }
                    if message.latestTranscription?.shouldDisplayTranslation == true {
                        translationCard(message)
                    }
                    if message.latestApplicableModeration != nil {
                        moderationCard(message)
                    }
                    if readOnlyReason == nil {
                        decisionCard(message)
                    } else {
                        readOnlyDecisionCard(message)
                    }
                    MessageMetadataCard(
                        message: message,
                        questionMetadata: questionMetadata
                    )
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
        .autoRefresh {
            usesDemoData = await client.usesDemoData
            await load()
        }
        .task(id: sourceLanguage) {
            await onDeviceProcessor.refreshAvailability(sourceLanguage: sourceLanguage)
        }
        .task {
            await watchInstallationUpdates()
        }
        .notificationVisibilityScope(notificationScope)
        .refreshableIfAvailable {
            await load()
        }
        .confirmationDialog(
            "Permanently delete this recording?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete recording", role: .destructive) {
                Task { await deleteMessage() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Reject keeps the recording; delete removes it permanently.")
        }
    }
    private func appleIntelligenceCard(_ message: Message) -> some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                SectionHeader(text: "Transcribe & Review")
                Text(
                    "Creates a fresh transcript and suggested action on this device, "
                        + "translating non-English messages before review."
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
                            Label("Transcribe & Review", systemImage: "waveform")
                                .font(Theme.Fonts.bodySmall.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.Colors.accent)
                        .disabled(onDeviceProcessor.isRunning)
                    }
                } else if onDeviceProcessor.stage != .checkingAvailability {
                    Text("Check the BCP-47 source language (for example, fr-CA) and device support.")
                        .font(Theme.Fonts.bodySmall)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                if !usesDemoData, onDeviceProcessor.canRetryPersistence {
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
                if let translation = transcription.displayableTranslation {
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
                        disabled: readOnlyReason != nil
                            || usesDemoData
                            || onDeviceProcessor.isRunning
                            || savingCorrection,
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
                        disabled: readOnlyReason != nil
                            || usesDemoData
                            || onDeviceProcessor.isRunning
                            || savingCorrection,
                        onEdit: {
                            transcriptCorrectionSnapshot = latest
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
                    Label("Suggested action: \(rec.displayName)", systemImage: "checklist")
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
                    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                        Text("Reason")
                            .font(Theme.Fonts.caption.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(reason)
                            .font(Theme.Fonts.bodySmall)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
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
                    Image(systemName: "checklist")
                        .foregroundStyle(recommendationColor(rec))
                    Text("Suggested action: \(rec.displayName). Review the message before deciding.")
                        .font(Theme.Fonts.bodySmall)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            if message.recommendsPermanentDelete {
                Label(
                    "Silence was classified as a likely hangup. Delete is recommended.",
                    systemImage: "trash.fill"
                )
                .font(Theme.Fonts.bodySmall.weight(.semibold))
                .foregroundStyle(Theme.Colors.error)
            } else if message.reviewClassification == .unclear {
                Label(
                    "Silence needs human review before it is removed.",
                    systemImage: "questionmark.circle"
                )
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.warning)
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
                HStack(spacing: Theme.Spacing.extraLarge) {
                    decisionButton(.approve, isCurrent: message.status == .approved)
                    decisionButton(.reject, isCurrent: message.status == .rejected)
                }
                if deciding {
                    ProgressView()
                }
            case .unknown:
                EmptyView()
            }
            Button {
                showDeleteConfirmation = true
            } label: {
                Label(
                    message.recommendsPermanentDelete ? "Delete recommended recording" : "Delete recording",
                    systemImage: "trash.fill"
                )
                .font(Theme.Fonts.bodySmall.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.error)
            .disabled(deciding || deleting)
            .padding(.top, Theme.Spacing.small)
            if deleting {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
    }
    private func readOnlyDecisionCard(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(text: "Decision")
            if message.status == .approved || message.status == .rejected {
                StatRow(label: "Current decision", value: message.status.displayName)
            }
            Text(readOnlyReason ?? "This recording is read-only.")
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
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
            .controlSize(.large)
            .tint(tint)
            .disabled(deciding || deleting)
        } else {
            Button {
                Task { await decide(decision) }
            } label: {
                Label(title, systemImage: icon)
                    .font(Theme.Fonts.bodySmall.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(tint)
            .disabled(deciding || deleting)
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
    private func load() async {
        guard !loading else { return }
        loading = true
        errorMessage = nil
        defer { loading = false }
        let accessRevision = installationAccessRevision
        async let messageTask: Message? = (try? await client.fetchMessage(id: messageId))
        async let listTask: TranscriptionList? = (try? await client.fetchTranscriptions(messageId: messageId))
        async let installationTask = resolveInstallationAccess()
        let (newMessage, newList, installationLookup) = await (
            messageTask,
            listTask,
            installationTask
        )
        if let newMessage {
            apply(
                installationLookup,
                to: newMessage,
                requestRevision: accessRevision
            )
            if let latestInstallationUpdate,
               accessRevision != installationAccessRevision {
                apply(latestInstallationUpdate, to: newMessage)
            }
            message = newMessage
            onMessageUpdate(newMessage)
            let scope = DeliveredNotificationScope.messages(ids: [messageId])
            notificationScope = scope
            await NotificationManager.shared.clearDeliveredNotifications(in: scope)
            if sourceLanguage.isEmpty {
                sourceLanguage = newMessage.latestTranscription?.language ?? ""
            }
            await loadQuestionPrompt(for: newMessage)
        } else if message == nil {
            errorMessage = "Couldn't load this message."
        }
        if let newList {
            transcriptions = newList.items
        }
    }
    private func loadQuestionPrompt(for message: Message) async {
        guard let questionId = message.questionId else {
            questionMetadata = MessageQuestionMetadata()
            return
        }
        guard questionMetadata.resolvedId != questionId else { return }
        questionMetadata = MessageQuestionMetadata(isLoading: true)
        defer { questionMetadata.isLoading = false }
        do {
            let question = try await client.fetchQuestion(id: questionId)
            questionMetadata = MessageQuestionMetadata(
                resolvedId: questionId,
                prompt: question?.prompt
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't load the question."
        }
    }
    func decide(_ decision: MessageDecision) async {
        guard requireWritable() else { return }
        guard !deciding, !deleting else { return }
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
            onMessageUpdate(updated)
            decisionNotes = ""
            if shouldDismissAfterDecision(updated) {
                dismiss()
            }
            await PendingMessagesStore.shared.refresh(using: client)
        } catch {
            let verb = decision == .approve ? "approve" : "reject"
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't \(verb) this message."
        }
    }
    func deleteMessage() async {
        guard requireWritable() else { return }
        guard !deleting, !deciding else { return }
        deleting = true
        errorMessage = nil
        defer { deleting = false }
        do {
            try await client.deleteMessage(id: messageId)
            onMessageDelete(messageId)
            await PendingMessagesStore.shared.refresh(using: client)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't delete this recording."
        }
    }
    func saveTranscriptCorrection(_ current: Message) async {
        guard requireWritable() else { return }
        guard !savingCorrection else { return }
        savingCorrection = true
        errorMessage = nil
        defer { savingCorrection = false }
        do {
            let updated = try await client.submitTranscription(
                messageId: current.id,
                text: transcriptCorrection,
                language: current.latestTranscription?.language,
                model: nil,
                processDownstream: false,
                expectedLatestTranscription: transcriptCorrectionSnapshot
            )
            let updatedMessage = (message ?? current).replacingLatestTranscription(updated)
            message = updatedMessage
            onMessageUpdate(updatedMessage)
            transcriptions = [updated] + transcriptions.filter { $0.id != updated.id }
            editingTranscript = false
            transcriptCorrectionSnapshot = nil
            onDeviceProcessor.reset()
            statusMessage = "Corrected transcript saved. Translation and moderation were cleared."
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't save the corrected transcript."
        }
    }
    func saveTranslationCorrection(_ current: Message) async {
        guard requireWritable() else { return }
        guard !savingCorrection else { return }
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
            if let message { onMessageUpdate(message) }
            transcriptions = transcriptions.map { $0.id == updated.id ? updated : $0 }
            editingTranslation = false
            translationCorrectionTranscriptionId = nil
            translationCorrectionSHA256 = nil
            onDeviceProcessor.reset()
            statusMessage = "Corrected translation saved."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't save the corrected translation."
        }
    }
    private func requireWritable() -> Bool {
        guard let readOnlyReason else { return true }
        errorMessage = readOnlyReason
        return false
    }
    private func resolveInstallationAccess() async -> MessageInstallationLookup {
        guard enforceInstallationReadOnly else { return .notRequired }
        do {
            let current = try await client.fetchCurrentInstallation()
            return .available(currentInstallationId: current?.id)
        } catch is CancellationError {
            return .notRequired
        } catch {
            return .unavailable
        }
    }
    private func apply(
        _ lookup: MessageInstallationLookup,
        to message: Message,
        requestRevision: UInt
    ) {
        guard enforceInstallationReadOnly,
              requestRevision == installationAccessRevision else {
            return
        }
        switch lookup {
        case .notRequired:
            break
        case .available(let currentInstallationId):
            readOnlyReason = MessageActionAccess.installationScoped(
                messageInstallationId: message.installationId,
                currentInstallationId: currentInstallationId
            ).readOnlyReason
        case .unavailable:
            readOnlyReason = MessageActionAccess.readOnlyUnavailable.readOnlyReason
        }
    }
    private func watchInstallationUpdates() async {
        guard enforceInstallationReadOnly else { return }
        while !Task.isCancelled {
            do {
                for try await envelope in socket.subscribe() {
                    guard !Task.isCancelled else { return }
                    if case .installation(let installation) = envelope {
                        apply(installation)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                // The periodic detail refresh remains the fallback while the
                // live connection retries.
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(2))
        }
    }
    private func apply(_ installation: Installation) {
        installationAccessRevision &+= 1
        latestInstallationUpdate = installation
        guard let message else { return }
        apply(installation, to: message)
    }
    private func apply(_ installation: Installation, to message: Message) {
        if installation.isActive, installation.endedAt == nil {
            readOnlyReason = MessageActionAccess.installationScoped(
                messageInstallationId: message.installationId,
                currentInstallationId: installation.id
            ).readOnlyReason
        } else if installation.id == message.installationId {
            readOnlyReason = MessageActionAccess.readOnlyArchived.readOnlyReason
        }
    }
}

#endif
