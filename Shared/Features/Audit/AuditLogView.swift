//
//  AuditLogView.swift
//  TelephoneBoothOperatorMobile
//
//  Admin-only view of the operator audit trail (`/v1/audit-logs`): who took
//  each write action, from which address, and when. Not shown on watchOS or
//  tvOS, which have no admin workflow.
//

#if !os(watchOS) && !os(tvOS)

import SwiftUI

public struct AuditLogView: View {
    /// The action-family filters, in the order they appear in the picker.
    /// `nil` is "everything"; the rest are prefixes the operator matches
    /// server-side.
    enum ActionFilter: String, CaseIterable, Identifiable {
        case all
        case messages
        case questions
        case tokens
        case signIn

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "All"
            case .messages: "Messages"
            case .questions: "Questions"
            case .tokens: "Tokens"
            case .signIn: "Sign-in"
            }
        }

        /// The `action` prefix sent to the API.
        var prefix: String? {
            switch self {
            case .all: nil
            case .messages: "message."
            case .questions: "question."
            case .tokens: "apiToken."
            // `auth.login` rather than `auth.`, so this does not also pull in
            // sign-outs.
            case .signIn: "auth.login"
            }
        }
    }

    enum LoadState: Equatable {
        case idle
        case loadingInitial
        case loadingMore
        case done
    }

    @State private var entries: [AuditLogEntry] = []
    @State private var nextCursor: String?
    @State private var loadState: LoadState = .idle
    @State private var errorMessage: String?
    @State private var filter: ActionFilter = .all
    /// Bumped whenever a first page is requested, so a slow in-flight page
    /// cannot overwrite or append to the results of a newer one.
    @State private var generation = 0
    @State private var loadedPageCount = 0

    private let client: OperatorClient
    private let pageSize: Int

    public init(client: OperatorClient = .shared, pageSize: Int = 50) {
        self.client = client
        self.pageSize = pageSize
    }

    public var body: some View {
        Group {
            if loadState == .loadingInitial && entries.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    filterPicker
                    if entries.isEmpty {
                        emptyState
                    } else {
                        list
                    }
                }
            }
        }
        .background(Theme.Colors.background)
        .autoRefresh {
            await refreshLoadedPages()
        }
        .refreshableIfAvailable {
            await loadFirstPage()
        }
    }

    private var filterPicker: some View {
        Picker("Actions", selection: $filter) {
            ForEach(ActionFilter.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Theme.Spacing.medium)
        .padding(.vertical, Theme.Spacing.small)
        .onChange(of: filter) {
            Task { await loadFirstPage(discardingEntries: true) }
        }
    }

    private var list: some View {
        List {
            if let errorMessage {
                BannerView(message: errorMessage, kind: .error)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(entries) { entry in
                AuditLogRow(entry: entry)
                    .operatorListRowBackground()
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
            Image(
                systemName: errorMessage == nil
                    ? "list.bullet.rectangle.portrait"
                    : "exclamationmark.triangle"
            )
                .font(.system(size: 36))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(errorMessage == nil ? "No recorded actions" : "Couldn't load the audit log")
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

    /// Starting a first page also invalidates any in-flight `loadMore`: its
    /// cursor belongs to a page boundary that is about to move.
    private func loadFirstPage(discardingEntries discard: Bool = false) async {
        generation += 1
        let requested = generation
        loadState = .loadingInitial
        errorMessage = nil
        if discard {
            entries = []
            nextCursor = nil
            loadedPageCount = 0
        }
        do {
            let page = try await client.fetchAuditLogs(action: filter.prefix, limit: pageSize)
            guard requested == generation else { return }
            entries = page.items
            nextCursor = page.nextCursor
            loadedPageCount = 1
            loadState = nextCursor == nil ? .done : .idle
        } catch {
            guard requested == generation else { return }
            // A failed refresh keeps what is already on screen; only a filter
            // change makes the visible entries wrong.
            errorMessage = Self.message(for: error, fallback: "Failed to load the audit log.")
            loadState = .idle
        }
    }

    private func refreshLoadedPages() async {
        guard loadState != .loadingInitial, loadState != .loadingMore else { return }
        generation += 1
        let requested = generation
        let pageCount = max(loadedPageCount, 1)
        let action = filter.prefix
        loadState = .loadingInitial
        do {
            let refreshed = try await reloadLoadedPages(
                pageCount: pageCount,
                isCurrent: { requested == generation },
                fetchPage: { cursor in
                    let page = try await client.fetchAuditLogs(
                        action: action,
                        cursor: cursor,
                        limit: pageSize
                    )
                    return (page.items, page.nextCursor)
                }
            )
            guard requested == generation else { return }
            guard !Task.isCancelled else {
                loadState = nextCursor == nil ? .done : .idle
                return
            }
            entries = refreshed.items
            nextCursor = refreshed.nextCursor
            loadedPageCount = refreshed.pageCount
            errorMessage = nil
            loadState = nextCursor == nil ? .done : .idle
        } catch {
            guard requested == generation else { return }
            loadState = nextCursor == nil ? .done : .idle
            guard !Task.isCancelled else { return }
            errorMessage = Self.message(for: error, fallback: "Failed to refresh the audit log.")
        }
    }

    private func loadMore() async {
        // Only from idle: a refresh in flight is about to move the page
        // boundary this cursor points at.
        guard let cursor = nextCursor, loadState == .idle else { return }
        let requested = generation
        loadState = .loadingMore
        errorMessage = nil
        do {
            let page = try await client.fetchAuditLogs(
                action: filter.prefix,
                cursor: cursor,
                limit: pageSize
            )
            guard requested == generation else { return }
            entries.append(contentsOf: page.items)
            nextCursor = page.nextCursor
            loadedPageCount += 1
            loadState = nextCursor == nil ? .done : .idle
        } catch {
            guard requested == generation else { return }
            errorMessage = Self.message(for: error, fallback: "Failed to load more entries.")
            loadState = .idle
        }
    }

    /// The trail is admin-only, so a rejection needs to say which kind it is.
    /// The client collapses 401 and 403 into `.unauthorized`, so they are told
    /// apart by the problem code in the body: an expired sign-in is not a
    /// privileges problem, and the wrong message sends people hunting.
    static func message(for error: any Error, fallback: String) -> String {
        switch error {
        case OperatorError.unauthenticated:
            return "Sign in to view the audit log."
        case OperatorError.unauthorized(let body):
            return problemCode(in: body) == "forbidden"
                ? "The audit log is available to administrators only."
                : "Your session has expired. Sign in again."
        case OperatorError.httpError(status: 403, body: _):
            return "The audit log is available to administrators only."
        default:
            return (error as? LocalizedError)?.errorDescription ?? fallback
        }
    }

    /// `{"error":"forbidden", …}` → `forbidden`.
    private static func problemCode(in body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["error"] as? String
    }
}

struct AuditLogRow: View {
    let entry: AuditLogEntry

    /// A 4xx is a refusal; a 5xx is the server falling over. Calling both
    /// "denied" would misreport the outcome the trail exists to record.
    static func outcomeLabel(for entry: AuditLogEntry) -> String {
        if entry.succeeded { return "\(entry.statusCode)" }
        return entry.statusCode >= 500 ? "failed \(entry.statusCode)" : "denied \(entry.statusCode)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                Text(entry.actionTitle)
                    .font(Theme.Fonts.bodyLarge)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text(Self.outcomeLabel(for: entry))
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(
                        entry.succeeded ? Theme.Colors.textSecondary : Theme.Colors.warning
                    )
            }
            HStack(spacing: Theme.Spacing.small) {
                Image(systemName: entry.actorType.symbolName)
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(entry.actorLabel)
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
            }
            Text(subtitle)
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
            if let metadata = entry.metadata, !metadata.isEmpty {
                Text(Self.metadataSummary(metadata))
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, Theme.Spacing.small)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    static func metadataSummary(_ metadata: [String: AuditMetadataValue]) -> String {
        metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value.displayString)" }
            .joined(separator: " · ")
    }

    /// Who, from where, when — the three things the trail exists to answer.
    private var subtitle: String {
        var parts = [entry.createdAt.formatted(date: .abbreviated, time: .standard)]
        if let address = entry.ip { parts.append(address) }
        parts.append("\(entry.method) \(entry.path)")
        return parts.joined(separator: " · ")
    }

    /// Everything the row shows, in reading order, so VoiceOver users are not
    /// missing the request or its detail.
    var accessibilityLabel: String {
        let outcome: String
        if entry.succeeded {
            outcome = "succeeded"
        } else if entry.statusCode >= 500 {
            outcome = "failed with \(entry.statusCode)"
        } else {
            outcome = "was denied with \(entry.statusCode)"
        }
        var parts = ["\(entry.actionTitle) by \(entry.actorLabel)"]
        if let address = entry.ip { parts.append("from \(address)") }
        parts.append(outcome)
        parts.append("\(entry.method) \(entry.path)")
        parts.append(entry.createdAt.formatted(date: .abbreviated, time: .standard))
        if let metadata = entry.metadata, !metadata.isEmpty {
            parts.append(Self.metadataSummary(metadata))
        }
        return parts.joined(separator: ", ")
    }
}

#endif
