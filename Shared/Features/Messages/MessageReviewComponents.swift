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
        if !emphasized, let translation = transcription.completedTranslation {
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
        } else if !emphasized, transcription.translationStatus == .failed {
            Label(
                transcription.translationError ?? "Translation failed.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(Theme.Fonts.bodySmall)
            .foregroundStyle(Theme.Colors.error)
        }
    }
}

struct MessageMetadataCard: View {
    let message: Message
    let questionPrompt: String?
    let loadingQuestion: Bool

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
                    value: questionPrompt ?? (loadingQuestion ? "Loading…" : "Question unavailable")
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

#endif
