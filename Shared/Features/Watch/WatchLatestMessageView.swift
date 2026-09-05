//
//  WatchLatestMessageView.swift
//  TelephoneBoothOperatorMobile
//
//  Shows the single most recent message: status pill, time, and
//  the latest transcription excerpt if available. Optimised for
//  the small watch screen — one tappable card.
//

#if os(watchOS)

import SwiftUI

struct WatchLatestMessageView: View {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let errorMessage = model.errorMessage {
                    BannerView(message: errorMessage, kind: .error)
                    Button("Retry") { Task { await refresh() } }
                        .disabled(model.isRefreshing)
                }
                if let message = model.messages.first {
                    NavigationLink(value: WatchModerationDestination.message(message.id)) {
                        messageCard(message)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the full transcript and moderation actions")
                } else if !model.hasLoaded && model.errorMessage == nil {
                    ProgressView("Loading latest message")
                } else if model.hasLoaded && model.errorMessage == nil {
                    emptyState
                }
            }
            .padding(.horizontal, 4)
        }
        .refreshableIfAvailable {
            await refresh()
        }
        .autoRefresh(id: refreshRevision) {
            await refresh()
        }
        .watchMessageNotifications(model.notificationScope)
    }

    private func messageCard(_ msg: Message) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(msg.status.watchStatusColor)
                    .frame(width: 8, height: 8)
                Text(msg.status.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(msg.status.watchStatusColor)
                Spacer()
                Text(msg.receivedAt ?? msg.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            if let text = msg.bestDisplayText {
                Text(text)
                    .font(.body)
                    .lineLimit(8)
            } else {
                Text("No transcription yet.")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            if let reason = msg.latestApplicableModeration?.reasonSummary, !reason.isEmpty {
                Text("Reason: \(reason)")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.warning)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Colors.elevatedBackground)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title3)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("No messages yet.")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    func refresh() async {
        await model.refresh(failureMessage: "Couldn't refresh the latest message. Displayed data may be out of date.") {
            try await client.fetchMessages(limit: 1).items
        }
    }
}

@MainActor
@Observable
final class WatchMessageListModel {
    private(set) var messages: [Message] = []
    private(set) var errorMessage: String?
    private(set) var isRefreshing = false
    private(set) var hasLoaded = false
    private var mutationRevision = 0

    var notificationScope: DeliveredNotificationScope? {
        guard hasLoaded else { return nil }
        return .messages(ids: Set(messages.map(\.id)))
    }

    func refreshReview(
        fetch: @escaping @MainActor @Sendable (MessageStatus) async throws -> MessageList
    ) async {
        await refresh(failureMessage: "Couldn't refresh the queue. Displayed messages may be out of date.") {
            async let pending = fetch(.pending)
            async let received = fetch(.received)
            let lists = try await (pending, received)
            return Self.reviewMessages(pending: lists.0.items, received: lists.1.items)
        }
    }

    func refresh(
        failureMessage: String,
        fetch: () async throws -> [Message]
    ) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let revision = mutationRevision
        defer { isRefreshing = false }
        do {
            let loaded = try await fetch()
            try Task.checkCancellation()
            guard revision == mutationRevision else { return }
            messages = loaded
            hasLoaded = true
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            errorMessage = failureMessage
        }
    }

    func applyDecision(_ updated: Message, filter: MessageListFilter) {
        mutationRevision += 1
        messages = messages.compactMap { existing in
            guard existing.id == updated.id else { return existing }
            return filter.includes(updated.status) ? updated : nil
        }
    }

    static func reviewMessages(pending: [Message], received: [Message]) -> [Message] {
        // Prefer pending when a message moves between the two server queries.
        var byID: [String: Message] = [:]
        for message in received + pending where MessageListFilter.review.includes(message.status) {
            byID[message.id] = message
        }
        return byID.values.sorted {
            let lhsDate = $0.receivedAt ?? $0.createdAt
            let rhsDate = $1.receivedAt ?? $1.createdAt
            return lhsDate == rhsDate ? $0.id > $1.id : lhsDate > rhsDate
        }
    }
}

#endif
