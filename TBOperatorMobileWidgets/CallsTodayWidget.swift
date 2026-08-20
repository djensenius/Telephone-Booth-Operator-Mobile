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
        [.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular]
        #else
        [.systemSmall, .systemMedium]
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

    private func system(_ summary: WidgetSnapshot.Summary, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
            Text("\(summary.interactionsToday)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .privacySensitive()
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
