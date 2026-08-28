// swiftlint:disable file_length
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
    @State private var filter: MessageListFilter
    @State private var searchText = ""
    @State private var decidingMessageIds: Set<String> = []
    @State private var deletingMessageIds: Set<String> = []
    @State private var deleteCandidate: Message?
    @State private var refreshGeneration = 0
    @State private var notificationScope: DeliveredNotificationScope?
    #if os(macOS)
    @State private var hoveredMessageId: String?
    #endif
    private let client: OperatorClient
    private let socket: StatusSocket
    private let routeFilter: MessageListFilter
    private let routeRevision: UInt

    public init(
        client: OperatorClient = .shared,
        socket: StatusSocket? = nil,
        routeFilter: MessageListFilter = .all,
        routeRevision: UInt = 0
    ) {
        self.client = client
        self.socket = socket ?? (client.demoMode ? .demo : .shared)
        self.routeFilter = routeFilter
        self.routeRevision = routeRevision
        _filter = State(initialValue: routeFilter)
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
        .navigationDestination(for: String.self) { messageId in
            MessageDetailView(
                messageId: messageId,
                client: client,
                onMessageUpdate: { updated in apply(updated) },
                shouldDismissAfterDecision: { updated in
                    filter.shouldDismissDetail(afterDecisionTo: updated.status)
                },
                onMessageDelete: { id in messages.removeAll { $0.id == id } }
            )
        }
        .autoRefresh(id: filter) {
            await refresh()
        }
        .onChange(of: routeRevision) {
            filter = routeFilter
        }
        .task {
            await watchMessageUpdates()
        }
        .notificationVisibilityScope(notificationScope)
        .refreshableIfAvailable {
            await refresh()
        }
        .confirmationDialog(
            "Permanently delete this recording?",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete recording", role: .destructive) {
                if let deleteCandidate {
                    Task { await delete(deleteCandidate) }
                }
            }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        } message: {
            Text("This cannot be undone. Reject keeps the recording; delete removes it permanently.")
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
                        isDeciding: isPerformingAction(on: message)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                #if os(macOS)
                .overlay(alignment: .trailing) {
                    if hoveredMessageId == message.id {
                        quickActions(for: message)
                            .padding(.horizontal, Theme.Spacing.small)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: .capsule)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .onHover { isHovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        hoveredMessageId = isHovering ? message.id : nil
                    }
                }
                #endif
                .operatorListRowBackground()
                .contextMenu {
                    actionButtons(for: message)
                }
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
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if message.canBeDecided, message.status != .rejected {
                        Button(role: .destructive) {
                            Task { await decide(message, as: .reject) }
                        } label: {
                            Label("Reject", systemImage: "xmark.circle.fill")
                        }
                    }
                    Button(role: .destructive) {
                        deleteCandidate = message
                    } label: {
                        Label("Delete permanently", systemImage: "trash.fill")
                    }
                    .tint(message.recommendsPermanentDelete ? Theme.Colors.error : Theme.Colors.textSecondary)
                }
            }
        }
        .operatorListStyle()
    }

    #if os(macOS)
    private func quickActions(for message: Message) -> some View {
        HStack(spacing: Theme.Spacing.small) {
            if message.canBeDecided, message.status != .approved {
                Button {
                    Task { await decide(message, as: .approve) }
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.Colors.success)
                .help("Approve")
            }
            if message.canBeDecided, message.status != .rejected {
                Button {
                    Task { await decide(message, as: .reject) }
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.Colors.error)
                .help("Reject")
            }
            Button {
                deleteCandidate = message
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(
                message.recommendsPermanentDelete
                    ? Theme.Colors.error
                    : Theme.Colors.textSecondary
            )
            .help("Delete permanently")
        }
        .disabled(isPerformingAction(on: message))
    }
    #endif

    @ViewBuilder
    private func actionButtons(for message: Message) -> some View {
        if message.canBeDecided, message.status != .approved {
            Button {
                Task { await decide(message, as: .approve) }
            } label: {
                Label("Approve", systemImage: "checkmark.circle")
            }
        }
        if message.canBeDecided, message.status != .rejected {
            Button {
                Task { await decide(message, as: .reject) }
            } label: {
                Label("Reject", systemImage: "xmark.circle")
            }
        }
        Button(role: .destructive) {
            deleteCandidate = message
        } label: {
            Label("Delete permanently", systemImage: "trash")
        }
    }

    private func isPerformingAction(on message: Message) -> Bool {
        decidingMessageIds.contains(message.id) || deletingMessageIds.contains(message.id)
    }
    private var filterPicker: some View {
        Picker("Filter", selection: $filter) {
            ForEach(MessageListFilter.allCases) { option in
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
            filter.includes(message.status) && message.matchesSearch(searchText)
        }
    }

    private func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        notificationScope = nil
        loading = true
        errorMessage = nil
        defer {
            if generation == refreshGeneration {
                loading = false
            }
        }
        do {
            let list = try await fetchMessages(for: filter)
            guard !Task.isCancelled, generation == refreshGeneration else { return }
            messages = list
            let scope: DeliveredNotificationScope =
                filter == .all || filter == .review
                    ? .allMessages
                    : .messages(ids: Set(list.map(\.id)))
            notificationScope = scope
            await NotificationManager.shared.clearDeliveredNotifications(in: scope)
        } catch {
            guard !Task.isCancelled, generation == refreshGeneration else { return }
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

    private func delete(_ message: Message) async {
        guard !deletingMessageIds.contains(message.id) else { return }
        deleteCandidate = nil
        deletingMessageIds.insert(message.id)
        errorMessage = nil
        defer { deletingMessageIds.remove(message.id) }
        do {
            try await client.deleteMessage(id: message.id)
            messages.removeAll { $0.id == message.id }
            await PendingMessagesStore.shared.refresh(using: client)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't delete this recording."
        }
    }

    private func apply(_ updated: Message) {
        messages.applyLiveUpdate(updated, isIncluded: filter.includes(updated.status))
    }

    private func fetchMessages(for filter: MessageListFilter) async throws -> [Message] {
        guard let statuses = filter.requestedStatuses else {
            return try await client.fetchMessages(limit: 100).items
        }
        guard statuses.count == 2 else {
            return try await client.fetchMessages(status: statuses[0], limit: 100).items
        }

        async let received = client.fetchMessages(status: statuses[0], limit: 100)
        async let pending = client.fetchMessages(status: statuses[1], limit: 100)
        let lists = try await [received, pending]
        var messagesByID: [String: Message] = [:]
        for message in lists.flatMap(\.items) {
            messagesByID[message.id] = message
        }
        return messagesByID.values.sorted { $0.createdAt > $1.createdAt }
    }

    private func watchMessageUpdates() async {
        while !Task.isCancelled {
            do {
                for try await envelope in socket.subscribe() {
                    guard !Task.isCancelled else { return }
                    if case .message(let message) = envelope {
                        apply(message)
                        if filter.includes(message.status) {
                            let descriptor = NotificationManager.deliveredNotificationDescriptor(
                                categoryIdentifier: "BOOTH_MESSAGE",
                                userInfo: ["messageId": message.id]
                            )
                            if NotificationManager.shared.isViewingNotification(descriptor) {
                                await NotificationManager.shared.clearDeliveredNotifications(
                                    in: .messages(ids: [message.id])
                                )
                            }
                        }
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                // The periodic REST refresh remains the fallback while the
                // live connection retries.
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

extension Array where Element == Message {
    mutating func applyLiveUpdate(_ updated: Message, isIncluded: Bool) {
        guard isIncluded else {
            removeAll { $0.id == updated.id }
            return
        }
        if let index = firstIndex(where: { $0.id == updated.id }) {
            self[index] = updated
        } else {
            append(updated)
        }
        sort { $0.createdAt > $1.createdAt }
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
            } else {
                Text(message.isAwaitingTranscript ? "Processing audio…" : "No transcript available")
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
                if message.recommendsPermanentDelete {
                    Label("Delete recommended", systemImage: "trash.fill")
                        .font(Theme.Fonts.caption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.error)
                        .padding(.horizontal, Theme.Spacing.small)
                        .padding(.vertical, 3)
                        .background(Theme.Colors.error.opacity(0.12), in: Capsule())
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

    var isAwaitingTranscript: Bool {
        if let transcription = latestTranscription { return transcription.status == .pending }
        return status == .uploading || status == .received
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
