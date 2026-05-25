//
//  CallsTodayWidget.swift
//  TBOperatorMobileWidgets
//
//  Shows the booth's call volume for the day. Highlights an in-progress
//  call when applicable.
//

import SwiftUI
import WidgetKit

struct CallsTodayWidget: Widget {
    let kind = "CallsTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetSnapshotProvider()) { entry in
            CallsTodayWidgetView(entry: entry)
                .widgetURL(URL(string: "tboperator://sessions"))
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Calls today")
        .description("Calls answered today, plus any currently in progress.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CallsTodayWidgetView: View {
    let entry: WidgetSnapshotEntry

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
                Image(systemName: "phone.connection.fill")
                    .foregroundStyle(.tint)
                    .font(.title3.weight(.semibold))
                Text("Calls")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if snapshot.callsInProgress > 0 {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse)
                        .privacySensitive()
                }
            }
            Text("\(snapshot.callsToday)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .privacySensitive()
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if snapshot.callsInProgress > 0 {
                    Text("\(snapshot.callsInProgress) in progress")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .privacySensitive()
                } else {
                    Text("None active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(snapshot.generatedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Calls", systemImage: "phone.connection")
                .font(.headline)
            Text("Open the app to load latest counts.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
