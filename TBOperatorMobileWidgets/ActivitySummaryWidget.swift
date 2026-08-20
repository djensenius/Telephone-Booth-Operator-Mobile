//
//  ActivitySummaryWidget.swift
//  TBOperatorMobileWidgets
//
//  Rolling 24-hour pickup and message activity: headline totals plus an
//  hourly trend. Uses Swift Charts where available and falls back to a
//  lightweight SwiftUI bar strip otherwise. Zero and partial series are
//  rendered without crashing or dividing by zero.
//

import SwiftUI
import WidgetKit
#if canImport(Charts)
import Charts
#endif

struct ActivitySummaryWidget: Widget {
    let kind = "ActivitySummaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetSnapshotProvider()) { entry in
            ActivitySummaryWidgetView(entry: entry)
                .widgetURL(WidgetDeepLink.stats)
        }
        .configurationDisplayName("24-hour activity")
        .description("Pickups and messages over the last 24 hours.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ActivitySummaryWidgetView: View {
    let entry: WidgetSnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetContainerBackground(family)
    }

    @ViewBuilder
    private var content: some View {
        switch entry.activityState {
        case .noSnapshot:
            WidgetUnavailableView(
                title: "Activity",
                systemImage: "chart.bar.xaxis",
                message: "Open the app to load activity."
            )
        case .missingSection:
            WidgetUnavailableView(
                title: "Activity",
                systemImage: "chart.bar.xaxis",
                message: "Activity not available yet."
            )
        case let .current(activity, _):
            layout(activity, stale: false)
        case let .stale(activity, _):
            layout(activity, stale: true)
        }
    }

    private func layout(_ activity: WidgetSnapshot.Activity, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                    .widgetAccentable()
                Text("Last 24 hours")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if stale { WidgetStaleBadge() }
            }
            HStack(spacing: 16) {
                StatBlock(label: "Pickups", value: "\(activity.pickups)")
                StatBlock(label: "Messages", value: "\(activity.messages)")
                Spacer()
                legend
            }
            trend(activity)
            if family == .systemLarge {
                WidgetUpdatedFooter(date: activity.refreshedAt, stale: stale)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Last 24 hours: \(activity.pickups) pickups, \(activity.messages) messages"
        )
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(color: Theme.Colors.accent, label: "Pickups")
            legendItem(color: Theme.Colors.info, label: "Messages")
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func trend(_ activity: WidgetSnapshot.Activity) -> some View {
        let buckets = activity.buckets
        let hasSignal = buckets.contains { $0.pickups > 0 || $0.messages > 0 }
        if buckets.isEmpty || !hasSignal {
            emptyTrend
        } else {
            ActivityTrendChart(buckets: buckets)
                .frame(maxWidth: .infinity)
                .frame(height: family == .systemLarge ? 150 : 60)
        }
    }

    private var emptyTrend: some View {
        Text("No activity in the last 24 hours.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: family == .systemLarge ? 150 : 60, alignment: .center)
    }
}

/// Hourly pickup/message trend. Prefers Swift Charts and degrades to a
/// dependency-free SwiftUI bar strip if Charts is unavailable.
struct ActivityTrendChart: View {
    let buckets: [WidgetSnapshot.ActivityBucket]

    var body: some View {
        #if canImport(Charts)
        Chart {
            ForEach(buckets) { bucket in
                BarMark(
                    x: .value("Hour", bucket.hour),
                    y: .value("Pickups", bucket.pickups)
                )
                .foregroundStyle(Theme.Colors.accent.opacity(0.85))
            }
            ForEach(buckets) { bucket in
                LineMark(
                    x: .value("Hour", bucket.hour),
                    y: .value("Messages", bucket.messages)
                )
                .foregroundStyle(Theme.Colors.info)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartLegend(.hidden)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityHidden(true)
        #else
        fallbackStrip
        #endif
    }

    /// Dependency-free bar strip used when Swift Charts is unavailable.
    /// Defined unconditionally so it is always type-checked, even on the
    /// platforms where the Charts path is the one that ships.
    private var fallbackStrip: some View {
        let maxValue = CGFloat(max(buckets.map { max($0.pickups, $0.messages) }.max() ?? 1, 1))
        return GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(buckets) { bucket in
                    let fraction = CGFloat(bucket.pickups) / maxValue
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.Colors.accent.opacity(0.85))
                        .frame(height: max(1, proxy.size.height * fraction))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}

#Preview("Activity · medium", as: .systemMedium) {
    ActivitySummaryWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
    WidgetSnapshotEntry.emptySections()
}

#Preview("Activity · large", as: .systemLarge) {
    ActivitySummaryWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
    WidgetSnapshotEntry.sample(minutesAgo: 45, treatAsFresh: false)
}
