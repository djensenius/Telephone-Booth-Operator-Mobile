// swiftlint:disable file_length
//
//  MessageListView.swift
//  TelephoneBoothOperatorMobile
//
//  Operator-facing browser of recorded messages. Filterable by status,
//  drills into MessageDetailView for transcripts + audio playback.
//

#if !os(watchOS) && !os(tvOS)

import os
import SwiftUI

private let messageListLogger = Logger(
    subsystem: "org.davidjensenius.TBOperatorMobile",
    category: "MessageList"
)

enum MessageListMode: Equatable, Sendable {
    case queue
    case question(id: String)

    var questionId: String? {
        guard case .question(let id) = self else { return nil }
        return id
    }

    var isQuestion: Bool {
        questionId != nil
    }

    func includes(_ message: Message, filter: MessageListFilter) -> Bool {
        switch self {
        case .queue:
            return filter.includes(message.status)
        case .question(let id):
            return message.questionId == id
        }
    }

    func shouldDismissDetail(afterDecisionTo status: MessageStatus, filter: MessageListFilter) -> Bool {
        switch self {
        case .queue:
            return filter.shouldDismissDetail(afterDecisionTo: status)
        case .question:
            return false
        }
    }

    func notificationScope(
        for messages: [Message],
        filter: MessageListFilter
    ) -> DeliveredNotificationScope {
        switch self {
        case .queue where filter == .all || filter == .review:
            return .allMessages
        case .queue, .question:
            return .messages(ids: Set(messages.map(\.id)))
        }
    }

    func liveUpdateDisposition(
        for message: Message,
        loadedMessages: [Message],
        hasMore: Bool,
        filter: MessageListFilter
    ) -> MessageLiveUpdateDisposition {
        let isLoaded = loadedMessages.contains { $0.id == message.id }
        guard includes(message, filter: filter) else {
            return isLoaded ? .remove : .ignore
        }
        guard case .question = self, !isLoaded, hasMore, let oldest = loadedMessages.oldest else {
            return .upsert
        }
        return message.isNewer(than: oldest) ? .upsert : .ignore
    }

    func actionAccess(
        for message: Message,
        installationState: MessageInstallationAccessState
    ) -> MessageActionAccess {
        guard case .question = self else { return .writable }
        switch installationState {
        case .loading:
            return .checking
        case .available(let currentInstallationId):
            return .installationScoped(
                messageInstallationId: message.installationId,
                currentInstallationId: currentInstallationId
            )
        case .unavailable:
            return .readOnlyUnavailable
        }
    }
}

enum MessageLiveUpdateDisposition: Equatable, Sendable {
    case upsert
    case remove
    case ignore
}

enum MessageInstallationAccessState: Equatable, Sendable {
    case loading
    case available(currentInstallationId: String?)
    case unavailable
}

enum MessageActionAccess: Equatable, Sendable {
    case writable
    case checking
    case readOnlyArchived
    case readOnlyUnavailable

    static func installationScoped(
        messageInstallationId: String?,
        currentInstallationId: String?
    ) -> MessageActionAccess {
        guard let messageInstallationId,
              let currentInstallationId,
              messageInstallationId == currentInstallationId else {
            return .readOnlyArchived
        }
        return .writable
    }

    var readOnlyReason: String? {
        switch self {
        case .writable:
            return nil
        case .checking:
            return "Checking installation status — actions are temporarily disabled."
        case .readOnlyArchived:
            return "Archived installation — this recording is read-only."
        case .readOnlyUnavailable:
            return "Installation status is unavailable — this recording is read-only."
        }
    }
}

enum MessageListMutation: Equatable, Sendable {
    case upsert(Message)
    case remove(String)

    var messageId: String {
        switch self {
        case .upsert(let message): return message.id
        case .remove(let id): return id
        }
    }
}

struct MessageListMutationRecord: Equatable, Sendable {
    let sequence: UInt
    let mutation: MessageListMutation
}

private struct MessageListRefreshID: Equatable {
    let filter: MessageListFilter
    let questionId: String?
}

// swiftlint:disable:next type_body_length
public struct MessageListView: View {
    @Environment(\.automaticRefreshEnabled) private var automaticRefreshEnabled
    @Environment(\.scenePhase) private var scenePhase
    @State private var messages: [Message] = []
    @State private var loading = false
    @State private var loadingMore = false
    @State private var errorMessage: String?
    @State private var filter: MessageListFilter
    @State private var searchText = ""
    @State private var decidingMessageIds: Set<String> = []
    @State private var deletingMessageIds: Set<String> = []
    @State private var deleteCandidate: Message?
    @State private var refreshGeneration = 0
    @State private var notificationScope: DeliveredNotificationScope?
    @State private var nextCursor: String?
    @State private var loadedPageCount = 0
    @State private var isVisible = false
    @State private var latestMutationSequence: UInt = 0
    @State private var pendingMutations: [MessageListMutationRecord] = []
    @State private var installationAccessState: MessageInstallationAccessState = .loading
    @State private var installationAccessError: String?
    @State private var installationAccessRevision: UInt = 0
    @State private var questionSnapshot: Question?
    @State private var questionSummaryRevision: UInt = 0
    #if os(macOS)
    @State private var hoveredMessageId: String?
    #endif
    private let client: OperatorClient
    private let socket: StatusSocket
    private let routeFilter: MessageListFilter
    private let routeRevision: UInt
    private let mode: MessageListMode
    private let question: Question?
    private let pageSize: Int
    private let onQuestionMessageCountChange: (Int) -> Void

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
        self.mode = .queue
        self.question = nil
        self.pageSize = 50
        self.onQuestionMessageCountChange = { _ in }
        _filter = State(initialValue: routeFilter)
        _questionSnapshot = State(initialValue: nil)
    }

    public init(
        question: Question,
        client: OperatorClient = .shared,
        socket: StatusSocket? = nil,
        pageSize: Int = 50,
        onQuestionMessageCountChange: @escaping (Int) -> Void = { _ in }
    ) {
        self.client = client
        self.socket = socket ?? (client.demoMode ? .demo : .shared)
        self.routeFilter = .all
        self.routeRevision = 0
        self.mode = .question(id: question.id)
        self.question = question
        self.pageSize = pageSize
        self.onQuestionMessageCountChange = onQuestionMessageCountChange
        _filter = State(initialValue: .all)
        _questionSnapshot = State(initialValue: question)
    }

    public var body: some View {
        Group {
            if mode.isQuestion {
                questionList
            } else {
                VStack(spacing: 0) {
                    filterPicker
                    queueContent
                }
            }
        }
        .background(Theme.Colors.background)
        .searchable(text: $searchText, prompt: searchPrompt)
        .navigationDestination(for: String.self) { messageId in
            messageDetail(messageId: messageId)
        }
        .autoRefresh(
            id: MessageListRefreshID(filter: filter, questionId: mode.questionId)
        ) {
            await refresh()
        }
        .onChange(of: filter) {
            if !mode.isQuestion {
                notificationScope = nil
            }
        }
        .onChange(of: routeRevision) {
            if !mode.isQuestion {
                filter = routeFilter
            }
        }
        .onChange(of: question) { _, updated in
            guard let updated else { return }
            questionSummaryRevision &+= 1
            questionSnapshot = updated.preservingMessageCount(
                from: questionSnapshot ?? updated
            )
        }
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
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

    @ViewBuilder
    private var queueContent: some View {
        if loading && messages.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Colors.background)
        } else if messages.isEmpty {
            emptyState
        } else {
            queueList
        }
    }

    private var queueList: some View {
        List {
            messageBanners
            if filteredMessages.isEmpty {
                noMatchesRow
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            messageRows
        }
        .operatorListStyle()
    }

    private var questionList: some View {
        List {
            if let question = displayedQuestion {
                QuestionDetailCard(question: question)
                    .listRowInsets(
                        EdgeInsets(
                            top: Theme.Spacing.medium,
                            leading: Theme.Spacing.medium,
                            bottom: Theme.Spacing.medium,
                            trailing: Theme.Spacing.medium
                        )
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                messageBanners
                if loading && messages.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, Theme.Spacing.extraLarge)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if filteredMessages.isEmpty {
                    noMatchesRow
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    messageRows
                }

                if nextCursor != nil {
                    loadMoreFooter
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } header: {
                HStack {
                    Text("Answers")
                    Spacer()
                    if !messages.isEmpty {
                        Text(filteredMessages.count, format: .number)
                    }
                }
            }
        }
        .operatorListStyle()
    }

    @ViewBuilder
    private var messageBanners: some View {
        if let errorMessage {
            BannerView(message: errorMessage, kind: .error)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        if let installationAccessError {
            BannerView(message: installationAccessError, kind: .info)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var messageRows: some View {
        ForEach(filteredMessages) { message in
            let actionAccess = mode.actionAccess(
                for: message,
                installationState: installationAccessState
            )
            messageLink(for: message, actionAccess: actionAccess)
                .frame(maxWidth: .infinity, alignment: .leading)
                #if os(macOS)
                .overlay(alignment: .trailing) {
                    if hoveredMessageId == message.id, actionAccess == .writable {
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
                    if actionAccess == .writable {
                        actionButtons(for: message)
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if actionAccess == .writable,
                       message.canBeDecided,
                       message.status != .approved {
                        Button {
                            Task { await decide(message, as: .approve) }
                        } label: {
                            Label("Approve", systemImage: "checkmark.circle.fill")
                        }
                        .tint(Theme.Colors.success)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if actionAccess == .writable,
                       message.canBeDecided,
                       message.status != .rejected {
                        Button(role: .destructive) {
                            Task { await decide(message, as: .reject) }
                        } label: {
                            Label("Reject", systemImage: "xmark.circle.fill")
                        }
                    }
                    if actionAccess == .writable {
                        Button(role: .destructive) {
                            deleteCandidate = message
                        } label: {
                            Label("Delete permanently", systemImage: "trash.fill")
                        }
                        .tint(
                            message.recommendsPermanentDelete
                                ? Theme.Colors.error
                                : Theme.Colors.textSecondary
                        )
                    }
                }
        }
    }

    @ViewBuilder
    private func messageLink(
        for message: Message,
        actionAccess: MessageActionAccess
    ) -> some View {
        if mode.isQuestion {
            NavigationLink {
                messageDetail(messageId: message.id)
            } label: {
                MessageRow(
                    message: message,
                    isDeciding: isPerformingAction(on: message),
                    readOnlyReason: actionAccess.readOnlyReason
                )
            }
        } else {
            NavigationLink(value: message.id) {
                MessageRow(
                    message: message,
                    isDeciding: isPerformingAction(on: message),
                    readOnlyReason: actionAccess.readOnlyReason
                )
            }
        }
    }

    private func messageDetail(messageId: String) -> some View {
        MessageDetailView(
            messageId: messageId,
            client: client,
            readOnlyReason: readOnlyReason(for: messageId),
            enforceInstallationReadOnly: mode.isQuestion,
            socket: socket,
            onMessageUpdate: { updated in apply(updated) },
            shouldDismissAfterDecision: { updated in
                mode.shouldDismissDetail(
                    afterDecisionTo: updated.status,
                    filter: filter
                )
            },
            onMessageDelete: { id in removeMessage(id: id) }
        )
    }

    private var searchPrompt: String {
        mode.isQuestion ? "Search answers" : "Search transcripts"
    }

    private var noMatchesRow: some View {
        VStack(spacing: Theme.Spacing.medium) {
            Image(systemName: emptyIcon)
                .font(.system(size: 28))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(emptyTitle)
                .font(Theme.Fonts.bodyLarge)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(Theme.Spacing.extraLarge)
        .frame(maxWidth: .infinity)
    }

    private var emptyIcon: String {
        if !searchText.isEmpty { return "magnifyingglass" }
        return mode.isQuestion ? "waveform" : "tray"
    }

    @ViewBuilder
    private var loadMoreFooter: some View {
        if loadingMore {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, Theme.Spacing.medium)
        } else {
            Button {
                Task { await loadMoreAnswers() }
            } label: {
                Text("Load more answers")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.medium)
            }
            .buttonStyle(.plain)
        }
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
        if errorMessage != nil {
            return mode.isQuestion ? "Couldn't load answers" : "Couldn't load messages"
        }
        if !searchText.isEmpty {
            return mode.isQuestion ? "No matching answers" : "No matching messages"
        }
        if mode.isQuestion { return "No answers yet" }
        if filter != .all { return "No \(filter.title.lowercased()) messages" }
        return "No messages yet"
    }

    private var filteredMessages: [Message] {
        messages.filter { message in
            mode.includes(message, filter: filter) && message.matchesSearch(searchText)
        }
    }

    private var displayedQuestion: Question? {
        questionSnapshot
    }

    private func refresh() async {
        if mode.isQuestion {
            await refreshQuestionAnswers()
            return
        }
        refreshGeneration += 1
        let generation = refreshGeneration
        let mutationSequence = latestMutationSequence
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
            messages = list.applying(pendingMutations.mutations(after: mutationSequence))
            pendingMutations.removeAll()
            nextCursor = nil
            loadedPageCount = 0
            await acknowledgeLoadedMessages()
        } catch {
            guard !Task.isCancelled, generation == refreshGeneration else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Failed to load messages."
        }
    }

    private func refreshQuestionAnswers() async {
        guard let questionId = mode.questionId, !loadingMore else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let mutationSequence = latestMutationSequence
        let pageCount = max(loadedPageCount, 1)
        loading = true
        errorMessage = nil
        defer {
            if generation == refreshGeneration {
                loading = false
            }
        }
        do {
            let refreshed = try await reloadLoadedPages(
                pageCount: pageCount,
                isCurrent: { generation == refreshGeneration },
                fetchPage: { cursor in
                    let page = try await client.fetchQuestionMessages(
                        questionId: questionId,
                        cursor: cursor,
                        limit: pageSize
                    )
                    return (page.items, page.nextCursor)
                }
            )
            guard !Task.isCancelled, generation == refreshGeneration else { return }
            messages = refreshed.items.applying(
                pendingMutations.mutations(after: mutationSequence)
            )
            pendingMutations.removeAll()
            nextCursor = refreshed.nextCursor
            loadedPageCount = refreshed.pageCount
            if nextCursor == nil {
                setQuestionMessageCount(messages.count)
            }
            await refreshQuestionSummary()
            await refreshQuestionInstallationAccess()
            await acknowledgeLoadedMessages()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, generation == refreshGeneration else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Failed to load answers for this question."
        }
    }

    private func loadMoreAnswers() async {
        guard let questionId = mode.questionId,
              let cursor = nextCursor,
              !loading,
              !loadingMore else {
            return
        }
        let generation = refreshGeneration
        let mutationSequence = latestMutationSequence
        loadingMore = true
        errorMessage = nil
        defer { loadingMore = false }
        do {
            let page = try await client.fetchQuestionMessages(
                questionId: questionId,
                cursor: cursor,
                limit: pageSize
            )
            guard !Task.isCancelled, generation == refreshGeneration else { return }
            messages = (messages + page.items).applying(
                pendingMutations.mutations(after: mutationSequence)
            )
            pendingMutations.removeAll()
            nextCursor = page.nextCursor
            loadedPageCount += 1
            if nextCursor == nil {
                setQuestionMessageCount(messages.count)
            }
            await acknowledgeLoadedMessages()
        } catch {
            guard !Task.isCancelled, generation == refreshGeneration else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Failed to load more answers."
        }
    }

    private func acknowledgeLoadedMessages() async {
        let scope = mode.notificationScope(for: messages, filter: filter)
        notificationScope = scope
        guard isVisible, scenePhase == .active, automaticRefreshEnabled else { return }
        await NotificationManager.shared.clearDeliveredNotifications(in: scope)
    }

    private func decide(_ message: Message, as decision: MessageDecision) async {
        guard mode.actionAccess(
            for: message,
            installationState: installationAccessState
        ) == .writable else {
            errorMessage = "This recording belongs to a read-only installation."
            return
        }
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
        guard mode.actionAccess(
            for: message,
            installationState: installationAccessState
        ) == .writable else {
            errorMessage = "This recording belongs to a read-only installation."
            return
        }
        guard !deletingMessageIds.contains(message.id) else { return }
        deleteCandidate = nil
        deletingMessageIds.insert(message.id)
        errorMessage = nil
        defer { deletingMessageIds.remove(message.id) }
        do {
            try await client.deleteMessage(id: message.id)
            removeMessage(id: message.id)
            await PendingMessagesStore.shared.refresh(using: client)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't delete this recording."
        }
    }

    private func apply(_ updated: Message) {
        let mutation: MessageListMutation = mode.includes(updated, filter: filter)
            ? .upsert(updated)
            : .remove(updated.id)
        apply(mutation)
    }

    @discardableResult
    private func apply(_ mutation: MessageListMutation) -> Bool {
        let containedMessage = messages.contains { $0.id == mutation.messageId }
        latestMutationSequence &+= 1
        pendingMutations.removeAll { $0.mutation.messageId == mutation.messageId }
        pendingMutations.append(
            MessageListMutationRecord(
                sequence: latestMutationSequence,
                mutation: mutation
            )
        )
        messages.apply(mutation)
        let containsMessage = messages.contains { $0.id == mutation.messageId }
        if mode.isQuestion, containedMessage != containsMessage {
            adjustQuestionMessageCount(by: containsMessage ? 1 : -1)
        }
        updateQuestionNotificationScope()
        return containedMessage != containsMessage
    }

    private func removeMessage(id: String) {
        if apply(.remove(id)) {
            Task { await refreshQuestionSummary() }
        }
    }

    private func updateQuestionNotificationScope() {
        guard mode.isQuestion else { return }
        notificationScope = mode.notificationScope(for: messages, filter: filter)
    }

    private func readOnlyReason(for messageId: String) -> String? {
        guard mode.isQuestion else { return nil }
        guard let message = messages.first(where: { $0.id == messageId }) else {
            return MessageActionAccess.checking.readOnlyReason
        }
        return mode.actionAccess(
            for: message,
            installationState: installationAccessState
        ).readOnlyReason
    }

    private func refreshQuestionInstallationAccess() async {
        guard mode.isQuestion else { return }
        let revision = installationAccessRevision
        do {
            let current = try await client.fetchCurrentInstallation()
            guard !Task.isCancelled, revision == installationAccessRevision else { return }
            installationAccessState = .available(currentInstallationId: current?.id)
            installationAccessError = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, revision == installationAccessRevision else { return }
            installationAccessState = .unavailable
            installationAccessError = "Couldn't verify installation status. Actions are disabled."
        }
    }

    private func adjustQuestionMessageCount(by adjustment: Int) {
        if let messageCount = displayedQuestion?.messageCount {
            setQuestionMessageCount(max(0, messageCount + adjustment))
        } else if nextCursor == nil {
            setQuestionMessageCount(messages.count)
        }
    }

    private func setQuestionMessageCount(_ count: Int) {
        guard let question = displayedQuestion else { return }
        questionSummaryRevision &+= 1
        let updated = question.updatingMessageCount(count)
        questionSnapshot = updated
        onQuestionMessageCountChange(count)
    }

    private func refreshQuestionSummary() async {
        guard let questionId = mode.questionId else { return }
        questionSummaryRevision &+= 1
        let revision = questionSummaryRevision
        do {
            guard let updated = try await client.fetchQuestion(id: questionId) else {
                messageListLogger.error("Question summary missing for \(questionId, privacy: .public)")
                return
            }
            guard !Task.isCancelled,
                  revision == questionSummaryRevision,
                  let latestQuestion = displayedQuestion else {
                return
            }
            let merged = latestQuestion.updatingMessageCount(
                updated.messageCount ?? latestQuestion.messageCount
            )
            questionSnapshot = merged
            if let messageCount = merged.messageCount {
                onQuestionMessageCountChange(messageCount)
            }
        } catch is CancellationError {
            return
        } catch {
            messageListLogger.error(
                "Failed to refresh question summary: \(error.localizedDescription, privacy: .public)"
            )
        }
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
                    switch envelope {
                    case .message(let message):
                        await handleLiveMessage(message)
                    case .installation(let installation):
                        handleInstallationUpdate(installation)
                    case .status, .system, .work, .unknown:
                        break
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

    private func handleLiveMessage(_ message: Message) async {
        let disposition = mode.liveUpdateDisposition(
            for: message,
            loadedMessages: messages,
            hasMore: nextCursor != nil,
            filter: filter
        )
        switch disposition {
        case .upsert:
            if apply(.upsert(message)) {
                await refreshQuestionSummary()
            }
        case .remove:
            if apply(.remove(message.id)) {
                await refreshQuestionSummary()
            }
        case .ignore:
            return
        }
        guard disposition == .upsert else { return }

        let descriptor = NotificationManager.deliveredNotificationDescriptor(
            categoryIdentifier: "BOOTH_MESSAGE",
            userInfo: ["messageId": message.id]
        )
        let isViewingQuestionAnswers = mode.isQuestion
            && isVisible
            && scenePhase == .active
            && automaticRefreshEnabled
        guard isViewingQuestionAnswers
                || NotificationManager.shared.isViewingNotification(descriptor) else {
            return
        }
        await NotificationManager.shared.clearDeliveredNotifications(
            in: .messages(ids: [message.id])
        )
    }

    private func handleInstallationUpdate(_ installation: Installation) {
        guard mode.isQuestion else { return }
        installationAccessRevision &+= 1
        if installation.isActive, installation.endedAt == nil {
            installationAccessState = .available(currentInstallationId: installation.id)
            installationAccessError = nil
            return
        }
        if case .available(let currentInstallationId) = installationAccessState,
           currentInstallationId == installation.id {
            installationAccessState = .available(currentInstallationId: nil)
            installationAccessError = nil
        }
    }
}

extension Array where Element == Message {
    mutating func applyLiveUpdate(_ updated: Message, isIncluded: Bool) {
        apply(isIncluded ? .upsert(updated) : .remove(updated.id))
    }

    mutating func apply(_ mutation: MessageListMutation) {
        switch mutation {
        case .upsert(let message):
            self = (filter { $0.id != message.id } + [message]).deduplicatedNewestFirst()
        case .remove(let id):
            removeAll { $0.id == id }
        }
    }

    func applying(_ mutations: [MessageListMutation]) -> [Message] {
        var result = deduplicatedNewestFirst()
        for mutation in mutations {
            result.apply(mutation)
        }
        return result
    }

    func deduplicatedNewestFirst() -> [Message] {
        var messagesById: [String: Message] = [:]
        for message in self {
            messagesById[message.id] = message
        }
        return messagesById.values.sorted {
            $0.isNewer(than: $1)
        }
    }

    var oldest: Message? {
        self.min { $0.isOlder(than: $1) }
    }
}

private extension Message {
    func isNewer(than other: Message) -> Bool {
        if createdAt != other.createdAt { return createdAt > other.createdAt }
        return id > other.id
    }

    func isOlder(than other: Message) -> Bool {
        if createdAt != other.createdAt { return createdAt < other.createdAt }
        return id < other.id
    }
}

extension Array where Element == MessageListMutationRecord {
    func mutations(after sequence: UInt) -> [MessageListMutation] {
        filter { $0.sequence > sequence }.map(\.mutation)
    }
}

struct MessageRow: View {
    let message: Message
    let isDeciding: Bool
    let readOnlyReason: String?

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
            if let readOnlyReason {
                Label(readOnlyReason, systemImage: "lock.fill")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
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
