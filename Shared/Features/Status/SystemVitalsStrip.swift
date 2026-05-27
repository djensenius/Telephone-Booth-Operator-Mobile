//
//  SystemVitalsStrip.swift
//  TelephoneBoothOperatorMobile
//
//  Compact always-visible booth vitals tile row, mirroring the operator
//  web `SystemVitalsStrip`. Renders CPU temperature, CPU usage, 1-min
//  load average, memory utilisation, uptime, throttling, and tailscale
//  reachability with the same Grafana-matching severity thresholds the
//  operator alerts on.
//
//  This view is platform-portable and never fetches anything itself —
//  callers (StatusDashboardView, SystemView) pass in the latest cached
//  snapshot.
//

import SwiftUI

public struct SystemVitalsStrip: View {
    public let snapshot: BoothSystemSnapshot?
    public let receivedAt: Date?

    public init(snapshot: BoothSystemSnapshot?, receivedAt: Date? = nil) {
        self.snapshot = snapshot
        self.receivedAt = receivedAt
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader(text: "Live vitals")
            tilesGrid
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Live booth vitals"))
    }

    @ViewBuilder
    private var tilesGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 110), spacing: Theme.Spacing.small)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.small) {
            VitalTile(
                label: "CPU temp",
                value: temperatureValue,
                severity: SystemVitals.temperatureSeverity(snapshot?.cpuTemperatureCelsius)
            )
            VitalTile(label: "CPU", value: cpuValue, severity: .nominal)
            VitalTile(
                label: "Load 1m",
                value: SystemVitals.formatNumber(snapshot?.loadAverage1m),
                severity: SystemVitals.loadSeverity(
                    snapshot?.loadAverage1m,
                    cores: snapshot?.cpuCoreCount
                )
            )
            VitalTile(
                label: "Memory",
                value: SystemVitals.formatPercent(snapshot?.memoryUsedRatio),
                severity: SystemVitals.memorySeverity(snapshot?.memoryUsedRatio)
            )
            VitalTile(
                label: "Uptime",
                value: SystemVitals.formatUptime(snapshot?.uptimeSeconds),
                severity: .nominal
            )
            if let flags = snapshot?.throttlingFlags, !flags.isEmpty {
                VitalTile(label: "Throttling", value: "\(flags.count)", severity: .warn)
            }
            if snapshot?.tailscaleConnected == false {
                VitalTile(label: "Tailscale", value: "down", severity: .crit)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        Text(footerText)
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    private var footerText: String {
        if let receivedAt {
            return "Updated " + receivedAt.formatted(date: .omitted, time: .standard)
        }
        return snapshot == nil ? "Awaiting first snapshot" : "Updated just now"
    }

    private var temperatureValue: String {
        guard let temp = snapshot?.cpuTemperatureCelsius else { return "—" }
        return String(format: "%.1f°C", temp)
    }

    private var cpuValue: String {
        guard let ratio = snapshot?.cpuUsageRatio else { return "—" }
        let bounded = max(0, min(1, ratio))
        return String(format: "%.0f%%", bounded * 100)
    }
}

// MARK: - Tile

private struct VitalTile: View {
    let label: String
    let value: String
    let severity: SystemVitals.Severity

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(Theme.Fonts.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Fonts.bodyLarge.weight(.semibold).monospacedDigit())
                .foregroundStyle(severity.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(Theme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(severity.tint.opacity(severity == .nominal ? 0.08 : 0.18))
        }
    }
}

// MARK: - Pure severity helpers (testable)

public enum SystemVitals {
    public enum Severity: Sendable, Equatable {
        case nominal, warn, crit

        public var tint: Color {
            switch self {
            case .nominal: return Theme.Colors.textPrimary
            case .warn: return Theme.Colors.warning
            case .crit: return Theme.Colors.error
            }
        }
    }

    public static let temperatureWarnC: Double = 60
    public static let temperatureCritC: Double = 75
    public static let memoryWarnRatio: Double = 0.85
    public static let memoryCritRatio: Double = 0.95

    public static func temperatureSeverity(_ value: Double?) -> Severity {
        guard let value else { return .nominal }
        if value >= temperatureCritC { return .crit }
        if value >= temperatureWarnC { return .warn }
        return .nominal
    }

    public static func memorySeverity(_ ratio: Double?) -> Severity {
        guard let ratio else { return .nominal }
        if ratio >= memoryCritRatio { return .crit }
        if ratio >= memoryWarnRatio { return .warn }
        return .nominal
    }

    public static func loadSeverity(_ value: Double?, cores: Int?) -> Severity {
        guard let value else { return .nominal }
        let reference = Double(cores ?? 1)
        if value >= reference * 2 { return .crit }
        if value >= reference { return .warn }
        return .nominal
    }

    public static func formatNumber(_ value: Double?, fractionDigits: Int = 2) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(fractionDigits)f", value)
    }

    public static func formatPercent(_ ratio: Double?) -> String {
        guard let ratio else { return "—" }
        let bounded = max(0, min(1, ratio))
        return String(format: "%.0f%%", bounded * 100)
    }

    public static func formatUptime(_ seconds: Double?) -> String {
        guard let seconds else { return "—" }
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    public static func formatBytes(_ value: Double?) -> String {
        guard let value else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB, .useBytes]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(value))
    }
}
