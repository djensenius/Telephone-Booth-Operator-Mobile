//
//  QuestionsView.swift
//  TelephoneBoothOperatorMobile
//
//  Paged list of active questions on the booth. Operators can preview the
//  question audio and retire a question with swipe-to-delete. Creating
//  new questions still happens from the operator console (the audio
//  upload pipeline lives there).
//

#if !os(watchOS) && !os(tvOS)

import SwiftUI

public struct QuestionsView: View {
    @State private var questions: [Question] = []
    @State private var nextCursor: String?
    @State private var loadState: LoadState = .idle
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var expandedId: String?

    private let client: OperatorClient
    private let pageSize: Int

    enum LoadState: Equatable {
        case idle
        case loadingInitial
        case loadingMore
        case done
    }

    public init(client: OperatorClient = .shared, pageSize: Int = 50) {
        self.client = client
        self.pageSize = pageSize
    }

    public var body: some View {
        Group {
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
        .background(Theme.Colors.background)
        .task {
            if questions.isEmpty { await loadFirstPage() }
        }
        .refreshableIfAvailable {
            await loadFirstPage()
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
                    isExpanded: expandedId == question.id,
                    onToggle: { toggle(question.id) }
                )
                .listRowBackground(Theme.Colors.secondaryBackground)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await retire(question) }
                    } label: {
                        Label("Retire", systemImage: "trash")
                    }
                }
            }
            if nextCursor != nil {
                loadMoreFooter
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
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
            Text("No active questions")
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

    private func toggle(_ id: String) {
        withAnimation(.snappy) {
            expandedId = expandedId == id ? nil : id
        }
    }

    private func loadFirstPage() async {
        loadState = .loadingInitial
        errorMessage = nil
        do {
            let page = try await client.fetchQuestions(cursor: nil, limit: pageSize)
            questions = page.items
            nextCursor = page.nextCursor
            loadState = nextCursor == nil ? .done : .idle
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Failed to load questions."
            loadState = .idle
        }
    }

    private func loadMore() async {
        guard let cursor = nextCursor, loadState != .loadingMore else { return }
        loadState = .loadingMore
        errorMessage = nil
        do {
            let page = try await client.fetchQuestions(cursor: cursor, limit: pageSize)
            questions.append(contentsOf: page.items)
            nextCursor = page.nextCursor
            loadState = nextCursor == nil ? .done : .idle
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Failed to load more questions."
            loadState = .idle
        }
    }

    private func retire(_ question: Question) async {
        actionError = nil
        do {
            try await client.deleteQuestion(id: question.id)
            questions.removeAll { $0.id == question.id }
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "Couldn't retire question."
        }
    }
}

struct QuestionRow: View {
    let question: Question
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
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
                            Text(question.createdAt, format: .dateTime.month(.abbreviated).day().year())
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            if let duration = DurationFormatter.shortString(milliseconds: question.audio.durationMs) {
                                Label(duration, systemImage: "clock")
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hide audio preview" : "Show audio preview")

            if isExpanded {
                AudioPlayerView(audio: question.audio)
                    .padding(.top, Theme.Spacing.small)
            }
        }
        .padding(.vertical, Theme.Spacing.small)
    }
}

#endif
