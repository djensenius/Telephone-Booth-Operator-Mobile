//
//  BoothStatusWidget.swift
//  TBOperatorMobileWidgets
//
//  Shows the current booth state and last-updated timestamp. System
//  small/medium on every platform, plus iOS Lock Screen accessory
//  families. Tapping deep-links into the read-only dashboard.
//

import SwiftUI
import WidgetKit

struct BoothStatusWidget: Widget {
    let kind = "BoothStatusWidget"

    private var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular]
        #else
        [.systemSmall, .systemMedium]
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

    private func system(_ summary: WidgetSnapshot.Summary, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
            Text(summary.boothState.widgetDisplayName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .privacySensitive()
            Spacer(minLength: 0)
            WidgetUpdatedFooter(date: summary.boothUpdatedAt, stale: stale)
            if family == .systemMedium {
                Divider()
                HStack {
                    StatBlock(label: "Pickups", value: "\(summary.interactionsToday)")
                    Spacer()
                    StatBlock(label: "Pending", value: "\(summary.pendingMessages)")
                    Spacer()
                    StatBlock(label: "Clients", value: "\(summary.wsClients)")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
