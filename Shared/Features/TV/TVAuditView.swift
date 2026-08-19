//
//  TVAuditView.swift
//  TelephoneBoothOperatorMobile
//
//  Admin-only, read-only audit trail for tvOS.
//

#if os(tvOS)

import Foundation
import SwiftUI

struct TVAuditView: View {
    @State private var entries: [AuditLogEntry] = []
    @State private var nextCursor: String?
    @State private var filter: TVAuditFilter = .all
    @State private var loadedFilter: TVAuditFilter?
    @State private var loadState: LoadState = .idle
    @State private var errorMessage: String?
    @State private var generation = 0
    @State private var loadedPageCount = 0

    private let client: OperatorClient
    private let pageSize: Int

    private enum LoadState: Equatable {
        case idle
        case loadingInitial
        case loadingMore
        case done
    }

    init(client: OperatorClient = .shared, pageSize: Int = 50) {
        self.client = client
        self.pageSize = pageSize
    }

    var body: some View {
        TVScreen(
            title: "Audit",
            systemImage: "list.bullet.rectangle.portrait",
            accessory: { countAccessory },
            content: {
                filterMenu

                if let errorMessage {
                    TVBanner(message: errorMessage)
                }

                if entries.isEmpty {
                    emptyState
                } else {
                    ForEach(entries) { entry in
                        TVAuditCard(entry: entry)
                    }
                }

                if nextCursor != nil {
                    loadMoreButton
                }
            }
        )
        .autoRefresh(id: filter, every: .seconds(30)) {
            if loadedFilter == filter {
                await refreshLoadedPages()
            } else {
                await loadFirstPage(discardingEntries: true)
            }
        }
    }

    @ViewBuilder
    private var countAccessory: some View {
        if !entries.isEmpty {
            VStack(alignment: .trailing, spacing: 2) {
                Text("Loaded")
                    .font(TVMetrics.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text("\(entries.count)")
                    .font(.system(size: 36, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            ForEach(TVAuditFilter.allCases) { option in
                Button {
                    filter = option
                } label: {
                    if filter == option {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            Label(filter.title, systemImage: "line.3.horizontal.decrease.circle")
                .font(.system(size: 30, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
        }
        .buttonStyle(TVSegmentButtonStyle(isSelected: filter != .all))
    }

    private var emptyState: some View {
        TVFocusCard {
            HStack(spacing: 22) {
                if loadState == .loadingInitial {
                    ProgressView()
                } else {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Text(loadState == .loadingInitial ? "Loading audit history…" : "No recorded actions")
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
                if loadState == .loadingMore {
                    ProgressView()
                }
                Text(loadState == .loadingMore ? "Loading…" : "Load more entries")
                    .font(.system(size: 30, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
        .buttonStyle(TVSegmentButtonStyle(isSelected: false))
        .disabled(loadState == .loadingInitial || loadState == .loadingMore)
    }

    private func loadFirstPage(discardingEntries discard: Bool) async {
        generation += 1
        let requested = generation
        let requestedFilter = filter
        loadState = .loadingInitial
        defer {
            if requested == generation, loadState == .loadingInitial {
                loadState = nextCursor == nil ? .done : .idle
            }
        }
        errorMessage = nil
        if discard {
            entries = []
            nextCursor = nil
            loadedPageCount = 0
        }
        do {
            let page = try await client.fetchAuditLogs(
                action: requestedFilter.prefix,
                limit: pageSize
            )
            guard requested == generation, !Task.isCancelled else { return }
            entries = page.items
            nextCursor = page.nextCursor
            loadedPageCount = 1
            loadedFilter = requestedFilter
            loadState = nextCursor == nil ? .done : .idle
        } catch {
            guard requested == generation, !Task.isCancelled else { return }
            errorMessage = Self.message(for: error, fallback: "Failed to load the audit log.")
            loadState = .idle
        }
    }

    private func refreshLoadedPages() async {
        guard loadState != .loadingInitial, loadState != .loadingMore else { return }
        generation += 1
        let requested = generation
        let requestedFilter = filter
        let pageCount = max(loadedPageCount, 1)
        loadState = .loadingInitial
        defer {
            if requested == generation, loadState == .loadingInitial {
                loadState = nextCursor == nil ? .done : .idle
            }
        }
        do {
            let refreshed = try await reloadLoadedPages(
                pageCount: pageCount,
                isCurrent: { requested == generation && filter == requestedFilter },
                fetchPage: { cursor in
                    let page = try await client.fetchAuditLogs(
                        action: requestedFilter.prefix,
                        cursor: cursor,
                        limit: pageSize
                    )
                    return (page.items, page.nextCursor)
                }
            )
            guard requested == generation, !Task.isCancelled else { return }
            entries = refreshed.items
            nextCursor = refreshed.nextCursor
            loadedPageCount = refreshed.pageCount
            errorMessage = nil
            loadState = nextCursor == nil ? .done : .idle
        } catch {
            guard requested == generation, !Task.isCancelled else { return }
            errorMessage = Self.message(
                for: error,
                fallback: "Failed to refresh the audit log."
            )
            loadState = nextCursor == nil ? .done : .idle
        }
    }

    private func loadMore() async {
        guard let cursor = nextCursor, loadState == .idle else { return }
        let requested = generation
        let requestedFilter = filter
        loadState = .loadingMore
        defer {
            if requested == generation, loadState == .loadingMore {
                loadState = .idle
            }
        }
        errorMessage = nil
        do {
            let page = try await client.fetchAuditLogs(
                action: requestedFilter.prefix,
                cursor: cursor,
                limit: pageSize
            )
            guard requested == generation,
                  requestedFilter == filter,
                  !Task.isCancelled else {
                return
            }
            entries.append(contentsOf: page.items)
            nextCursor = page.nextCursor
            loadedPageCount += 1
            loadState = nextCursor == nil ? .done : .idle
        } catch {
            guard requested == generation, !Task.isCancelled else { return }
            errorMessage = Self.message(for: error, fallback: "Failed to load more entries.")
            loadState = .idle
        }
    }

    private static func message(for error: any Error, fallback: String) -> String {
        switch error {
        case OperatorError.unauthenticated:
            "Sign in to view the audit log."
        case OperatorError.unauthorized(let body):
            problemCode(in: body) == "forbidden"
                ? "The audit log is available to administrators only."
                : "Your session has expired. Sign in again."
        case OperatorError.httpError(status: 403, body: _):
            "The audit log is available to administrators only."
        default:
            (error as? LocalizedError)?.errorDescription ?? fallback
        }
    }

    private static func problemCode(in body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["error"] as? String
    }
}

private enum TVAuditFilter: String, CaseIterable, Identifiable {
    case all
    case messages
    case questions
    case tokens
    case signIn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All actions"
        case .messages: "Messages"
        case .questions: "Questions"
        case .tokens: "Tokens"
        case .signIn: "Sign-in"
        }
    }

    var prefix: String? {
        switch self {
        case .all: nil
        case .messages: "message."
        case .questions: "question."
        case .tokens: "apiToken."
        case .signIn: "auth.login"
        }
    }
}

private struct TVAuditCard: View {
    let entry: AuditLogEntry

    var body: some View {
        TVFocusCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(entry.actionTitle)
                        .font(TVMetrics.Font.cardTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer(minLength: 18)
                    Text(outcome)
                        .font(TVMetrics.Font.rowValue)
                        .foregroundStyle(
                            entry.succeeded
                                ? Theme.Colors.textSecondary
                                : Theme.Colors.warning
                        )
                }
                Label(entry.actorLabel, systemImage: entry.actorType.symbolName)
                    .font(TVMetrics.Font.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(TVMetrics.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let metadata = entry.metadata, !metadata.isEmpty {
                    Text(metadataSummary(metadata))
                        .font(TVMetrics.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(3)
                }
            }
        }
    }

    private var outcome: String {
        if entry.succeeded { return "\(entry.statusCode)" }
        return entry.statusCode >= 500
            ? "failed \(entry.statusCode)"
            : "denied \(entry.statusCode)"
    }

    private var subtitle: String {
        var parts = [
            entry.createdAt.formatted(date: .abbreviated, time: .standard)
        ]
        if let address = entry.ip {
            parts.append(address)
        }
        parts.append("\(entry.method) \(entry.path)")
        return parts.joined(separator: " · ")
    }

    private func metadataSummary(
        _ metadata: [String: AuditMetadataValue]
    ) -> String {
        metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value.displayString)" }
            .joined(separator: " · ")
    }
}

#Preview {
    TVAuditView(client: .demo)
}

#endif
