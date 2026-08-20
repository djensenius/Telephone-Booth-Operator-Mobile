//
//  CallsTodayWidget.swift
//  TBOperatorMobileWidgets
//
//  Shows the booth's pickup volume for the day and highlights an
//  in-progress pickup when applicable. Tapping deep-links into the
//  read-only sessions list.
//

import SwiftUI
import WidgetKit

struct CallsTodayWidget: Widget {
    let kind = "CallsTodayWidget"

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
            CallsTodayWidgetView(entry: entry)
                .widgetURL(WidgetDeepLink.sessions)
        }
        .configurationDisplayName("Pickups today")
        .description("Pickups started today, plus any currently in progress.")
        .supportedFamilies(families)
    }
}

struct CallsTodayWidgetView: View {
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
                title: "Pickups",
                systemImage: "phone.connection",
                message: "Open the app to load pickup counts."
            )
        case .missingSection:
            WidgetUnavailableView(
                title: "Pickups",
                systemImage: "phone.connection",
                message: "Pickup counts not available yet."
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
            Label(inlineText(summary), systemImage: "phone.connection.fill")
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

    private func inlineText(_ summary: WidgetSnapshot.Summary) -> String {
        if summary.interactionsInProgress > 0 {
            return "\(summary.interactionsToday) pickups · \(summary.interactionsInProgress) live"
        }
        return "\(summary.interactionsToday) pickups today"
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
            header(summary, stale: stale)
            pickupCount(summary, size: 48)
            Spacer(minLength: 0)
            if summary.interactionsInProgress > 0 {
                Text("\(summary.interactionsInProgress) in progress")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.error)
                    .privacySensitive()
            } else {
                Text("None active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            WidgetUpdatedFooter(date: summary.refreshedAt, stale: stale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func mediumSystem(_ summary: WidgetSnapshot.Summary, stale: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                header(summary, stale: stale)
                pickupCount(summary, size: 52)
                Text("pickups today")
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
        VStack(alignment: .leading, spacing: 10) {
            header(summary, stale: stale)
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 1) {
                    pickupCount(summary, size: 72)
                    Text("pickups today")
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
            if let activity = entry.activityState.value {
                WidgetActivityTrendSection(activity: activity, height: 56)
            } else {
                Text("24-hour activity is not available yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                WidgetStatusBlock(
                    label: "Booth",
                    value: summary.boothState.widgetDisplayName,
                    systemImage: summary.boothState.widgetSymbol,
                    tint: summary.boothState.widgetTint
                )
                latestMessageBlock
                systemHealthBlock
            }
            Spacer(minLength: 0)
            WidgetUpdatedFooter(date: summary.refreshedAt, stale: stale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(
        _ summary: WidgetSnapshot.Summary,
        stale: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "phone.connection.fill")
                .foregroundStyle(.tint)
                .font(.title3.weight(.semibold))
                .widgetAccentable()
            Text("Pickups")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            if stale {
                WidgetStaleBadge()
            } else if summary.interactionsInProgress > 0 {
                Label("Live", systemImage: "dot.radiowaves.left.and.right")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Theme.Colors.error)
                    .symbolEffect(.pulse)
            }
        }
    }

    private func pickupCount(
        _ summary: WidgetSnapshot.Summary,
        size: CGFloat
    ) -> some View {
        Text("\(summary.interactionsToday)")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .monospacedDigit()
            .contentTransition(.numericText())
            .privacySensitive()
    }

    private func supportingMetrics(_ summary: WidgetSnapshot.Summary) -> [WidgetMetricValue] {
        [
            WidgetMetricValue(label: "Active", value: "\(summary.interactionsInProgress)"),
            WidgetMetricValue(label: "Pending", value: "\(summary.pendingMessages)"),
            WidgetMetricValue(label: "Received", value: "\(summary.receivedToday)"),
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
                detail: Text(message.occurredAt, style: .relative)
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
                privacySensitive: false
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
            Image(systemName: "phone.connection.fill")
                .font(.caption2)
            Text("\(summary.interactionsToday)")
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
        }
        .widgetAccentable()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .privacySensitive()
        .accessibilityLabel("\(summary.interactionsToday) pickups today")
    }

    private func rectangular(_ summary: WidgetSnapshot.Summary, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Pickups today", systemImage: "phone.connection.fill")
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            Text("\(summary.interactionsToday)")
                .font(.title.weight(.bold))
                .monospacedDigit()
                .privacySensitive()
            if stale {
                WidgetStaleBadge()
            } else if summary.interactionsInProgress > 0 {
                Text("\(summary.interactionsInProgress) in progress")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.Colors.error)
                    .privacySensitive()
            } else {
                Text("None active")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Pickups · small", as: .systemSmall) {
    CallsTodayWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
    WidgetSnapshotEntry.sample(minutesAgo: 45, treatAsFresh: false)
    WidgetSnapshotEntry.noSnapshot()
}

#Preview("Pickups · medium", as: .systemMedium) {
    CallsTodayWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
}

#Preview("Pickups · large", as: .systemLarge) {
    CallsTodayWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
}

#if os(iOS)
#Preview("Pickups · Lock Screen inline", as: .accessoryInline) {
    CallsTodayWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
}

#Preview("Pickups · Lock Screen circular", as: .accessoryCircular) {
    CallsTodayWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
}

#Preview("Pickups · Lock Screen rectangular", as: .accessoryRectangular) {
    CallsTodayWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
}
#endif
