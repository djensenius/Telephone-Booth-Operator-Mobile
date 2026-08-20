//
//  PendingModerationWidget.swift
//  TBOperatorMobileWidgets
//
//  Shows how many messages are waiting for moderation. Tapping deep-links
//  into the Messages tab filtered to the review queue.
//

import SwiftUI
import WidgetKit

struct PendingModerationWidget: Widget {
    let kind = "PendingModerationWidget"

    private var families: [WidgetFamily] {
        #if os(iOS)
        [
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ]
        #else
        [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetSnapshotProvider()) { entry in
            PendingModerationWidgetView(entry: entry)
                .widgetURL(WidgetDeepLink.messagesReview)
        }
        .configurationDisplayName("Pending moderation")
        .description("Number of messages waiting for review.")
        .supportedFamilies(families)
    }
}

struct PendingModerationWidgetView: View {
    let entry: WidgetSnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetContainerBackground(family)
    }

    @ViewBuilder
    private var content: some View {
        switch entry.summaryState {
        case .noSnapshot:
            WidgetUnavailableView(
                title: "Pending",
                systemImage: "tray",
                message: "Open the app to load the review queue."
            )
        case .missingSection:
            WidgetUnavailableView(
                title: "Pending",
                systemImage: "tray",
                message: "Review queue not available yet."
            )
        case let .current(summary, _):
            layout(summary, stale: false)
        case let .stale(summary, _):
            layout(summary, stale: true)
        }
    }

    @ViewBuilder
    private func layout(_ summary: WidgetSnapshot.Summary, stale: Bool) -> some View {
        #if os(iOS)
        switch family {
        case .accessoryInline:
            Label("\(summary.pendingMessages) pending", systemImage: "tray.full.fill")
                .privacySensitive()
        case .accessoryCircular:
            circular(summary)
        case .accessoryRectangular:
            rectangular(summary, stale: stale)
        default:
            system(summary, stale: stale)
        }
        #else
        system(summary, stale: stale)
        #endif
    }

    @ViewBuilder
    private func system(_ summary: WidgetSnapshot.Summary, stale: Bool) -> some View {
        switch family.operatorLayoutSize {
        case .medium:
            mediumSystem(summary, stale: stale)
        case .large, .extraLarge:
            largeSystem(summary, stale: stale)
        default:
            compactSystem(summary, stale: stale)
        }
    }

    private func compactSystem(_ summary: WidgetSnapshot.Summary, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(stale: stale)
            pendingCount(summary, size: 48)
            Spacer(minLength: 0)
            HStack {
                Image(systemName: "calendar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(summary.receivedToday) received today")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            }
            WidgetUpdatedFooter(date: summary.refreshedAt, stale: stale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func mediumSystem(_ summary: WidgetSnapshot.Summary, stale: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                header(stale: stale)
                pendingCount(summary, size: 52)
                Text("waiting for review")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                WidgetUpdatedFooter(date: summary.refreshedAt, stale: stale)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            Divider()
            WidgetMetricGrid(
                metrics: supportingMetrics(summary),
                columns: 2,
                compact: true
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func largeSystem(_ summary: WidgetSnapshot.Summary, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(stale: stale)
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 1) {
                    pendingCount(summary, size: 72)
                    Text("waiting for review")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                WidgetMetricGrid(
                    metrics: supportingMetrics(summary),
                    columns: 4
                )
                .frame(maxWidth: .infinity)
            }
            Divider()
            HStack(alignment: .top, spacing: 16) {
                WidgetStatusBlock(
                    label: "Booth",
                    value: summary.boothState.widgetDisplayName,
                    systemImage: summary.boothState.widgetSymbol,
                    tint: summary.boothState.widgetTint,
                    detail: Text(summary.boothUpdatedAt, style: .relative)
                )
                latestMessageBlock
                systemHealthBlock
            }
            Spacer(minLength: 0)
            WidgetUpdatedFooter(date: summary.refreshedAt, stale: stale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(stale: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full.fill")
                .foregroundStyle(.tint)
                .font(.title3.weight(.semibold))
                .widgetAccentable()
            Text("Pending")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            if stale { WidgetStaleBadge() }
        }
    }

    private func pendingCount(
        _ summary: WidgetSnapshot.Summary,
        size: CGFloat
    ) -> some View {
        Text("\(summary.pendingMessages)")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .monospacedDigit()
            .contentTransition(.numericText())
            .privacySensitive()
    }

    private func supportingMetrics(_ summary: WidgetSnapshot.Summary) -> [WidgetMetricValue] {
        [
            WidgetMetricValue(label: "Received", value: "\(summary.receivedToday)"),
            WidgetMetricValue(label: "Pickups", value: "\(summary.interactionsToday)"),
            WidgetMetricValue(label: "Live", value: "\(summary.interactionsInProgress)"),
            WidgetMetricValue(label: "Clients", value: "\(summary.wsClients)")
        ]
    }

    @ViewBuilder
    private var latestMessageBlock: some View {
        if let message = entry.latestMessageState.value {
            WidgetStatusBlock(
                label: "Latest message",
                value: message.status.displayName,
                systemImage: "waveform",
                tint: message.status.widgetTint,
                detail: Text(message.occurredAt, style: .relative),
                staleAsOf: entry.latestMessageState.staleAsOf
            )
        } else {
            WidgetStatusBlock(
                label: "Latest message",
                value: "None yet",
                systemImage: "waveform"
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

    private func circular(_ summary: WidgetSnapshot.Summary) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "tray.full.fill")
                .font(.caption2)
            Text("\(summary.pendingMessages)")
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
        }
        .widgetAccentable()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .privacySensitive()
        .accessibilityLabel("\(summary.pendingMessages) messages pending review")
    }

    private func rectangular(_ summary: WidgetSnapshot.Summary, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Pending review", systemImage: "tray.full.fill")
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            Text("\(summary.pendingMessages)")
                .font(.title.weight(.bold))
                .monospacedDigit()
                .privacySensitive()
            if stale {
                WidgetStaleBadge()
            } else {
                Text("\(summary.receivedToday) received today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Pending · small", as: .systemSmall) {
    PendingModerationWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
    WidgetSnapshotEntry.sample(minutesAgo: 45, treatAsFresh: false)
    WidgetSnapshotEntry.noSnapshot()
}

#Preview("Pending · medium", as: .systemMedium) {
    PendingModerationWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
}

#Preview("Pending · large", as: .systemLarge) {
    PendingModerationWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
}

#if os(iOS)
#Preview("Pending · Lock Screen inline", as: .accessoryInline) {
    PendingModerationWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
}

#Preview("Pending · Lock Screen circular", as: .accessoryCircular) {
    PendingModerationWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
}

#Preview("Pending · Lock Screen rectangular", as: .accessoryRectangular) {
    PendingModerationWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
}
#endif
