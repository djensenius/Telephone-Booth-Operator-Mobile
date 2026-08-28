//
//  SystemHealthWidget.swift
//  TBOperatorMobileWidgets
//
//  At-a-glance booth system health: overall severity, CPU and router
//  temperatures, memory pressure, Tailscale connectivity, and how old the
//  underlying telemetry is. Severity escalates automatically once the
//  source data crosses the five-minute offline threshold.
//

import SwiftUI
import WidgetKit

struct SystemHealthWidget: Widget {
    let kind = "SystemHealthWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetSnapshotProvider()) { entry in
            SystemHealthWidgetView(entry: entry)
                .widgetURL(WidgetDeepLink.system)
        }
        .configurationDisplayName("System health")
        .description("Booth severity, temperatures, memory, and connectivity.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct SystemHealthWidgetView: View {
    let entry: WidgetSnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetContainerBackground(family)
    }

    @ViewBuilder
    private var content: some View {
        switch entry.systemHealthState {
        case .noSnapshot:
            WidgetUnavailableView(
                title: "System",
                systemImage: "cpu",
                message: "Open the app to load system health."
            )
        case .missingSection:
            WidgetUnavailableView(
                title: "System",
                systemImage: "cpu",
                message: "System health not available yet."
            )
        case let .current(health, _):
            layout(health, cacheStale: false)
        case let .stale(health, _):
            layout(health, cacheStale: true)
        }
    }

    @ViewBuilder
    private func layout(_ health: WidgetSnapshot.SystemHealth, cacheStale: Bool) -> some View {
        let severity = health.effectiveSeverity(at: entry.date)
        let sourceStale = entry.date.timeIntervalSince(health.sourceUpdatedAt)
            >= WidgetSnapshot.sourceStaleInterval

        switch family.operatorLayoutSize {
        case .large, .extraLarge:
            largeLayout(
                health,
                severity: severity,
                cacheStale: cacheStale,
                sourceStale: sourceStale
            )
        default:
            standardLayout(
                health,
                severity: severity,
                cacheStale: cacheStale,
                sourceStale: sourceStale
            )
        }
    }

    private func standardLayout(
        _ health: WidgetSnapshot.SystemHealth,
        severity: WidgetSnapshot.HealthSeverity,
        cacheStale: Bool,
        sourceStale: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: family.operatorLayoutSize == .small ? 6 : 10) {
            header(severity: severity, cacheStale: cacheStale)
            if family.operatorLayoutSize == .small {
                compactMetrics(health)
            } else {
                metricGrid(health)
            }
            Spacer(minLength: 0)
            footer(health, sourceStale: sourceStale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func largeLayout(
        _ health: WidgetSnapshot.SystemHealth,
        severity: WidgetSnapshot.HealthSeverity,
        cacheStale: Bool,
        sourceStale: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(severity: severity, cacheStale: cacheStale)
            metricGrid(health)
            Divider()
            relatedSummary
            if let activity = entry.activityState.value {
                WidgetActivityTrendSection(
                    activity: activity,
                    height: 52,
                    staleAsOf: entry.activityState.staleAsOf
                )
            }
            Spacer(minLength: 0)
            footer(health, sourceStale: sourceStale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var relatedSummary: some View {
        if let summary = entry.summaryState.value {
            HStack(alignment: .top, spacing: 14) {
                WidgetStatusBlock(
                    label: "Booth",
                    value: summary.boothState.widgetDisplayName,
                    systemImage: summary.boothState.widgetSymbol,
                    tint: summary.boothState.widgetTint,
                    detail: Text(summary.boothUpdatedAt, style: .relative),
                    staleAsOf: entry.summaryState.staleAsOf
                )
                WidgetMetricGrid(
                    metrics: [
                        WidgetMetricValue(
                            label: "Pickups",
                            value: "\(summary.interactionsToday)"
                        ),
                        WidgetMetricValue(
                            label: "Pending",
                            value: "\(summary.pendingMessages)"
                        )
                    ],
                    columns: 2,
                    compact: true,
                    staleAsOf: entry.summaryState.staleAsOf
                )
                .frame(maxWidth: .infinity)
                latestMessageBlock
            }
        } else {
            Text("Booth summary is not available yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var latestMessageBlock: some View {
        if let message = entry.latestMessageState.value {
            WidgetStatusBlock(
                label: "Latest message",
                value: message.status.displayName,
                systemImage: "waveform",
                tint: message.status.widgetTint,
                detail: Text(message.occurredAt, style: .relative),
                staleAsOf: entry.latestMessageState.staleAsOf
            )
        } else {
            WidgetStatusBlock(
                label: "Latest message",
                value: "None yet",
                systemImage: "waveform"
            )
        }
    }

    private func header(severity: WidgetSnapshot.HealthSeverity, cacheStale: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: severity.symbolName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(severity.tint)
                .widgetAccentable()
            WidgetHeaderTitle(title: family == .systemSmall ? "System" : "System health")
            Spacer(minLength: 4)
            if cacheStale {
                WidgetStaleBadge()
            } else {
                Text(severity.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(severity.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            cacheStale
                ? "System health \(severity.displayName), data is stale"
                : "System health \(severity.displayName)"
        )
    }

    private func compactMetrics(_ health: WidgetSnapshot.SystemHealth) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MetricRow(symbol: "thermometer.medium", label: "CPU", value: Self.temp(health.cpuTemperatureCelsius))
            MetricRow(symbol: "memorychip", label: "Memory", value: Self.ratio(health.memoryUsedRatio))
            MetricRow(
                symbol: connectivitySymbol(health.tailscaleConnected),
                label: "Link",
                value: Self.connectivity(health.tailscaleConnected)
            )
        }
    }

    private func metricGrid(_ health: WidgetSnapshot.SystemHealth) -> some View {
        let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            MetricTile(symbol: "thermometer.medium", label: "CPU temp", value: Self.temp(health.cpuTemperatureCelsius))
            MetricTile(
                symbol: "thermometer.medium",
                label: "Router temp",
                value: Self.temp(health.routerTemperatureCelsius)
            )
            MetricTile(symbol: "memorychip", label: "Memory", value: Self.ratio(health.memoryUsedRatio))
            MetricTile(
                symbol: connectivitySymbol(health.tailscaleConnected),
                label: "Tailscale",
                value: Self.connectivity(health.tailscaleConnected)
            )
        }
    }

    private func footer(_ health: WidgetSnapshot.SystemHealth, sourceStale: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: sourceStale ? "exclamationmark.triangle.fill" : "clock")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text("Source \(health.sourceUpdatedAt, style: .relative)")
            if sourceStale {
                Spacer(minLength: 4)
                Text("Delayed")
                    .fontWeight(.semibold)
            }
        }
        .font(.caption2)
        .foregroundStyle(sourceStale ? AnyShapeStyle(Theme.Colors.warning) : AnyShapeStyle(.tertiary))
        .accessibilityElement(children: .combine)
    }

    private func connectivitySymbol(_ connected: Bool?) -> String {
        switch connected {
        case .some(true): return "network"
        case .some(false): return "network.slash"
        case .none: return "network"
        }
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

private struct MetricRow: View {
    let symbol: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

private struct MetricTile: View {
    let symbol: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .imageScale(.small)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

#Preview("System health · small", as: .systemSmall) {
    SystemHealthWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
    WidgetSnapshotEntry.sample(minutesAgo: 45, treatAsFresh: false)
    WidgetSnapshotEntry.noSnapshot()
}

#Preview("System health · medium", as: .systemMedium) {
    SystemHealthWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
}

#Preview("System health · large", as: .systemLarge) {
    SystemHealthWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
}
