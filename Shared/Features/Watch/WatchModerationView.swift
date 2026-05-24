//
//  WatchModerationView.swift
//  TelephoneBoothOperatorMobile
//
//  Lists messages awaiting moderation (status == .pending or
//  .received). Tap to view a compact detail page with a Re-run
//  moderation button. Lightweight by design — no audio playback
//  on the watch.
//

#if os(watchOS)

import SwiftUI

struct WatchModerationView: View {
    @State private var messages: [Message] = []
    @State private var errorMessage: String?
    @State private var isRefreshing = false

    private let client: OperatorClient

    init(client: OperatorClient = .shared) {
        self.client = client
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    BannerView(message: errorMessage, kind: .error)
                }
            }
            if messages.isEmpty && !isRefreshing && errorMessage == nil {
                Section {
                    emptyState
                }
            }
            ForEach(messages) { message in
                NavigationLink(value: WatchModerationDestination.message(message.id)) {
                    WatchModerationRow(message: message)
                }
            }
        }
        .navigationDestination(for: WatchModerationDestination.self) { dest in
            switch dest {
            case .message(let id):
                WatchModerationDetailView(messageId: id, client: client)
            }
        }
        .refreshableIfAvailable {
            await refresh()
        }
        .task {
            await refresh()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(Theme.Colors.success)
            Text("Queue empty.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    func refresh() async {
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }
        async let pendingTask: MessageList? = (
            try? await client.fetchMessages(status: .pending, since: nil, limit: 25)
        )
        async let receivedTask: MessageList? = (
            try? await client.fetchMessages(status: .received, since: nil, limit: 25)
        )
        let (pending, received) = await (pendingTask, receivedTask)
        if pending == nil && received == nil {
            if messages.isEmpty {
                errorMessage = "Couldn't load the moderation queue."
            }
            return
        }
        let combined = (pending?.items ?? []) + (received?.items ?? [])
        messages = combined.sorted { lhs, rhs in
            (lhs.receivedAt ?? lhs.createdAt) > (rhs.receivedAt ?? rhs.createdAt)
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
            HStack(spacing: 6) {
                Circle()
                    .fill(message.status.watchStatusColor)
                    .frame(width: 8, height: 8)
                Text(message.status.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(message.status.watchStatusColor)
                Spacer()
                Text(message.receivedAt ?? message.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let text = message.latestTranscription?.text, !text.isEmpty {
                Text(text)
                    .font(.caption)
                    .lineLimit(2)
            } else {
                Text("No transcription")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct WatchModerationDetailView: View {
    let messageId: String
    let client: OperatorClient

    @State private var message: Message?
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var isReRunning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let errorMessage {
                    BannerView(message: errorMessage, kind: .error)
                }
                if let infoMessage {
                    BannerView(message: infoMessage, kind: .info)
                }
                if let message {
                    detail(message)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Message")
        .task {
            await load()
        }
    }

    private func detail(_ msg: Message) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(msg.status.displayName)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(msg.receivedAt ?? msg.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let text = msg.latestTranscription?.text, !text.isEmpty {
                Text(text)
                    .font(.body)
            }
            if let reason = msg.latestModeration?.reasonSummary, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.warning)
            }
            Button {
                Task { await reRunModeration() }
            } label: {
                HStack {
                    if isReRunning {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Re-run moderation")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isReRunning)
        }
    }

    private func load() async {
        do {
            message = try await client.fetchMessage(id: messageId)
        } catch {
            errorMessage = "Couldn't load message."
        }
    }

    private func reRunModeration() async {
        isReRunning = true
        defer { isReRunning = false }
        errorMessage = nil
        infoMessage = nil
        do {
            _ = try await client.moderateMessage(id: messageId)
            infoMessage = "Moderation queued."
            await load()
        } catch {
            errorMessage = "Couldn't re-run moderation."
        }
    }
}

#endif
