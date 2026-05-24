//
//  PendingModerationWidget.swift
//  TBOperatorMobileWidgets
//
//  Shows how many messages are waiting for moderation. Tapping deep-links
//  into the Messages tab filtered to status "received".
//

import SwiftUI
import WidgetKit

struct PendingModerationWidget: Widget {
    let kind = "PendingModerationWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetSnapshotProvider()) { entry in
            PendingModerationWidgetView(entry: entry)
                .widgetURL(URL(string: "tboperator://messages?filter=received"))
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Pending moderation")
        .description("Number of messages waiting for review.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PendingModerationWidgetView: View {
    let entry: WidgetSnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            content(snapshot)
        } else {
            emptyState
        }
    }

    private func content(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full.fill")
                    .foregroundStyle(.tint)
                    .font(.title3.weight(.semibold))
                Text("Pending")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            Text("\(snapshot.pendingMessages)")
                .font(.system(size: family == .systemSmall ? 48 : 56, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText())
            Spacer(minLength: 0)
            HStack {
                Image(systemName: "calendar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(snapshot.receivedToday) received today")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(snapshot.generatedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Pending", systemImage: "tray")
                .font(.headline)
            Text("Open the app to load latest counts.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
