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
    private enum MessageFilter: String, CaseIterable, Identifiable {
        case all
        case pending
        case approved
        case rejected

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .pending: return "Review"
            case .approved: return "Approved"
            case .rejected: return "Rejected"
            }
        }

        func includes(_ message: Message) -> Bool {
            switch self {
            case .all: return true
            case .pending: return message.status == .pending
            case .approved: return message.status == .approved
            case .rejected: return message.status == .rejected
            }
        }

        var status: MessageStatus? {
            switch self {
            case .all: return nil
            case .pending: return .pending
            case .approved: return .approved
            case .rejected: return .rejected
            }
        }
    }

    @State private var messages: [Message] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var filter: MessageFilter = .all
    @State private var searchText = ""
    @State private var decidingMessageIds: Set<String> = []

    private let client: OperatorClient

    public init(client: OperatorClient = .shared) {
        self.client = client
    }

    public var body: some View {
        VStack(spacing: 0) {
            filterPicker

            Group {
                if loading && messages.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.Colors.background)
                } else if filteredMessages.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
        }
        .background(Theme.Colors.background)
        .searchable(text: $searchText, prompt: "Search transcripts")
        .task(id: filter) {
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
            ForEach(filteredMessages) { message in
                NavigationLink(value: message.id) {
                    MessageRow(
                        message: message,
                        isDeciding: decidingMessageIds.contains(message.id)
                    )
                }
                .operatorListRowBackground()
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if message.canBeDecided, message.status != .approved {
                        Button {
                            Task { await decide(message, as: .approve) }
                        } label: {
                            Label("Approve", systemImage: "checkmark.circle.fill")
                        }
                        .tint(Theme.Colors.success)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if message.canBeDecided, message.status != .rejected {
                        Button(role: .destructive) {
                            Task { await decide(message, as: .reject) }
                        } label: {
                            Label("Reject", systemImage: "xmark.circle.fill")
                        }
                    }
                }
            }
        }
        .operatorListStyle()
        .navigationDestination(for: String.self) { messageId in
            MessageDetailView(messageId: messageId, client: client) { updated in
                apply(updated)
            }
        }
    }

    private var filterPicker: some View {
        Picker("Filter", selection: $filter) {
            ForEach(MessageFilter.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Theme.Spacing.medium)
        .padding(.vertical, Theme.Spacing.small)
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
        if !searchText.isEmpty { return "No matching messages" }
        if filter != .all { return "No \(filter.title.lowercased()) messages" }
        return "No messages yet"
    }

    private var filteredMessages: [Message] {
        messages.filter { message in
            filter.includes(message) && message.matchesSearch(searchText)
        }
    }

    private func refresh() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            let list = try await client.fetchMessages(status: filter.status, limit: 100)
            messages = list.items
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Failed to load messages."
        }
    }

    private func decide(_ message: Message, as decision: MessageDecision) async {
        guard !decidingMessageIds.contains(message.id) else { return }
        decidingMessageIds.insert(message.id)
        errorMessage = nil
        defer { decidingMessageIds.remove(message.id) }
        do {
            let updated = try await client.decideMessage(id: message.id, decision: decision)
            apply(updated)
            await PendingMessagesStore.shared.refresh(using: client)
        } catch {
            let verb = decision == .approve ? "approve" : "reject"
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't \(verb) this message."
        }
    }

    private func apply(_ updated: Message) {
        guard filter.includes(updated) else {
            messages.removeAll { $0.id == updated.id }
            return
        }
        if let index = messages.firstIndex(where: { $0.id == updated.id }) {
            messages[index] = updated
        }
    }
}

struct MessageRow: View {
    let message: Message
    let isDeciding: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                MessageStatusBadge(status: message.status)
                Spacer()
                if isDeciding {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(message.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            if let displayText = message.bestDisplayText, !displayText.isEmpty {
                Text(displayText)
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
            } else if message.latestTranscription?.status == .pending {
                Text("Transcribing…")
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
                if let moderation = message.latestApplicableModeration,
                   let rec = moderation.recommendation {
                    Label("Suggested action: \(rec.displayName)", systemImage: "checklist")
                        .font(Theme.Fonts.caption.weight(.semibold))
                        .foregroundStyle(color(for: rec))
                        .padding(.horizontal, Theme.Spacing.small)
                        .padding(.vertical, 3)
                        .background(color(for: rec).opacity(0.12), in: Capsule())
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
        case .unknown: return Theme.Colors.textSecondary
        }
    }
}

private extension Message {
    var canBeDecided: Bool {
        status == .pending || status == .approved || status == .rejected
    }

    func matchesSearch(_ searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return latestTranscription?.text?.localizedCaseInsensitiveContains(query) == true
            || latestTranscription?.completedTranslation?.localizedCaseInsensitiveContains(query) == true
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
        case .unknown: return Theme.Colors.textSecondary
        }
    }
}

#endif
