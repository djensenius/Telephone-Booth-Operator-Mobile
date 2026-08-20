//
//  BoothStatusWidget.swift
//  TBOperatorMobileWidgets
//
//  Shows the current booth state and last-updated timestamp. System
//  small/medium/large on every platform, plus iOS Lock Screen accessory
//  families. Tapping deep-links into the read-only dashboard.
//

import SwiftUI
import WidgetKit

struct BoothStatusWidget: Widget {
    let kind = "BoothStatusWidget"

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
            BoothStatusWidgetView(entry: entry)
                .widgetURL(WidgetDeepLink.dashboard)
        }
        .configurationDisplayName("Booth status")
        .description("Current state of the operator booth.")
        .supportedFamilies(families)
    }
}

struct BoothStatusWidgetView: View {
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
                title: "Booth",
                systemImage: "phone.connection",
                message: "Open the app to load booth status."
            )
        case .missingSection:
            WidgetUnavailableView(
                title: "Booth",
                systemImage: "phone.connection",
                message: "Booth status not available yet."
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
            Label(summary.boothState.widgetDisplayName, systemImage: summary.boothState.widgetSymbol)
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
        VStack(alignment: .leading, spacing: 8) {
            header(summary, stale: stale)
            stateTitle(summary)
            Spacer(minLength: 0)
            WidgetUpdatedFooter(date: summary.boothUpdatedAt, stale: stale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func mediumSystem(_ summary: WidgetSnapshot.Summary, stale: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                header(summary, stale: stale)
                stateTitle(summary)
                Spacer(minLength: 0)
                WidgetUpdatedFooter(date: summary.boothUpdatedAt, stale: stale)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            Divider()
            WidgetMetricGrid(
                metrics: summaryMetrics(summary),
                columns: 2,
                compact: true
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func largeSystem(_ summary: WidgetSnapshot.Summary, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(summary, stale: stale)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                stateTitle(summary, font: .title.weight(.semibold))
                Spacer(minLength: 8)
                WidgetUpdatedFooter(date: summary.boothUpdatedAt, stale: stale)
            }
            Divider()
            WidgetMetricGrid(metrics: summaryMetrics(summary), columns: 4)
            Divider()
            HStack(alignment: .top, spacing: 16) {
                relatedHealth
                Divider()
                relatedMessage
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ summary: WidgetSnapshot.Summary, stale: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: summary.boothState.widgetSymbol)
                .foregroundStyle(summary.boothState.widgetTint)
                .font(.title3.weight(.semibold))
                .widgetAccentable()
            Text("Booth")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            if stale {
                WidgetStaleBadge()
            } else if let mode = summary.runtimeMode, mode.shouldDisplayBadge {
                RuntimeModeBadge(mode: mode)
            }
        }
    }

    private func stateTitle(
        _ summary: WidgetSnapshot.Summary,
        font: Font = .title2.weight(.semibold)
    ) -> some View {
        Text(summary.boothState.widgetDisplayName)
            .font(font)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .privacySensitive()
    }

    private func summaryMetrics(_ summary: WidgetSnapshot.Summary) -> [WidgetMetricValue] {
        [
            WidgetMetricValue(label: "Pickups", value: "\(summary.interactionsToday)"),
            WidgetMetricValue(label: "Pending", value: "\(summary.pendingMessages)"),
            WidgetMetricValue(label: "Received", value: "\(summary.receivedToday)"),
            WidgetMetricValue(label: "Clients", value: "\(summary.wsClients)")
        ]
    }

    @ViewBuilder
    private var relatedHealth: some View {
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

    @ViewBuilder
    private var relatedMessage: some View {
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

    private func circular(_ summary: WidgetSnapshot.Summary) -> some View {
        Image(systemName: summary.boothState.widgetSymbol)
            .font(.title2)
            .widgetAccentable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .privacySensitive()
            .accessibilityLabel("Booth \(summary.boothState.widgetDisplayName)")
    }

    private func rectangular(_ summary: WidgetSnapshot.Summary, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Booth", systemImage: summary.boothState.widgetSymbol)
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            Text(summary.boothState.widgetDisplayName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .privacySensitive()
            if stale {
                WidgetStaleBadge()
            } else {
                Text(summary.boothUpdatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Booth · small", as: .systemSmall) {
    BoothStatusWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
    WidgetSnapshotEntry.sample(minutesAgo: 45, treatAsFresh: false)
    WidgetSnapshotEntry.noSnapshot()
}

#Preview("Booth · medium", as: .systemMedium) {
    BoothStatusWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
    WidgetSnapshotEntry.emptySections()
}

#Preview("Booth · large", as: .systemLarge) {
    BoothStatusWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
}

#if os(iOS)
#Preview("Booth · Lock Screen inline", as: .accessoryInline) {
    BoothStatusWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
}

#Preview("Booth · Lock Screen circular", as: .accessoryCircular) {
    BoothStatusWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
}

#Preview("Booth · Lock Screen rectangular", as: .accessoryRectangular) {
    BoothStatusWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
}
#endif
