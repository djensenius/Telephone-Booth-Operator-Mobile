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
    @State private var expandedId: String?
    @State private var filter: QuestionFilter = .all
    @State private var isComposing = false
    @State private var generation = 0
    @State private var loadedPageCount = 0
    @State private var loadedFilter: QuestionFilter?

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
        .autoRefresh(id: filter) {
            if loadedFilter != filter || loadState == .loadingInitial || loadState == .loadingMore {
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
                    isExpanded: expandedId == question.id,
                    canManage: isAdmin,
                    onToggle: { toggle(question.id) },
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

    private func toggle(_ id: String) {
        withAnimation(.snappy) {
            expandedId = expandedId == id ? nil : id
        }
    }

    private func handleCreated(_ created: Question) {
        actionError = nil
        // Show the new question if it belongs in the current filter.
        if filter == .all || filter.query == .status(created.status) {
            questions.insert(created, at: 0)
        }
    }

    private func loadFirstPage() async {
        generation += 1
        let requested = generation
        let selectedFilter = filter
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
            questions = page.items
            nextCursor = page.nextCursor
            loadedPageCount = 1
            loadedFilter = selectedFilter
            loadState = nextCursor == nil ? .done : .idle
        } catch {
            guard requested == generation, selectedFilter == filter else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Failed to load questions."
            loadState = .idle
        }
    }

    private func refreshLoadedPages() async {
        guard loadState != .loadingInitial, loadState != .loadingMore else { return }
        generation += 1
        let requested = generation
        let pageCount = max(loadedPageCount, 1)
        let selectedFilter = filter
        let query = selectedFilter.query
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
            questions = refreshed.items
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

    private func loadMore() async {
        guard let cursor = nextCursor, loadState == .idle else { return }
        let requested = generation
        let selectedFilter = filter
        loadState = .loadingMore
        errorMessage = nil
        do {
            let page = try await client.fetchQuestions(cursor: cursor, limit: pageSize, filter: selectedFilter.query)
            guard requested == generation, selectedFilter == filter else { return }
            questions.append(contentsOf: page.items)
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
            if filter == .all || filter == .archived {
                // The retired question still belongs in this filter — refetch.
                await refreshLoadedPages()
            } else {
                questions.removeAll { $0.id == question.id }
            }
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "Couldn't retire question."
        }
    }

    private func applyUpdate(_ updated: Question) {
        if filter != .all && filter.query != .status(updated.status) {
            // No longer matches the active filter — drop it from the list.
            questions.removeAll { $0.id == updated.id }
            return
        }
        if let index = questions.firstIndex(where: { $0.id == updated.id }) {
            questions[index] = updated
        }
    }
}

struct QuestionRow: View {
    let question: Question
    let client: OperatorClient
    let isExpanded: Bool
    let canManage: Bool
    let onToggle: () -> Void
    let onActivate: () -> Void
    let onDeactivate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(alignment: .top, spacing: Theme.Spacing.medium) {
                Button(action: onToggle) {
                    HStack(alignment: .top, spacing: Theme.Spacing.medium) {
                        Image(systemName: "quote.opening")
                            .foregroundStyle(Theme.Colors.accent)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                            Text(question.prompt)
                                .font(Theme.Fonts.bodyMedium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(isExpanded ? nil : 2)
                            HStack(spacing: Theme.Spacing.medium) {
                                QuestionStatusBadge(status: question.status)
                                Text(question.createdAt, format: .dateTime.month(.abbreviated).day().year())
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                if let duration = DurationFormatter.shortString(
                                    milliseconds: question.audio.durationMs
                                ) {
                                    Label(duration, systemImage: "clock")
                                        .font(Theme.Fonts.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(isExpanded ? "Hide audio preview" : "Show audio preview")

                if canManage {
                    actionsMenu
                }
            }

            if isExpanded {
                AudioPlayerView(audio: question.audio)
                    .padding(.top, Theme.Spacing.small)
            }

            NavigationLink {
                MessageListView(
                    questionId: question.id,
                    questionPrompt: question.prompt,
                    client: client
                )
                .navigationTitle("Answers")
            } label: {
                Label("View answers", systemImage: "waveform")
                    .font(Theme.Fonts.bodySmall.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View answers to \(question.prompt)")
        }
        .padding(.vertical, Theme.Spacing.small)
        .contextMenu {
            if canManage {
                actionButtons
            }
        }
    }

    private var actionsMenu: some View {
        Menu {
            actionButtons
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(Theme.Colors.textSecondary)
                .font(.body)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Question actions")
    }

    @ViewBuilder
    private var actionButtons: some View {
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
