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
        [.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular]
        #else
        [.systemSmall, .systemMedium]
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

    private func system(_ summary: WidgetSnapshot.Summary, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
            Text("\(summary.pendingMessages)")
                .font(.system(size: family == .systemSmall ? 48 : 56, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .privacySensitive()
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
