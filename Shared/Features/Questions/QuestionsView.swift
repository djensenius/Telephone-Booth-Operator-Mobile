// swiftlint:disable file_length
//
//  QuestionsView.swift
//  TelephoneBoothOperatorMobile
//
//  Browse, preview, and manage the question lifecycle and audio.
//

#if !os(watchOS) && !os(tvOS)

import SwiftUI

public struct QuestionsView: View {
    enum QuestionFilter: String, CaseIterable, Identifiable {
        case all
        case draft
        case active
        case archived

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .draft: return "Draft"
            case .active: return "Active"
            case .archived: return "Archived"
            }
        }

        var query: QuestionListFilter {
            switch self {
            case .all: return .all
            case .draft: return .status(.draft)
            case .active: return .status(.active)
            case .archived: return .status(.archived)
            }
        }
    }

    @State private var questions: [Question] = []
    @State private var nextCursor: String?
    @State private var loadState: LoadState = .idle
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var filter: QuestionFilter = .all
    @State private var isComposing = false
    @State private var generation = 0
    @State private var loadedPageCount = 0
    @State private var loadedFilter: QuestionFilter?
    @State private var messageCountsByQuestionID: [String: Int] = [:]
    @State private var messageCountRevisions: [String: UInt] = [:]

    private let client: OperatorClient
    private let pageSize: Int
    private let isAdmin: Bool

    enum LoadState: Equatable {
        case idle
        case loadingInitial
        case loadingMore
        case done
    }

    public init(client: OperatorClient = .shared, isAdmin: Bool = false, pageSize: Int = 50) {
        self.client = client
        self.isAdmin = isAdmin
        self.pageSize = pageSize
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $filter) {
                ForEach(QuestionFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.small)

            content
        }
        .background(Theme.Colors.background)
        .toolbar {
            if isAdmin {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isComposing = true
                    } label: {
                        Label("New Question", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $isComposing) {
            QuestionComposerView(client: client) { created in
                handleCreated(created)
            }
        }
        .task(id: filter) {
            // Overflow tabs can appear before adaptive tab selection updates.
            await loadFirstPageIfNeeded()
        }
        .autoRefresh(id: filter, immediately: false) {
            guard loadState != .loadingInitial, loadState != .loadingMore else { return }
            if loadedFilter != filter || questions.isEmpty {
                await loadFirstPage()
            } else {
                await refreshLoadedPages()
            }
        }
        .refreshableIfAvailable {
            await loadFirstPage()
        }
    }

    @ViewBuilder
    private var content: some View {
        if loadState == .loadingInitial && questions.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Colors.background)
        } else if questions.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        List {
            if let errorMessage {
                BannerView(message: errorMessage, kind: .error)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if let actionError {
                BannerView(message: actionError, kind: .error)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(questions) { question in
                QuestionRow(
                    question: question,
                    client: client,
                    canManage: isAdmin,
                    onQuestionUpdate: { updated in applyUpdate(updated) },
                    onQuestionRetired: { id in handleRetired(id) },
                    onActivate: { Task { await activate(question) } },
                    onDeactivate: { Task { await deactivate(question) } },
                    onDelete: { Task { await retire(question) } }
                )
                .operatorListRowBackground()
                .swipeActions(edge: .trailing) {
                    if isAdmin {
                        if question.status != .archived {
                            Button(role: .destructive) {
                                Task { await retire(question) }
                            } label: {
                                Label("Retire", systemImage: "trash")
                            }
                        }
                        if question.status == .active {
                            Button {
                                Task { await deactivate(question) }
                            } label: {
                                Label("Deactivate", systemImage: "pause.circle")
                            }
                            .tint(Theme.Colors.warning)
                        } else {
                            Button {
                                Task { await activate(question) }
                            } label: {
                                Label("Activate", systemImage: "checkmark.circle")
                            }
                            .tint(Theme.Colors.success)
                        }
                    }
                }
            }
            if nextCursor != nil {
                loadMoreFooter
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .operatorListStyle()
    }

    @ViewBuilder
    private var loadMoreFooter: some View {
        if loadState == .loadingMore {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, Theme.Spacing.medium)
        } else {
            Button {
                Task { await loadMore() }
            } label: {
                Text("Load more")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.medium)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.medium) {
            Image(systemName: "questionmark.bubble")
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
        switch filter {
        case .all: return "No questions yet"
        case .draft: return "No draft questions"
        case .active: return "No active questions"
        case .archived: return "No archived questions"
        }
    }

    private func handleCreated(_ created: Question) {
        actionError = nil
        recordKnownMessageCount(from: created)
        // Show the new question if it belongs in the current filter.
        if filter == .all || filter.query == .status(created.status) {
            questions.insert(created, at: 0)
        }
    }

    private func loadFirstPageIfNeeded() async {
        guard Self.shouldLoadFirstPage(
            filter: filter,
            loadedFilter: loadedFilter,
            hasQuestions: !questions.isEmpty
        ) else { return }
        await loadFirstPage()
    }

    private func loadFirstPage() async {
        generation += 1
        let requested = generation
        let selectedFilter = filter
        let requestedCountRevisions = messageCountRevisions
        if selectedFilter != loadedFilter {
            questions = []
            nextCursor = nil
            loadedPageCount = 0
        }
        loadState = .loadingInitial
        errorMessage = nil
        do {
            let page = try await client.fetchQuestions(cursor: nil, limit: pageSize, filter: selectedFilter.query)
            guard requested == generation, selectedFilter == filter else { return }
            questions = reconcileMessageCounts(
                in: page.items,
                requestedCountRevisions: requestedCountRevisions
            )
            nextCursor = page.nextCursor
            loadedPageCount = 1
            loadedFilter = selectedFilter
            loadState = nextCursor == nil ? .done : .idle
        } catch {
            guard requested == generation, selectedFilter == filter else { return }
            loadState = .idle
            guard !Task.isCancelled else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Failed to load questions."
        }
    }

    private func refreshLoadedPages() async {
        guard loadState != .loadingInitial, loadState != .loadingMore else { return }
        generation += 1
        let requested = generation
        let pageCount = max(loadedPageCount, 1)
        let selectedFilter = filter
        let query = selectedFilter.query
        let requestedCountRevisions = messageCountRevisions
        loadState = .loadingInitial
        do {
            let refreshed = try await reloadLoadedPages(
                pageCount: pageCount,
                isCurrent: { requested == generation },
                fetchPage: { cursor in
                    let page = try await client.fetchQuestions(cursor: cursor, limit: pageSize, filter: query)
                    return (page.items, page.nextCursor)
                }
            )
            guard requested == generation, selectedFilter == filter else { return }
            guard !Task.isCancelled else {
                loadState = nextCursor == nil ? .done : .idle
                return
            }
            questions = reconcileMessageCounts(
                in: refreshed.items,
                requestedCountRevisions: requestedCountRevisions
            )
            nextCursor = refreshed.nextCursor
            loadedPageCount = refreshed.pageCount
            errorMessage = nil
            loadState = nextCursor == nil ? .done : .idle
        } catch {
            guard requested == generation, selectedFilter == filter else { return }
            loadState = nextCursor == nil ? .done : .idle
            guard !Task.isCancelled else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Failed to refresh questions."
        }
    }

    private func reconcileMessageCounts(
        in fetchedQuestions: [Question],
        requestedCountRevisions: [String: UInt]
    ) -> [Question] {
        return fetchedQuestions.map { question in
            let cachedCount = messageCountsByQuestionID[question.id]
            if messageCountRevisions[question.id] != requestedCountRevisions[question.id],
               let cachedCount {
                return question.updatingMessageCount(cachedCount)
            }
            if let messageCount = question.messageCount {
                messageCountsByQuestionID[question.id] = messageCount
                return question
            }
            return question.updatingMessageCount(cachedCount)
        }
    }

    private func loadMore() async {
        guard let cursor = nextCursor, loadState == .idle else { return }
        let requested = generation
        let selectedFilter = filter
        let requestedCountRevisions = messageCountRevisions
        loadState = .loadingMore
        errorMessage = nil
        do {
            let page = try await client.fetchQuestions(cursor: cursor, limit: pageSize, filter: selectedFilter.query)
            guard requested == generation, selectedFilter == filter else { return }
            questions.append(
                contentsOf: reconcileMessageCounts(
                    in: page.items,
                    requestedCountRevisions: requestedCountRevisions
                )
            )
            nextCursor = page.nextCursor
            loadedPageCount += 1
            loadState = nextCursor == nil ? .done : .idle
        } catch {
            guard requested == generation, selectedFilter == filter else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Failed to load more questions."
            loadState = .idle
        }
    }

    private func activate(_ question: Question) async {
        actionError = nil
        do {
            let updated = try await client.activateQuestion(id: question.id)
            applyUpdate(updated)
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "Couldn't activate question."
        }
    }

    private func deactivate(_ question: Question) async {
        actionError = nil
        do {
            let updated = try await client.deactivateQuestion(id: question.id)
            applyUpdate(updated)
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "Couldn't deactivate question."
        }
    }

    private func retire(_ question: Question) async {
        actionError = nil
        do {
            try await client.deleteQuestion(id: question.id)
            handleRetired(question.id)
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "Couldn't retire question."
        }
    }

    private func handleRetired(_ id: String) {
        if filter == .all || filter == .archived {
            // The retired question still belongs in this filter — refetch.
            Task { await refreshLoadedPages() }
        } else {
            questions.removeAll { $0.id == id }
        }
    }

    private func applyUpdate(_ updated: Question) {
        let current = questions.first(where: { $0.id == updated.id })
        let merged = updated
            .preservingMessageCount(from: current ?? updated)
            .updatingMessageCount(
                updated.messageCount
                    ?? current?.messageCount
                    ?? messageCountsByQuestionID[updated.id]
            )
        recordKnownMessageCount(from: merged)
        if filter != .all && filter.query != .status(updated.status) {
            // No longer matches the active filter — drop it from the list.
            questions.removeAll { $0.id == updated.id }
            return
        }
        if let index = questions.firstIndex(where: { $0.id == updated.id }) {
            questions[index] = merged
        }
    }

    private func recordKnownMessageCount(from question: Question) {
        guard let messageCount = question.messageCount else { return }
        messageCountsByQuestionID[question.id] = messageCount
        messageCountRevisions[question.id, default: 0] &+= 1
    }
}

extension QuestionsView {
    static func shouldLoadFirstPage(
        filter: QuestionFilter,
        loadedFilter: QuestionFilter?,
        hasQuestions: Bool
    ) -> Bool {
        loadedFilter != filter || !hasQuestions
    }
}

struct QuestionRow: View {
    let question: Question
    let client: OperatorClient
    let canManage: Bool
    let onQuestionUpdate: (Question) -> Void
    let onQuestionRetired: (String) -> Void
    let onActivate: () -> Void
    let onDeactivate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.small) {
            NavigationLink {
                QuestionDetailView(
                    question: question,
                    client: client,
                    canManage: canManage,
                    onQuestionUpdate: onQuestionUpdate,
                    onQuestionRetired: onQuestionRetired
                )
            } label: {
                HStack(alignment: .top, spacing: Theme.Spacing.medium) {
                    Image(systemName: "quote.opening")
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                        Text(question.prompt)
                            .font(Theme.Fonts.bodyMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        HStack(spacing: Theme.Spacing.medium) {
                            QuestionStatusBadge(status: question.status)
                            Text(question.createdAt, format: .dateTime.month(.abbreviated).day().year())
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        if question.audio.durationMs != nil || question.messageCount != nil {
                            HStack(spacing: Theme.Spacing.medium) {
                                if let duration = DurationFormatter.shortString(
                                    milliseconds: question.audio.durationMs
                                ) {
                                    Label(duration, systemImage: "clock")
                                        .font(Theme.Fonts.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                                if let messageCount = question.messageCount {
                                    Label(
                                        responseCountText(messageCount),
                                        systemImage: "bubble.left.and.bubble.right"
                                    )
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .accessibilityHint("Open the question and its answers")

            if canManage {
                actionsMenu
            }
        }
        .padding(.vertical, Theme.Spacing.small)
        .contextMenu {
            if canManage {
                QuestionActionButtons(
                    question: question,
                    onActivate: onActivate,
                    onDeactivate: onDeactivate,
                    onDelete: onDelete
                )
            }
        }
    }

    private var actionsMenu: some View {
        Menu {
            QuestionActionButtons(
                question: question,
                onActivate: onActivate,
                onDeactivate: onDeactivate,
                onDelete: onDelete
            )
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(Theme.Colors.textSecondary)
                .font(.body)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Question actions")
    }
}

private struct QuestionActionButtons: View {
    let question: Question
    let onActivate: () -> Void
    let onDeactivate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        if question.status == .active {
            Button {
                onDeactivate()
            } label: {
                Label("Deactivate", systemImage: "pause.circle")
            }
        } else {
            Button {
                onActivate()
            } label: {
                Label(question.status == .archived ? "Reactivate" : "Activate", systemImage: "checkmark.circle")
            }
        }
        if question.status != .archived {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Retire", systemImage: "trash")
            }
        }
    }
}

private struct QuestionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var question: Question
    @State private var isUpdating = false
    @State private var actionError: String?

    private let client: OperatorClient
    private let canManage: Bool
    private let onQuestionUpdate: (Question) -> Void
    private let onQuestionRetired: (String) -> Void

    init(
        question: Question,
        client: OperatorClient,
        canManage: Bool,
        onQuestionUpdate: @escaping (Question) -> Void,
        onQuestionRetired: @escaping (String) -> Void
    ) {
        _question = State(initialValue: question)
        self.client = client
        self.canManage = canManage
        self.onQuestionUpdate = onQuestionUpdate
        self.onQuestionRetired = onQuestionRetired
    }

    var body: some View {
        MessageListView(
            question: question,
            client: client,
            onQuestionMessageCountChange: { messageCount in
                applyQuestionMessageCount(messageCount)
            }
        )
            .navigationTitle("Question")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if canManage {
                    ToolbarItem(placement: .primaryAction) {
                        if isUpdating {
                            ProgressView()
                        } else {
                            Menu {
                                QuestionActionButtons(
                                    question: question,
                                    onActivate: { Task { await activate() } },
                                    onDeactivate: { Task { await deactivate() } },
                                    onDelete: { Task { await retire() } }
                                )
                            } label: {
                                Label("Question actions", systemImage: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
            .alert(
                "Couldn't update question",
                isPresented: Binding(
                    get: { actionError != nil },
                    set: { if !$0 { actionError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "Please try again.")
            }
    }

    private func activate() async {
        await updateQuestion(
            failureMessage: "Couldn't activate question."
        ) {
            try await client.activateQuestion(id: question.id)
        }
    }

    private func deactivate() async {
        await updateQuestion(
            failureMessage: "Couldn't deactivate question."
        ) {
            try await client.deactivateQuestion(id: question.id)
        }
    }

    private func updateQuestion(
        failureMessage: String,
        operation: () async throws -> Question
    ) async {
        guard !isUpdating else { return }
        isUpdating = true
        actionError = nil
        defer { isUpdating = false }
        do {
            let updated = try await operation()
            applyQuestionUpdate(updated)
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? failureMessage
        }
    }

    private func applyQuestionUpdate(_ updated: Question) {
        let merged = updated.preservingMessageCount(from: question)
        question = merged
        onQuestionUpdate(merged)
    }

    private func applyQuestionMessageCount(_ messageCount: Int) {
        let updated = question.updatingMessageCount(messageCount)
        question = updated
        onQuestionUpdate(updated)
    }

    private func retire() async {
        guard !isUpdating else { return }
        isUpdating = true
        actionError = nil
        defer { isUpdating = false }
        do {
            try await client.deleteQuestion(id: question.id)
            onQuestionRetired(question.id)
            dismiss()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "Couldn't retire question."
        }
    }
}

struct QuestionDetailCard: View {
    let question: Question

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(text: "Question")
                Spacer()
                QuestionStatusBadge(status: question.status)
            }

            Text(question.prompt)
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
                .textSelection(.enabled)

            HStack(spacing: Theme.Spacing.medium) {
                Label(
                    question.createdAt.formatted(.dateTime.month(.abbreviated).day().year()),
                    systemImage: "calendar"
                )
                if let duration = DurationFormatter.shortString(
                    milliseconds: question.audio.durationMs
                ) {
                    Label(duration, systemImage: "clock")
                }
                if let messageCount = question.messageCount {
                    Label(
                        responseCountText(messageCount),
                        systemImage: "bubble.left.and.bubble.right"
                    )
                }
            }
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Colors.textSecondary)

            AudioPlayerView(audio: question.audio)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
    }
}

private func responseCountText(_ count: Int) -> String {
    "\(count) \(count == 1 ? "response" : "responses")"
}

struct QuestionStatusBadge: View {
    let status: QuestionStatus

    var body: some View {
        Text(status.displayName)
            .font(Theme.Fonts.caption)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var color: Color {
        switch status {
        case .active: return Theme.Colors.success
        case .draft: return Theme.Colors.warning
        case .archived: return Theme.Colors.textSecondary
        case .unknown: return Theme.Colors.textSecondary
        }
    }
}

#endif
