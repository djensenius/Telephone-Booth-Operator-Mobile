//
//  SessionListView.swift
//  TelephoneBoothOperatorMobile
//
//  Paged list of call sessions from `/v1/sessions`. Tapping a row opens
//  the detail view with the full event timeline. Not shown on watchOS
//  (PR 7 will tailor a glance for the watch) or tvOS (PR 8 booth wall).
//

#if !os(watchOS) && !os(tvOS)

import SwiftUI

public struct SessionListView: View {
    @State private var sessions: [CallSession] = []
    @State private var nextCursor: String?
    @State private var loadState: LoadState = .idle
    @State private var errorMessage: String?

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
            if loadState == .loadingInitial && sessions.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.background)
            } else if sessions.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Theme.Colors.background)
        .task {
            if sessions.isEmpty {
                await loadFirstPage()
            }
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
            ForEach(sessions) { session in
                NavigationLink(value: session.id) {
                    SessionRow(session: session)
                }
                .listRowBackground(Theme.Colors.secondaryBackground)
            }
            if nextCursor != nil {
                loadMoreFooter
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: String.self) { sessionId in
            SessionDetailView(sessionId: sessionId, client: client)
        }
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
            Image(systemName: "phone.down.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("No call sessions yet")
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

    private func loadFirstPage() async {
        loadState = .loadingInitial
        errorMessage = nil
        do {
            let page = try await client.fetchSessions(cursor: nil, limit: pageSize)
            sessions = page.items
            nextCursor = page.nextCursor
            loadState = nextCursor == nil ? .done : .idle
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Failed to load sessions."
            loadState = .idle
        }
    }

    private func loadMore() async {
        guard let cursor = nextCursor, loadState != .loadingMore else { return }
        loadState = .loadingMore
        errorMessage = nil
        do {
            let page = try await client.fetchSessions(cursor: cursor, limit: pageSize)
            sessions.append(contentsOf: page.items)
            nextCursor = page.nextCursor
            loadState = nextCursor == nil ? .done : .idle
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Failed to load more sessions."
            loadState = .idle
        }
    }
}

struct SessionRow: View {
    let session: CallSession

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                Text(session.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(Theme.Fonts.bodyMedium.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                if let outcome = session.outcome {
                    Text(outcome.displayName)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(outcome.isSuccess ? Theme.Colors.success : Theme.Colors.textSecondary)
                }
            }
            HStack(spacing: Theme.Spacing.medium) {
                Label(session.boothId, systemImage: "phone.fill")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                if let digits = session.digitsDialed, !digits.isEmpty {
                    Label(digits, systemImage: "number")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                if let duration = formattedDuration(session.durationMs) {
                    Label(duration, systemImage: "clock")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.small)
    }

    private func formattedDuration(_ durationMs: Int?) -> String? {
        guard let durationMs, durationMs > 0 else { return nil }
        let totalSeconds = Int((Double(durationMs) / 1000.0).rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        }
        return "\(seconds)s"
    }
}

#endif
