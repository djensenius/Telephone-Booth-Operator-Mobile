//
//  TBOperatorMobileWidgetsBundle.swift
//  TBOperatorMobileWidgets
//
//  Real widgets + Live Activity arrive in PR 6. Placeholder keeps the
//  extension target buildable.
//

import SwiftUI
import WidgetKit

@main
struct TBOperatorMobileWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PlaceholderStatusWidget()
    }
}

struct PlaceholderStatusWidget: Widget {
    let kind = "BoothStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlaceholderProvider()) { entry in
            PlaceholderStatusWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Booth status")
        .description("Live operator booth status.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry {
        PlaceholderEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: .now)], policy: .never))
    }
}

struct PlaceholderStatusWidgetView: View {
    let entry: PlaceholderEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Operator", systemImage: "phone.connection")
                .font(.headline)
            Text("Holding for booth…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
