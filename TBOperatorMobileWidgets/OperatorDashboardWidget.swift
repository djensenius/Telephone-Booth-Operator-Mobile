//
//  OperatorDashboardWidget.swift
//  TBOperatorMobileWidgets
//
//  A combined "everything at a glance" widget for the medium, large,
//  and extra-large families: booth state, queue/pickup counts, system health,
//  latest-message status/time, and overall freshness. Each section
//  degrades independently when its snapshot slice is missing.
//
//  Note: WidgetKit exposes a single `.systemExtraLarge` family (there is
//  no distinct portrait family), offered on iPadOS/macOS only — hence the
//  compile-time platform guard around it.
//

import SwiftUI
import WidgetKit

struct OperatorDashboardWidget: Widget {
    let kind = "OperatorDashboardWidget"

    private var families: [WidgetFamily] {
        #if os(iOS) || os(macOS)
        [.systemMedium, .systemLarge, .systemExtraLarge]
        #else
        [.systemMedium, .systemLarge]
        #endif
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetSnapshotProvider()) { entry in
            OperatorDashboardWidgetView(entry: entry)
                .widgetURL(WidgetDeepLink.dashboard)
        }
        .configurationDisplayName("Operator dashboard")
        .description("Booth, queue, health, and latest message in one place.")
        .supportedFamilies(families)
    }
}

struct OperatorDashboardWidgetView: View {
    let entry: WidgetSnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var isWide: Bool {
        #if os(iOS) || os(macOS)
        return family == .systemExtraLarge
        #else
        return false
        #endif
    }

    var body: some View {
        content
            .widgetContainerBackground(family)
    }

    @ViewBuilder
    private var content: some View {
        if entry.snapshot == nil {
            WidgetUnavailableView(
                title: "Operator",
                systemImage: "square.grid.2x2",
                message: "Open the app to load the dashboard."
            )
        } else if family.operatorLayoutSize == .medium {
            compactLayout
        } else if isWide {
            wideLayout
        } else {
            stackedLayout
        }
    }

    private var compactLayout: some View {
        HStack(alignment: .top, spacing: 14) {
            compactBooth
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let summary = entry.summaryState.value {
                    WidgetMetricGrid(
                        metrics: countMetrics(summary),
                        columns: 2,
                        compact: true,
                        staleAsOf: entry.summaryState.staleAsOf
                    )
                } else {
                    sectionUnavailable("Counts unavailable")
                }
                HStack(alignment: .top, spacing: 10) {
                    compactHealth
                    compactMessage
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            boothHeader
            Divider()
            countsRow
            Divider()
            healthRow
            Divider()
            latestMessageRow
            stackedActivity
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var wideLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            boothHeader
            Divider()
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    countsRow
                    latestMessageRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    healthRow
                    if let activity = entry.activityState.value {
                        Divider()
                        WidgetActivityTrendSection(
                            activity: activity,
                            height: 78,
                            staleAsOf: entry.activityState.staleAsOf
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Sections

    @ViewBuilder
    private var compactBooth: some View {
        if let summary = entry.summaryState.value {
            VStack(alignment: .leading, spacing: 6) {
                Label("Booth", systemImage: summary.boothState.widgetSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(summary.boothState.widgetTint)
                    .widgetAccentable()
                Text(summary.boothState.widgetDisplayName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .privacySensitive()
                if let mode = summary.runtimeMode, mode.shouldDisplayBadge {
                    RuntimeModeBadge(mode: mode)
                }
                Spacer(minLength: 0)
                WidgetUpdatedFooter(
                    date: entry.summaryState.asOf ?? summary.boothUpdatedAt,
                    stale: entry.summaryState.isStale
                )
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            sectionUnavailable("Booth unavailable")
        }
    }

    @ViewBuilder
    private var compactHealth: some View {
        if let health = entry.systemHealthState.value {
            let severity = health.effectiveSeverity(at: entry.date)
            WidgetStatusBlock(
                label: "System",
                value: severity.displayName,
                systemImage: severity.symbolName,
                tint: severity.tint,
                privacySensitive: false,
                staleAsOf: entry.systemHealthState.staleAsOf
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
    private var compactMessage: some View {
        if let message = entry.latestMessageState.value {
            WidgetStatusBlock(
                label: "Message",
                value: message.status.displayName,
                systemImage: "waveform",
                tint: message.status.widgetTint,
                staleAsOf: entry.latestMessageState.staleAsOf
            )
        } else {
            WidgetStatusBlock(
                label: "Message",
                value: "None yet",
                systemImage: "waveform"
            )
        }
    }

    @ViewBuilder
    private var boothHeader: some View {
        if let summary = entry.summaryState.value {
            HStack(spacing: 10) {
                Image(systemName: summary.boothState.widgetSymbol)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(summary.boothState.widgetTint)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text(summary.boothState.widgetDisplayName)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .privacySensitive()
                    Text(summary.boothUpdatedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let staleAsOf = entry.summaryState.staleAsOf {
                        WidgetStaleBadge(asOf: staleAsOf)
                    }
                }
                Spacer()
                if let mode = summary.runtimeMode, mode.shouldDisplayBadge {
                    RuntimeModeBadge(mode: mode)
                }
                severityChip
            }
        } else {
            Label("Booth status unavailable", systemImage: "phone.connection")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var severityChip: some View {
        if let health = entry.systemHealthState.value {
            let severity = health.effectiveSeverity(at: entry.date)
            Label(severity.displayName, systemImage: severity.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(severity.tint)
                .widgetAccentable()
                .accessibilityLabel("System \(severity.displayName)")
        }
    }

    @ViewBuilder
    private var countsRow: some View {
        if let summary = entry.summaryState.value {
            WidgetMetricGrid(
                metrics: countMetrics(summary),
                columns: 4,
                staleAsOf: entry.summaryState.staleAsOf
            )
        } else {
            sectionUnavailable("Counts unavailable")
        }
    }

    @ViewBuilder
    private var healthRow: some View {
        if let health = entry.systemHealthState.value {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("System")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    if let staleAsOf = entry.systemHealthState.staleAsOf {
                        WidgetStaleBadge(asOf: staleAsOf)
                    }
                }
                HStack {
                    dashboardMetric("CPU", Self.temp(health.cpuTemperatureCelsius))
                    Spacer()
                    dashboardMetric("Router", Self.temp(health.routerTemperatureCelsius))
                    Spacer()
                    dashboardMetric("Memory", Self.ratio(health.memoryUsedRatio))
                    Spacer()
                    dashboardMetric("Link", Self.connectivity(health.tailscaleConnected))
                }
            }
        } else {
            sectionUnavailable("Health unavailable")
        }
    }

    @ViewBuilder
    private var latestMessageRow: some View {
        if let message = entry.latestMessageState.value {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(.tint)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text("Latest message")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(message.status.displayName)
                        .font(.callout.weight(.semibold))
                        .privacySensitive()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(message.occurredAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .privacySensitive()
                    if let staleAsOf = entry.latestMessageState.staleAsOf {
                        WidgetStaleBadge(asOf: staleAsOf)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(latestMessageAccessibilityLabel(message))
        } else {
            sectionUnavailable("No recent message")
        }
    }

    @ViewBuilder
    private var stackedActivity: some View {
        if let activity = entry.activityState.value {
            Divider()
            WidgetActivityTrendSection(
                activity: activity,
                height: 36,
                staleAsOf: entry.activityState.staleAsOf
            )
        }
    }

    private var footer: some View {
        let stale = entry.summaryState.isStale
            || entry.systemHealthState.isStale
            || entry.latestMessageState.isStale
            || entry.activityState.isStale
        let stamp = entry.oldestSectionAsOf ?? entry.date
        return WidgetUpdatedFooter(date: stamp, stale: stale)
    }

    // MARK: - Small helpers

    private func countMetrics(_ summary: WidgetSnapshot.Summary) -> [WidgetMetricValue] {
        [
            WidgetMetricValue(label: "Pending", value: "\(summary.pendingMessages)"),
            WidgetMetricValue(label: "Pickups", value: "\(summary.interactionsToday)"),
            WidgetMetricValue(label: "Received", value: "\(summary.receivedToday)"),
            WidgetMetricValue(label: "Clients", value: "\(summary.wsClients)")
        ]
    }

    private func dashboardMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    private func latestMessageAccessibilityLabel(
        _ message: WidgetSnapshot.LatestMessage
    ) -> Text {
        let label = "Latest message \(message.status.displayName)"
        if let staleAsOf = entry.latestMessageState.staleAsOf {
            return Text("\(label). Data is stale. Updated \(staleAsOf, style: .relative)")
        }
        return Text(label)
    }

    private func sectionUnavailable(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func temp(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f°", value)
    }

    private static func ratio(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }

    private static func connectivity(_ connected: Bool?) -> String {
        switch connected {
        case .some(true): return "Online"
        case .some(false): return "Offline"
        case .none: return "—"
        }
    }
}

#Preview("Dashboard · large", as: .systemLarge) {
    OperatorDashboardWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
    WidgetSnapshotEntry.sample(minutesAgo: 45, treatAsFresh: false)
    WidgetSnapshotEntry.noSnapshot()
}

#Preview("Dashboard · medium", as: .systemMedium) {
    OperatorDashboardWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
}

#if os(iOS) || os(macOS)
#Preview("Dashboard · extra large", as: .systemExtraLarge) {
    OperatorDashboardWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
}
#endif
