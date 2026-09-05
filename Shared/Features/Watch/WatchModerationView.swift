//
//  WatchModerationView.swift
//  TelephoneBoothOperatorMobile
//
//  Lists messages awaiting moderation (status == .pending or
//  .received). Tap to view a compact detail page showing the
//  transcript and moderation summary. Lightweight by design — no
//  audio playback on the watch.
//

#if os(watchOS)

import SwiftUI

struct WatchModerationView: View {
    @State private var model = WatchMessageListModel()

    private let client: OperatorClient
    private let refreshRevision: Int

    init(
        client: OperatorClient = .shared,
        refreshRevision: Int = 0,
        model: WatchMessageListModel? = nil
    ) {
        self.client = client
        self.refreshRevision = refreshRevision
        _model = State(initialValue: model ?? WatchMessageListModel())
    }

    var body: some View {
        List {
            if let errorMessage = model.errorMessage {
                Section {
                    BannerView(message: errorMessage, kind: .error)
                    Button("Retry") { Task { await refresh() } }
                        .disabled(model.isRefreshing)
                }
            }
            if !model.hasLoaded && model.errorMessage == nil {
                ProgressView("Loading queue")
            }
            if model.messages.isEmpty && model.hasLoaded && model.errorMessage == nil {
                Section {
                    emptyState
                }
            }
            ForEach(model.messages) { message in
                NavigationLink(value: WatchModerationDestination.message(message.id)) {
                    WatchModerationRow(message: message)
                }
            }
            if model.hasLoaded {
                Text("Up to 25 pending and 25 received messages. Review older messages on iPhone.")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .refreshableIfAvailable {
            await refresh()
        }
        .autoRefresh(id: refreshRevision) {
            await refresh()
        }
        .watchMessageNotifications(model.notificationScope)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(Theme.Colors.success)
            Text("Queue empty.")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    func refresh() async {
        await model.refreshReview { status in
            try await client.fetchMessages(status: status, limit: 25)
        }
    }
}

enum WatchModerationDestination: Hashable {
    case message(String)
}

struct WatchModerationRow: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WatchMessageHeader(message: message)
            if let text = message.bestDisplayText {
                Text(text)
                    .font(.caption)
                    .lineLimit(2)
            } else {
                Text("No transcription")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }
}

struct WatchModerationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let messageId: String
    let client: OperatorClient
    var onMessageUpdate: (Message) -> Void = { _ in }

    @State private var model = WatchMessageDetailModel()
    @State private var proposedDecision: MessageDecision?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let errorMessage = model.errorMessage {
                    BannerView(message: errorMessage, kind: .error)
                    Button("Retry loading") { Task { await load() } }
                        .disabled(model.isLoading || model.isDeciding)
                }
                if let message = model.message {
                    detail(message)
                    decisionControls(message)
                } else if model.errorMessage == nil {
                    ProgressView("Loading message")
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Message")
        .autoRefresh {
            guard proposedDecision == nil else { return }
            await load()
        }
        .refreshableIfAvailable { await load() }
        .watchMessageNotifications(model.notificationScope)
        .confirmationDialog(
            proposedDecision == .approve ? "Approve this message?" : "Reject this message?",
            isPresented: Binding(
                get: { proposedDecision != nil },
                set: { if !$0 { proposedDecision = nil } }
            ),
            titleVisibility: .visible,
            presenting: proposedDecision
        ) { decision in
            Button(decision == .approve ? "Approve" : "Reject",
                   role: decision == .reject ? .destructive : nil) {
                Task { await decide(decision) }
            }
            Button("Cancel", role: .cancel) { proposedDecision = nil }
        } message: { decision in
            Text(decision == .approve
                 ? "Makes this recording available for playback at the booth."
                 : "Keeps the recording but excludes it from booth playback. This does not delete it.")
        }
    }

    private func detail(_ msg: Message) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WatchMessageHeader(message: msg)
            if let text = msg.latestTranscription?.text, !text.isEmpty {
                Text(text)
                    .font(.body)
            } else {
                Text("No transcription yet.")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            if let translation = msg.latestTranscription?.displayableTranslation {
                Text("English translation").font(.caption.weight(.semibold))
                Text(translation).font(.body)
            }
            if let reason = msg.latestApplicableModeration?.reasonSummary, !reason.isEmpty {
                Text("Reason: \(reason)")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.warning)
            }
            if let recommendation = msg.latestApplicableModeration?.recommendation {
                Text("Suggested: \(recommendation.displayName). Review before deciding.")
                    .font(.caption)
            }
            if let notes = msg.notes, !notes.isEmpty {
                Text("Notes: \(notes)").font(.caption)
            }
            Text("Audio playback and editing are available on iPhone.")
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    @ViewBuilder
    private func decisionControls(_ message: Message) -> some View {
        if message.status == .uploading || message.status == .received {
            Text("Decisions are available after transcription and moderation finish.")
                .font(.caption)
        } else if case .unknown = message.status {
            Text("This message status is not supported. Review on iPhone.")
                .font(.caption)
        } else {
            Button("Approve") { proposedDecision = .approve }
                .tint(Theme.Colors.success)
                .disabled(!model.canDecide(.approve))
            Button("Reject", role: .destructive) { proposedDecision = .reject }
                .disabled(!model.canDecide(.reject))
            if model.isDeciding {
                ProgressView("Saving decision")
            }
        }
    }

    private func load() async {
        guard proposedDecision == nil else { return }
        await model.load { try await client.fetchMessage(id: messageId) }
    }

    private func decide(_ decision: MessageDecision) async {
        proposedDecision = nil
        if let updated = await model.decide(decision, submit: {
            try await client.decideMessage(id: messageId, decision: decision)
        }) {
            onMessageUpdate(updated)
            dismiss()
            await PendingMessagesStore.shared.refresh(using: client)
        }
    }
}

@MainActor
@Observable
final class WatchMessageDetailModel {
    private(set) var message: Message?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private(set) var isDeciding = false
    private var requiresReload = false

    var notificationScope: DeliveredNotificationScope? {
        message.map { .messages(ids: [$0.id]) }
    }

    func canDecide(_ decision: MessageDecision) -> Bool {
        guard !isLoading, !isDeciding, !requiresReload, let message else { return false }
        switch message.status {
        case .pending: return true
        case .approved: return decision == .reject
        case .rejected: return decision == .approve
        case .uploading, .received, .unknown: return false
        }
    }

    func load(fetch: () async throws -> Message) async {
        guard !isLoading, !isDeciding else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await fetch()
            try Task.checkCancellation()
            message = loaded
            requiresReload = false
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            requiresReload = true
            errorMessage = "Couldn't refresh message. Reload before making a decision."
        }
    }

    func decide(
        _ decision: MessageDecision,
        submit: () async throws -> Message
    ) async -> Message? {
        guard canDecide(decision) else {
            if !isDeciding {
                errorMessage = "This decision is unavailable. Reload the message before trying again."
            }
            return nil
        }
        isDeciding = true
        errorMessage = nil
        defer { isDeciding = false }
        do {
            let updated = try await submit()
            message = updated
            return updated
        } catch {
            requiresReload = true
            errorMessage = "Couldn't save the decision. Reload to check the server before trying again."
            return nil
        }
    }
}

#endif
