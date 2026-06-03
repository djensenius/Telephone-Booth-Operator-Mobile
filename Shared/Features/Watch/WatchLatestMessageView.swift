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
    @State private var message: Message?
    @State private var errorMessage: String?
    @State private var isRefreshing = false

    private let client: OperatorClient

    init(client: OperatorClient = .shared) {
        self.client = client
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let errorMessage {
                    BannerView(message: errorMessage, kind: .error)
                }
                if let message {
                    messageCard(message)
                } else if !isRefreshing {
                    emptyState
                }
            }
            .padding(.horizontal, 4)
        }
        .refreshableIfAvailable {
            await refresh()
        }
        .task {
            await refresh()
        }
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
            if let text = msg.latestTranscription?.text, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .lineLimit(8)
            } else {
                Text("No transcription yet.")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            if let reason = msg.latestModeration?.reasonSummary, !reason.isEmpty {
                Text(reason)
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
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }
        do {
            let list = try await client.fetchMessages(status: nil, since: nil, limit: 1)
            message = list.items.first
        } catch {
            if message == nil {
                errorMessage = "Couldn't load the latest message."
            }
        }
    }
}

#endif
