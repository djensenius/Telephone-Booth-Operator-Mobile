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
        .task {
            if entries.isEmpty {
                await loadFirstPage()
            }
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
            Task { await loadFirstPage() }
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
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("No recorded actions")
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
            let page = try await client.fetchAuditLogs(action: filter.prefix, limit: pageSize)
            entries = page.items
            nextCursor = page.nextCursor
            loadState = nextCursor == nil ? .done : .idle
        } catch {
            entries = []
            nextCursor = nil
            errorMessage = Self.message(for: error, fallback: "Failed to load the audit log.")
            loadState = .idle
        }
    }

    private func loadMore() async {
        guard let cursor = nextCursor, loadState != .loadingMore else { return }
        loadState = .loadingMore
        errorMessage = nil
        do {
            let page = try await client.fetchAuditLogs(
                action: filter.prefix,
                cursor: cursor,
                limit: pageSize
            )
            entries.append(contentsOf: page.items)
            nextCursor = page.nextCursor
            loadState = nextCursor == nil ? .done : .idle
        } catch {
            errorMessage = Self.message(for: error, fallback: "Failed to load more entries.")
            loadState = .idle
        }
    }

    /// The trail is admin-only, so a rejection here is a permissions problem
    /// rather than a failure worth retrying.
    static func message(for error: any Error, fallback: String) -> String {
        switch error {
        case OperatorError.unauthorized,
             OperatorError.httpError(status: 403, body: _):
            return "The audit log is available to administrators only."
        default:
            return (error as? LocalizedError)?.errorDescription ?? fallback
        }
    }
}

struct AuditLogRow: View {
    let entry: AuditLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                Text(entry.actionTitle)
                    .font(Theme.Fonts.bodyLarge)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text(entry.succeeded ? "\(entry.statusCode)" : "denied \(entry.statusCode)")
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

    private var accessibilityLabel: String {
        let outcome = entry.succeeded ? "succeeded" : "was denied with \(entry.statusCode)"
        let from = entry.ip.map { " from \($0)" } ?? ""
        return "\(entry.actionTitle) by \(entry.actorLabel)\(from), \(outcome), "
            + entry.createdAt.formatted(date: .abbreviated, time: .standard)
    }
}

#endif
