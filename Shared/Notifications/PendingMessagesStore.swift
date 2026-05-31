//
//  PendingMessagesStore.swift
//  TelephoneBoothOperatorMobile
//
//  Keeps the "messages awaiting moderation" count fresh so the app-icon
//  badge and the Messages tab badge stay current without the operator
//  having to open a specific screen.
//
//  Two refresh drivers feed the same store:
//    - a lightweight poll loop (every `pollInterval`) while the signed-in
//      shell is on screen, and
//    - explicit refreshes triggered when the app returns to the foreground
//      or when a push notification is received/tapped.
//
//  The count comes from `/v1/stats/summary`'s `messages.awaitingModeration`
//  (falling back to `pending` for older operator builds). The same value is
//  pushed to the app-icon badge via `UNUserNotificationCenter` and mirrored
//  into the widget snapshot.
//

import Foundation
import UserNotifications
import os

@MainActor
@Observable
public final class PendingMessagesStore {
    public static let shared = PendingMessagesStore()

    /// Number of messages awaiting moderation — the badge value.
    public private(set) var pendingCount: Int = 0

    private let logger = Logger(
        subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
        category: "PendingMessages"
    )

    /// How often the poll loop refreshes while the shell is visible.
    private let pollInterval: Duration = .seconds(25)
    private var pollingTask: Task<Void, Never>?

    private init() {}

    /// Starts the background poll loop. Idempotent: a second call while a
    /// loop is already running (e.g. a second iPad window) is a no-op.
    public func startPolling(using client: OperatorClient) {
        if let pollingTask, !pollingTask.isCancelled { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(using: client)
                do {
                    try await Task.sleep(for: self?.pollInterval ?? .seconds(25))
                } catch {
                    break
                }
            }
        }
    }

    /// Stops polling and clears the badge. Call on sign-out.
    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        Task { await applyCount(0, stats: nil) }
    }

    /// Fetches the latest count once and updates the badge + widget snapshot.
    public func refresh(using client: OperatorClient) async {
        do {
            let stats = try await client.fetchStatsSummary()
            await applyCount(stats.messages.badgeCount, stats: stats)
        } catch {
            // Transient failures (offline, token refresh) are expected; keep
            // the last known count rather than zeroing the badge.
            logger.debug("Pending-count refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func applyCount(_ count: Int, stats: StatsSummary?) async {
        pendingCount = count
        if let stats {
            WidgetSnapshotStore.write(WidgetSnapshot(stats: stats))
        }
        await setApplicationBadge(count)
    }

    private func setApplicationBadge(_ count: Int) async {
        #if !os(watchOS)
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(count)
        } catch {
            logger.debug("Failed to set app badge: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }
}
