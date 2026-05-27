//
//  BoothStatusWidget.swift
//  TBOperatorMobileWidgets
//
//  Shows the current booth state and last-updated timestamp. Small +
//  medium families. Tapping the widget deep-links into the dashboard
//  (handled by the main app's URL handler).
//

import SwiftUI
import WidgetKit

struct BoothStatusWidget: Widget {
    let kind = "BoothStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetSnapshotProvider()) { entry in
            BoothStatusWidgetView(entry: entry)
                .widgetURL(URL(string: "tboperator://dashboard"))
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Booth status")
        .description("Current state of the operator booth.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BoothStatusWidgetView: View {
    let entry: WidgetSnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            content(snapshot)
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: snapshot.boothState.widgetSymbol)
                    .foregroundStyle(snapshot.boothState.widgetTint)
                    .font(.title3.weight(.semibold))
                    .privacySensitive()
                Text("Booth")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if let mode = snapshot.runtimeMode, mode.shouldDisplayBadge {
                    RuntimeModeBadge(mode: mode)
                }
            }
            Text(snapshot.boothState.widgetDisplayName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .privacySensitive()
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text("Updated")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(snapshot.boothUpdatedAt, style: .relative)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .privacySensitive()
            }
            if family == .systemMedium {
                Divider()
                HStack {
                    StatBlock(label: "Calls today", value: "\(snapshot.callsToday)")
                    Spacer()
                    StatBlock(label: "Pending", value: "\(snapshot.pendingMessages)")
                    Spacer()
                    StatBlock(label: "Clients", value: "\(snapshot.wsClients)")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Operator", systemImage: "phone.connection")
                .font(.headline)
            Text("Open the app to load latest stats.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct StatBlock: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .privacySensitive()
        }
    }
}
