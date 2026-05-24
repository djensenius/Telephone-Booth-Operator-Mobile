//
//  MessageListView.swift
//  TelephoneBoothOperatorMobile
//
//  Operator-facing browser of recorded messages. Filterable by status,
//  drills into MessageDetailView for transcripts + audio playback.
//

#if !os(watchOS) && !os(tvOS)

import SwiftUI

public struct MessageListView: View {
    @State private var messages: [Message] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var statusFilter: MessageStatus?

    private let client: OperatorClient

    public init(client: OperatorClient = .shared) {
        self.client = client
    }

    public var body: some View {
        Group {
            if loading && messages.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.background)
            } else if messages.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Theme.Colors.background)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                statusMenu
            }
        }
        .task(id: statusFilter) {
            await refresh()
        }
        .refreshableIfAvailable {
            await refresh()
        }
    }

    private var list: some View {
        List {
            if let errorMessage {
                BannerView(message: errorMessage, kind: .error)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(messages) { message in
                NavigationLink(value: message.id) {
                    MessageRow(message: message)
                }
                .listRowBackground(Theme.Colors.secondaryBackground)
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: String.self) { messageId in
            MessageDetailView(messageId: messageId, client: client)
        }
    }

    private var statusMenu: some View {
        Menu {
            Button("All") { statusFilter = nil }
            Divider()
            ForEach(MessageStatus.allCases, id: \.self) { status in
                Button(status.displayName) { statusFilter = status }
            }
        } label: {
            Label(statusFilter?.displayName ?? "All", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.medium) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(emptyTitle)
                .font(Theme.Fonts.bodyLarge)
                .foregroundStyle(Theme.Colors.textPrimary)
            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Theme.Spacing.extraLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if errorMessage != nil { return "Couldn't load messages" }
        if let statusFilter { return "No \(statusFilter.displayName.lowercased()) messages" }
        return "No messages yet"
    }

    private func refresh() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            let list = try await client.fetchMessages(status: statusFilter, limit: 100)
            messages = list.items
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Failed to load messages."
        }
    }
}

struct MessageRow: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                MessageStatusBadge(status: message.status)
                Spacer()
                Text(message.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            if let transcript = message.latestTranscription?.text, !transcript.isEmpty {
                Text(transcript)
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
            } else if message.latestTranscription?.status == .pending {
                Text("Transcribing…")
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .italic()
            } else {
                Text("No transcript yet")
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .italic()
            }
            HStack(spacing: Theme.Spacing.medium) {
                if let duration = DurationFormatter.shortString(milliseconds: message.audio.durationMs) {
                    Label(duration, systemImage: "waveform")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                if let moderation = message.latestModeration, let rec = moderation.recommendation {
                    Label(rec.displayName, systemImage: "shield.lefthalf.filled")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(color(for: rec))
                }
            }
        }
        .padding(.vertical, Theme.Spacing.small)
    }

    private func color(for rec: ModerationRecommendation) -> Color {
        switch rec {
        case .approve: return Theme.Colors.success
        case .review: return Theme.Colors.warning
        case .reject: return Theme.Colors.error
        }
    }
}

struct MessageStatusBadge: View {
    let status: MessageStatus

    var body: some View {
        Text(status.displayName)
            .font(Theme.Fonts.caption.weight(.semibold))
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.opacity(0.18))
            )
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .uploading: return Theme.Colors.info
        case .received, .pending: return Theme.Colors.warning
        case .approved: return Theme.Colors.success
        case .rejected: return Theme.Colors.error
        }
    }
}

#endif
