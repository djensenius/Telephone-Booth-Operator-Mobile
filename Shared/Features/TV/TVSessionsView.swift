//
//  TVSessionsView.swift
//  TelephoneBoothOperatorMobile
//
//  Focus-friendly call-session history and detail for tvOS.
//

#if os(tvOS)

import SwiftUI

struct TVSessionsView: View {
    @State private var sessions: [CallSession] = []
    @State private var nextCursor: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadedPageCount = 0

    private let client: OperatorClient
    private let pageSize: Int

    init(client: OperatorClient = .shared, pageSize: Int = 50) {
        self.client = client
        self.pageSize = pageSize
    }

    var body: some View {
        TVScreen(
            title: "Sessions",
            systemImage: "phone.connection.fill",
            accessory: { countAccessory },
            content: {
                if let errorMessage {
                    TVBanner(message: errorMessage)
                }

                if sessions.isEmpty {
                    emptyState
                } else {
                    sessionGrid
                }

                if nextCursor != nil {
                    loadMoreButton
                }
            }
        )
        .autoRefresh(every: .seconds(30)) {
            if loadedPageCount == 0 {
                await loadFirstPage()
            } else {
                await refreshLoadedPages()
            }
        }
    }

    @ViewBuilder
    private var countAccessory: some View {
        if !sessions.isEmpty {
            VStack(alignment: .trailing, spacing: 2) {
                Text("Loaded")
                    .font(TVMetrics.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text("\(sessions.count)")
                    .font(.system(size: 36, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
    }

    private var sessionGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: TVMetrics.cardSpacing),
                count: 2
            ),
            alignment: .leading,
            spacing: TVMetrics.cardSpacing
        ) {
            ForEach(sessions) { session in
                NavigationLink(value: session.id) {
                    TVSessionCard(session: session)
                }
                .buttonStyle(TVCardButtonStyle())
            }
        }
    }

    private var emptyState: some View {
        TVFocusCard {
            HStack(spacing: 22) {
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Text(isLoading ? "Loading call sessions…" : "No call sessions yet")
                    .font(TVMetrics.Font.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var loadMoreButton: some View {
        Button {
            Task { await loadMore() }
        } label: {
            HStack(spacing: 14) {
                if isLoading {
                    ProgressView()
                }
                Text(isLoading ? "Loading…" : "Load more sessions")
                    .font(.system(size: 30, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
        .buttonStyle(TVSegmentButtonStyle(isSelected: false))
        .disabled(isLoading)
    }

    private func loadFirstPage() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await client.fetchSessions(cursor: nil, limit: pageSize)
            guard !Task.isCancelled else { return }
            sessions = page.items
            nextCursor = page.nextCursor
            loadedPageCount = 1
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't load call sessions."
        }
    }

    private func refreshLoadedPages() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let refreshed = try await reloadLoadedPages(
                pageCount: max(loadedPageCount, 1),
                isCurrent: { true },
                fetchPage: { cursor in
                    let page = try await client.fetchSessions(
                        cursor: cursor,
                        limit: pageSize
                    )
                    return (page.items, page.nextCursor)
                }
            )
            guard !Task.isCancelled else { return }
            sessions = refreshed.items
            nextCursor = refreshed.nextCursor
            loadedPageCount = refreshed.pageCount
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't refresh call sessions."
        }
    }

    private func loadMore() async {
        guard let cursor = nextCursor, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await client.fetchSessions(cursor: cursor, limit: pageSize)
            guard !Task.isCancelled else { return }
            let existing = Set(sessions.map(\.id))
            sessions.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            nextCursor = page.nextCursor
            loadedPageCount += 1
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't load more call sessions."
        }
    }
}

private struct TVSessionCard: View {
    let session: CallSession

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(session.startedAt, format: .dateTime.month(.abbreviated).day())
                    .font(TVMetrics.Font.cardTitle)
                Spacer(minLength: 10)
                Text(session.startedAt, format: .dateTime.hour().minute())
                    .font(TVMetrics.Font.rowValue)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Label("Booth \(session.boothId)", systemImage: "phone.fill")
                .font(TVMetrics.Font.body)
                .foregroundStyle(Theme.Colors.textPrimary)

            HStack(spacing: 26) {
                if let digits = session.digitsDialed, !digits.isEmpty {
                    Label(digits, systemImage: "number")
                }
                if let duration = DurationFormatter.shortString(milliseconds: session.durationMs) {
                    Label(duration, systemImage: "clock")
                }
            }
            .font(TVMetrics.Font.caption)
            .foregroundStyle(Theme.Colors.textSecondary)

            Text(session.outcome?.displayName ?? "In progress")
                .font(TVMetrics.Font.rowValue)
                .foregroundStyle(outcomeTint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var outcomeTint: Color {
        guard let outcome = session.outcome else { return Theme.Colors.accent }
        return outcome.isSuccess ? Theme.Colors.success : Theme.Colors.textSecondary
    }
}

struct TVSessionDetailView: View {
    let sessionId: String

    @State private var detail: CallSessionDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let client: OperatorClient

    init(sessionId: String, client: OperatorClient = .shared) {
        self.sessionId = sessionId
        self.client = client
    }

    var body: some View {
        TVScreen(title: "Session", systemImage: "phone.connection.fill") {
            if let errorMessage {
                TVBanner(message: errorMessage)
            }
            if let detail {
                summary(detail)
                events(detail.events)
            } else {
                loadingState
            }
        }
        .autoRefresh(every: .seconds(30)) {
            await load()
        }
    }

    private func summary(_ detail: CallSessionDetail) -> some View {
        TVFocusCard {
            VStack(alignment: .leading, spacing: 16) {
                TVCardHeader(title: "Summary", systemImage: "phone.fill")
                TVKeyValueRow(key: "Booth", value: detail.boothId)
                TVKeyValueRow(
                    key: "Started",
                    value: detail.startedAt.formatted(
                        .dateTime.month(.abbreviated).day().hour().minute().second()
                    )
                )
                if let endedAt = detail.endedAt {
                    TVKeyValueRow(
                        key: "Ended",
                        value: endedAt.formatted(
                            .dateTime.month(.abbreviated).day().hour().minute().second()
                        )
                    )
                }
                if let digits = detail.digitsDialed, !digits.isEmpty {
                    TVKeyValueRow(key: "Digits dialed", value: digits)
                }
                if let outcome = detail.outcome {
                    TVKeyValueRow(key: "Outcome", value: outcome.displayName)
                }
                if let duration = DurationFormatter.shortString(milliseconds: detail.durationMs) {
                    TVKeyValueRow(key: "Duration", value: duration)
                }
                if let recordingId = detail.recordingId {
                    TVKeyValueRow(key: "Recording", value: recordingId)
                }
            }
        }
    }

    @ViewBuilder
    private func events(_ events: [BoothEventRecord]) -> some View {
        if events.isEmpty {
            TVFocusCard {
                Text("No events recorded for this session.")
                    .font(TVMetrics.Font.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        } else {
            ForEach(events) { event in
                TVFocusCard {
                    HStack(alignment: .top, spacing: 22) {
                        Image(systemName: event.type.tvSymbol)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(event.type.tvTint)
                            .frame(width: 50)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(event.type.displayName)
                                .font(TVMetrics.Font.cardTitle)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(
                                event.occurredAt,
                                format: .dateTime.month(.abbreviated)
                                    .day().hour().minute().second()
                            )
                            .font(TVMetrics.Font.caption.monospacedDigit())
                            .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var loadingState: some View {
        TVFocusCard {
            HStack(spacing: 22) {
                if isLoading {
                    ProgressView()
                }
                Text(isLoading ? "Loading session details…" : "Session details unavailable")
                    .font(TVMetrics.Font.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await client.fetchSession(id: sessionId)
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't load this session."
        }
    }
}

#Preview {
    NavigationStack {
        TVSessionsView(client: .demo)
            .navigationDestination(for: String.self) { sessionId in
                TVSessionDetailView(sessionId: sessionId, client: .demo)
            }
    }
}

#endif
