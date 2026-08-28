//
//  LatestMessageWidget.swift
//  TBOperatorMobileWidgets
//
//  Surfaces only the *metadata* of the most recent message: its
//  identifier, moderation status, and received/created time. Transcript
//  text, translations, moderation reasons, notes, and audio never enter
//  the snapshot, so they can never be rendered here. Tapping opens the
//  exact message detail for review.
//

import SwiftUI
import WidgetKit

struct LatestMessageWidget: Widget {
    let kind = "LatestMessageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetSnapshotProvider()) { entry in
            LatestMessageWidgetView(entry: entry)
                .widgetURL(entry.latestMessageState.value.flatMap { WidgetDeepLink.message(id: $0.id) })
        }
        .configurationDisplayName("Latest message")
        .description("Status and time of the most recent message. No transcript is shown.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct LatestMessageWidgetView: View {
    let entry: WidgetSnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetContainerBackground(family)
    }

    @ViewBuilder
    private var content: some View {
        switch entry.latestMessageState {
        case .noSnapshot:
            WidgetUnavailableView(
                title: "Latest message",
                systemImage: "waveform",
                message: "Open the app to load recent messages."
            )
        case .missingSection:
            WidgetUnavailableView(
                title: "Latest message",
                systemImage: "waveform",
                message: "No messages recorded yet."
            )
        case let .current(message, _):
            layout(message, stale: false)
        case let .stale(message, _):
            layout(message, stale: true)
        }
    }

    @ViewBuilder
    private func layout(_ message: WidgetSnapshot.LatestMessage, stale: Bool) -> some View {
        switch family.operatorLayoutSize {
        case .medium:
            mediumLayout(message, stale: stale)
        case .large, .extraLarge:
            largeLayout(message, stale: stale)
        default:
            compactLayout(message, stale: stale)
        }
    }

    private func compactLayout(
        _ message: WidgetSnapshot.LatestMessage,
        stale: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(stale: stale)
            Spacer(minLength: 0)
            statusBadge(message.status)
            Spacer(minLength: 0)
            receivedBlock(message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func mediumLayout(
        _ message: WidgetSnapshot.LatestMessage,
        stale: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                header(stale: stale)
                statusBadge(message.status)
                receivedBlock(message)
                Spacer(minLength: 0)
                WidgetUpdatedFooter(date: message.refreshedAt, stale: stale)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            Divider()
            if let summary = entry.summaryState.value {
                WidgetMetricGrid(
                    metrics: summaryMetrics(summary),
                    columns: 2,
                    compact: true,
                    staleAsOf: entry.summaryState.staleAsOf
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                WidgetStatusBlock(
                    label: "Booth",
                    value: "Unavailable",
                    systemImage: "phone.connection"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func largeLayout(
        _ message: WidgetSnapshot.LatestMessage,
        stale: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(stale: stale)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    statusBadge(message.status)
                    receivedBlock(message)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                boothStatusBlock
                systemHealthBlock
            }
            Divider()
            if let summary = entry.summaryState.value {
                WidgetMetricGrid(
                    metrics: summaryMetrics(summary),
                    columns: 4,
                    staleAsOf: entry.summaryState.staleAsOf
                )
            }
            if let activity = entry.activityState.value {
                WidgetActivityTrendSection(
                    activity: activity,
                    height: 54,
                    staleAsOf: entry.activityState.staleAsOf
                )
            }
            Spacer(minLength: 0)
            WidgetUpdatedFooter(date: message.refreshedAt, stale: stale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(stale: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
                .widgetAccentable()
            WidgetHeaderTitle(title: "Latest message")
            Spacer(minLength: 4)
            if stale { WidgetStaleBadge() }
        }
    }

    private func receivedBlock(_ message: WidgetSnapshot.LatestMessage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Received")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(message.occurredAt, style: .relative)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .privacySensitive()
        }
        .accessibilityElement(children: .combine)
    }

    private func summaryMetrics(_ summary: WidgetSnapshot.Summary) -> [WidgetMetricValue] {
        [
            WidgetMetricValue(label: "Pending", value: "\(summary.pendingMessages)"),
            WidgetMetricValue(label: "Pickups", value: "\(summary.interactionsToday)"),
            WidgetMetricValue(label: "Received", value: "\(summary.receivedToday)"),
            WidgetMetricValue(label: "Clients", value: "\(summary.wsClients)")
        ]
    }

    @ViewBuilder
    private var boothStatusBlock: some View {
        if let summary = entry.summaryState.value {
            WidgetStatusBlock(
                label: "Booth",
                value: summary.boothState.widgetDisplayName,
                systemImage: summary.boothState.widgetSymbol,
                tint: summary.boothState.widgetTint,
                detail: Text(summary.boothUpdatedAt, style: .relative),
                staleAsOf: entry.summaryState.staleAsOf
            )
        } else {
            WidgetStatusBlock(
                label: "Booth",
                value: "Unavailable",
                systemImage: "phone.connection"
            )
        }
    }

    @ViewBuilder
    private var systemHealthBlock: some View {
        if let health = entry.systemHealthState.value {
            let severity = health.effectiveSeverity(at: entry.date)
            WidgetStatusBlock(
                label: "System",
                value: severity.displayName,
                systemImage: severity.symbolName,
                tint: severity.tint,
                detail: Text(health.sourceUpdatedAt, style: .relative),
                privacySensitive: false,
                staleAsOf: entry.systemHealthState.staleAsOf
            )
        } else {
            WidgetStatusBlock(
                label: "System",
                value: "Unavailable",
                systemImage: "cpu",
                privacySensitive: false
            )
        }
    }

    private func statusBadge(_ status: MessageStatus) -> some View {
        HStack(spacing: 8) {
            Image(systemName: status.widgetSymbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(status.widgetTint)
                .widgetAccentable()
            Text(status.displayName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .privacySensitive()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status \(status.displayName)")
    }
}

extension MessageStatus {
    var widgetSymbol: String {
        switch self {
        case .uploading: return "icloud.and.arrow.up"
        case .received: return "tray.and.arrow.down.fill"
        case .pending: return "clock.badge.questionmark"
        case .approved: return "checkmark.seal.fill"
        case .rejected: return "xmark.seal.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var widgetTint: Color {
        switch self {
        case .approved: return Theme.Colors.success
        case .rejected: return Theme.Colors.error
        case .pending, .received: return Theme.Colors.warning
        case .uploading: return Theme.Colors.info
        case .unknown: return .secondary
        }
    }
}

#Preview("Latest message · small", as: .systemSmall) {
    LatestMessageWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
    WidgetSnapshotEntry.sample(minutesAgo: 45, treatAsFresh: false)
    WidgetSnapshotEntry.emptySections()
}

#Preview("Latest message · medium", as: .systemMedium) {
    LatestMessageWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
    WidgetSnapshotEntry.noSnapshot()
}

#Preview("Latest message · large", as: .systemLarge) {
    LatestMessageWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
}
