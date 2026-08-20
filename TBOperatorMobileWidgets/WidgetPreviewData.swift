//
//  WidgetPreviewData.swift
//  TBOperatorMobileWidgets
//
//  Sample entries used only by `#Preview` blocks. Kept in one place so
//  every widget can render current / stale / empty states without
//  duplicating fixture construction.
//

import Foundation

extension WidgetSnapshotEntry {
    /// A fully-populated entry. `treatAsFresh` forces the placeholder path
    /// (never stale); set it false with a large `minutesAgo` to preview the
    /// stale treatment.
    static func sample(
        minutesAgo: Double = 4,
        treatAsFresh: Bool = true,
        at date: Date = .now
    ) -> WidgetSnapshotEntry {
        let refreshed = date.addingTimeInterval(-minutesAgo * 60)
        let snapshot = WidgetSnapshot(
            summary: WidgetSnapshot.Summary(
                boothState: .recording,
                boothUpdatedAt: refreshed,
                pendingMessages: 3,
                receivedToday: 7,
                interactionsToday: 5,
                interactionsInProgress: 1,
                wsClients: 2,
                runtimeMode: nil,
                sourceGeneratedAt: refreshed,
                refreshedAt: refreshed
            ),
            latestMessage: WidgetSnapshot.LatestMessage(
                id: "9f8c2b10",
                status: .received,
                occurredAt: refreshed,
                refreshedAt: refreshed
            ),
            systemHealth: WidgetSnapshot.SystemHealth(
                boothId: "booth",
                severity: .warning,
                cpuTemperatureCelsius: 63,
                memoryUsedRatio: 0.72,
                routerTemperatureCelsius: 51,
                tailscaleConnected: true,
                sourceUpdatedAt: refreshed,
                refreshedAt: refreshed
            ),
            activity: WidgetSnapshot.Activity(
                pickups: 22,
                messages: 9,
                buckets: (0..<24).map { hour in
                    WidgetSnapshot.ActivityBucket(
                        hour: hour,
                        pickups: max(0, (hour * 7) % 6 - 1),
                        messages: (hour * 3) % 4
                    )
                },
                rangeStart: date.addingTimeInterval(-24 * 3600),
                rangeEnd: date,
                refreshedAt: refreshed
            ),
            writtenAt: refreshed
        )
        return WidgetSnapshotEntry(date: date, snapshot: snapshot, isPlaceholder: treatAsFresh)
    }

    /// An entry whose snapshot exists but has no populated sections.
    static func emptySections(at date: Date = .now) -> WidgetSnapshotEntry {
        WidgetSnapshotEntry(date: date, snapshot: WidgetSnapshot(writtenAt: date))
    }

    /// An entry with no snapshot written at all.
    static func noSnapshot(at date: Date = .now) -> WidgetSnapshotEntry {
        WidgetSnapshotEntry(date: date, snapshot: nil)
    }
}
