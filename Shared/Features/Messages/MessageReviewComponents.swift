//
//  MessageReviewComponents.swift
//  TelephoneBoothOperatorMobile
//

#if !os(watchOS) && !os(tvOS)

import SwiftUI

struct TextCorrectionControls: View {
    @Binding var isEditing: Bool
    @Binding var text: String

    let originalText: String
    let editTitle: String
    let saveTitle: String
    let disabled: Bool
    let onEdit: () -> Void
    let save: () async -> Void

    var body: some View {
        if isEditing {
            TextField(editTitle, text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...8)
                .disabled(disabled)
            HStack {
                Button(saveTitle) {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(disabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel") {
                    text = originalText
                    isEditing = false
                }
                .buttonStyle(.bordered)
                .disabled(disabled)
            }
        } else {
            Button(editTitle) {
                onEdit()
                text = originalText
                isEditing = true
            }
            .buttonStyle(.bordered)
            .disabled(disabled)
        }
    }
}

struct TranscriptionRow: View {
    let transcription: Transcription
    let emphasized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            header
            transcriptionContent
            translationContent
        }
    }

    private var header: some View {
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
    }

    @ViewBuilder
    private var transcriptionContent: some View {
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

    @ViewBuilder
    private var translationContent: some View {
        if !emphasized, let translation = transcription.displayableTranslation {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                Text("English")
                    .font(Theme.Fonts.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(translation)
                    .font(emphasized ? Theme.Fonts.bodyMedium : Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .textSelection(.enabled)
            }
            .padding(.top, Theme.Spacing.small)
        } else if !emphasized,
                  transcription.shouldDisplayTranslation,
                  transcription.translationStatus == .failed {
            Label(
                transcription.translationError ?? "Translation failed.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(Theme.Fonts.bodySmall)
            .foregroundStyle(Theme.Colors.error)
        }
    }
}

struct MessageQuestionMetadata {
    var resolvedId: String?
    var prompt: String?
    var isLoading = false
}

struct MessageMetadataCard: View {
    let message: Message
    let questionMetadata: MessageQuestionMetadata

    var body: some View {
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
            if message.questionId != nil {
                StatRow(
                    label: "Question",
                    value: questionMetadata.prompt
                        ?? (questionMetadata.isLoading ? "Loading…" : "Question unavailable")
                )
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
}

#if canImport(Speech) && canImport(FoundationModels)
extension View {
    @ViewBuilder
    func automaticMessageProcessing(client: OperatorClient) -> some View {
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            modifier(AutomaticMessageProcessingModifier(client: client))
        } else {
            self
        }
    }
}

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
private struct AutomaticMessageProcessingModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator: AutomaticMessageProcessingCoordinator

    init(client: OperatorClient) {
        _coordinator = State(initialValue: AutomaticMessageProcessingCoordinator(client: client))
    }

    func body(content: Content) -> some View {
        placedStatus(content)
            .task {
                coordinator.setActive(scenePhase == .active)
            }
            .onChange(of: scenePhase) {
                coordinator.setActive(scenePhase == .active)
            }
            .onDisappear {
                coordinator.setActive(false)
            }
    }

    @ViewBuilder
    private func placedStatus(_ content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: coordinator.shouldPresentStatus) {
                MessageProcessingQueueStatus(coordinator: coordinator)
                    .padding(.horizontal, Theme.Spacing.medium)
                    .padding(.vertical, Theme.Spacing.small)
            }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if coordinator.shouldPresentStatus {
                    MessageProcessingQueueStatus(coordinator: coordinator)
                        .padding(.horizontal, Theme.Spacing.medium)
                        .padding(.vertical, Theme.Spacing.small)
                        .frame(maxWidth: 520)
                        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cornerRadius))
                        .padding(.horizontal, Theme.Spacing.medium)
                        .padding(.bottom, Theme.Spacing.small)
                }
            }
        }
        #else
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if coordinator.shouldPresentStatus {
                MessageProcessingQueueStatus(coordinator: coordinator)
                    .padding(.horizontal, Theme.Spacing.medium)
                    .padding(.vertical, Theme.Spacing.small)
                    .frame(maxWidth: 520)
                    .glassCardBackground()
                    .padding(.horizontal, Theme.Spacing.medium)
                    .padding(.bottom, Theme.Spacing.small)
            }
        }
        #endif
    }
}

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
private struct MessageProcessingQueueStatus: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var accessoryPlacement
    let coordinator: AutomaticMessageProcessingCoordinator

    var body: some View {
        let summary = coordinator.summary
        statusContent(summary)
    }

    private func statusContent(_ summary: MessageProcessingSummary?) -> some View {
        HStack(spacing: Theme.Spacing.small) {
            statusIndicator
            if accessoryPlacement == .inline {
                Text(compactStatusText(summary))
                    .font(Theme.Fonts.caption.weight(.semibold))
                    .foregroundStyle(
                        coordinator.canRetry ? Theme.Colors.error : Theme.Colors.textPrimary
                    )
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Messages · \(scopeText(summary))")
                        .font(Theme.Fonts.caption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(coordinator.status.text)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(
                            coordinator.canRetry ? Theme.Colors.error : Theme.Colors.textSecondary
                        )
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if coordinator.canRetry {
                retryButton(compact: accessoryPlacement == .inline)
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if coordinator.isProcessing {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: coordinator.canRetry
                ? "exclamationmark.triangle.fill"
                : "tray.and.arrow.down.fill")
            .foregroundStyle(coordinator.canRetry ? Theme.Colors.error : Theme.Colors.accent)
        }
    }

    private func retryButton(compact: Bool) -> some View {
        Button {
            coordinator.retry()
        } label: {
            if compact {
                Image(systemName: "arrow.clockwise")
                    .accessibilityLabel("Retry message processing")
            } else {
                Label("Retry", systemImage: "arrow.clockwise")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.Colors.accent)
        .font(Theme.Fonts.caption.weight(.semibold))
        .frame(minWidth: 44, minHeight: 44)
    }

    private func compactStatusText(_ summary: MessageProcessingSummary?) -> String {
        if coordinator.canRetry { return "Processing failed" }
        if coordinator.isProcessing { return coordinator.status.text }
        return scopeText(summary)
    }

    private func scopeText(_ summary: MessageProcessingSummary?) -> String {
        guard let summary else { return "checking queue" }
        let remaining = summary.queued + summary.leased
        return "\(remaining) remaining"
    }
}
#endif

#endif
