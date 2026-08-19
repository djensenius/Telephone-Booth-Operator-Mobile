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
//  snapshot plus the matching router component temperature.
//

import SwiftUI

public enum SystemVitalsPresentation: Sendable, Equatable {
    case full
    case summary
}

public struct SystemVitalsStrip: View {
    public let snapshot: BoothSystemSnapshot?
    public let receivedAt: Date?
    public let componentSources: [SystemComponentCurrentEnvelope]
    public let boothId: String?
    public let presentation: SystemVitalsPresentation

    public init(
        snapshot: BoothSystemSnapshot?,
        receivedAt: Date? = nil,
        componentSources: [SystemComponentCurrentEnvelope] = [],
        boothId: String? = nil,
        presentation: SystemVitalsPresentation = .full
    ) {
        self.snapshot = snapshot
        self.receivedAt = receivedAt
        self.componentSources = componentSources
        self.boothId = boothId
        self.presentation = presentation
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                HStack {
                    SectionHeader(text: presentation == .summary ? "System health" : "Live vitals")
                    if presentation == .summary {
                        Spacer(minLength: Theme.Spacing.small)
                        healthBadge(now: context.date)
                    }
                }
                if presentation == .summary {
                    summaryTiles(now: context.date)
                } else {
                    tilesGrid(now: context.date)
                }
                footer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(presentation == .summary ? "System health" : "Live booth vitals"))
    }

    private func summaryTiles(now: Date) -> some View {
        let routerTemperature = SystemVitals.routerBatteryTemperature(
            in: componentSources,
            boothId: boothId,
            now: now
        )
        return HStack(spacing: Theme.Spacing.small) {
            VitalTile(
                label: "CPU temp",
                value: temperatureValue,
                severity: SystemVitals.temperatureSeverity(snapshot?.cpuTemperatureCelsius)
            )
            VitalTile(
                label: "Router batt",
                value: SystemVitals.formatTemperature(routerTemperature),
                severity: SystemVitals.temperatureSeverity(routerTemperature)
            )
            VitalTile(
                label: "Memory",
                value: SystemVitals.formatPercent(snapshot?.memoryUsedRatio),
                severity: SystemVitals.memorySeverity(snapshot?.memoryUsedRatio)
            )
        }
    }

    private func healthBadge(now: Date) -> some View {
        let severity = healthSeverity(now: now)
        let label: String
        let symbol: String
        switch severity {
        case .none:
            (label, symbol) = ("Waiting", "wave.3.right.circle")
        case .nominal:
            (label, symbol) = ("Nominal", "checkmark.circle.fill")
        case .warn:
            (label, symbol) = ("Check", "exclamationmark.triangle.fill")
        case .crit:
            (label, symbol) = ("Attention", "xmark.octagon.fill")
        }
        return Label(label, systemImage: symbol)
            .font(Theme.Fonts.caption.weight(.semibold))
            .foregroundStyle(severity?.tint ?? Theme.Colors.info)
    }

    private func healthSeverity(now: Date) -> SystemVitals.Severity? {
        guard let snapshot else { return nil }
        let routerTemperature = SystemVitals.routerBatteryTemperature(
            in: componentSources,
            boothId: boothId,
            now: now
        )
        let telemetryIsStale = receivedAt.map {
            now.timeIntervalSince($0) >= BoothStalenessThresholds.offlineSeconds
        } ?? false
        return SystemVitals.overallSeverity(
            snapshot: snapshot,
            routerTemperature: routerTemperature,
            telemetryIsStale: telemetryIsStale
        )
    }

    @ViewBuilder
    private func tilesGrid(now: Date) -> some View {
        let routerBatteryTemperatureCelsius = SystemVitals.routerBatteryTemperature(
            in: componentSources,
            boothId: boothId,
            now: now
        )
        let columns = [GridItem(.adaptive(minimum: 110), spacing: Theme.Spacing.small)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.small) {
            VitalTile(
                label: "CPU temp",
                value: temperatureValue,
                severity: SystemVitals.temperatureSeverity(snapshot?.cpuTemperatureCelsius)
            )
            VitalTile(
                label: "Router batt",
                value: SystemVitals.formatTemperature(routerBatteryTemperatureCelsius),
                severity: SystemVitals.temperatureSeverity(routerBatteryTemperatureCelsius)
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
            if let fan = snapshot?.fan {
                FanVitalTile(fan: fan)
            }
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
        SystemVitals.formatTemperature(snapshot?.cpuTemperatureCelsius)
    }

    private var cpuValue: String {
        guard let ratio = snapshot?.cpuUsageRatio else { return "—" }
        let bounded = max(0, min(1, ratio))
        return String(format: "%.0f%%", bounded * 100)
    }
}

private struct FanVitalTile: View {
    let fan: BoothSystemSnapshot.FanStats

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("FAN")
                .font(Theme.Fonts.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            HStack(spacing: 6) {
                MiniFanDial(ratio: commandRatio)
                    .frame(width: 44, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryValue)
                        .font(Theme.Fonts.bodyLarge.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(metaText)
                        .font(Theme.Fonts.caption.monospacedDigit())
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(Theme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.Colors.textPrimary.opacity(0.08))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cooling fan"))
        .accessibilityValue(Text(accessibilityValue))
    }

    private var commandRatio: Double? {
        fan.pwmRatio.map { max(0, min(1, $0)) }
    }

    private var pwmPercent: Int? {
        fan.pwmRatio.map { Int((max(0, min(1, $0)) * 100).rounded()) }
    }

    private var primaryValue: String {
        if let rpm = fan.rpm {
            return rpm.formatted()
        }
        if let pwmPercent {
            return "\(pwmPercent)%"
        }
        if let commandedOn = fan.commandedOn {
            return commandedOn ? "On" : "Off"
        }
        return "—"
    }

    private var metaText: String {
        if fan.rpm != nil {
            if let pwmPercent {
                return "RPM · \(pwmPercent)% PWM"
            }
            if let commandedOn = fan.commandedOn {
                return "RPM · \(commandedOn ? "On" : "Off")"
            }
            return "RPM"
        }
        return pwmPercent != nil ? "PWM · no tach" : "No tach feedback"
    }

    private var accessibilityValue: String {
        [
            fan.rpm.map { "\($0) RPM measured" },
            pwmPercent.map { "\($0) percent PWM commanded" },
            fan.pwmRatio == nil
                ? fan.commandedOn.map { "fan commanded \($0 ? "on" : "off")" }
                : nil,
            fan.rpm == nil ? "no tachometer feedback" : nil
        ]
        .compactMap(\.self)
        .joined(separator: ", ")
    }
}

private struct MiniFanDial: View {
    let ratio: Double?

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height - 2)
            let radius = min(proxy.size.width / 2 - 3, proxy.size.height - 5)
            ZStack {
                arc(center: center, radius: radius, endDegrees: 360)
                    .stroke(
                        Theme.Colors.textSecondary.opacity(0.2),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                if let ratio {
                    arc(center: center, radius: radius, endDegrees: 180 + ratio * 180)
                        .stroke(
                            Theme.Colors.primary,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                    Capsule()
                        .fill(Theme.Colors.warning)
                        .frame(width: 2, height: radius - 2)
                        .offset(y: -(radius - 2) / 2)
                        .rotationEffect(.degrees(-90 + ratio * 180))
                        .position(center)
                }
                Circle()
                    .fill(Theme.Colors.warning)
                    .frame(width: 6, height: 6)
                    .position(center)
            }
        }
    }

    private func arc(center: CGPoint, radius: CGFloat, endDegrees: Double) -> Path {
        Path { path in
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(endDegrees),
                clockwise: false
            )
        }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value))
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

    public static func overallSeverity(
        snapshot: BoothSystemSnapshot,
        routerTemperature: Double? = nil,
        telemetryIsStale: Bool = false
    ) -> Severity? {
        let hasNumericSignal = [snapshot.cpuTemperatureCelsius, routerTemperature,
            snapshot.memoryUsedRatio, snapshot.loadAverage1m].contains { $0?.isFinite == true }
        guard hasNumericSignal || snapshot.tailscaleConnected != nil ||
            snapshot.throttlingFlags != nil else { return nil }
        var severities = [
            temperatureSeverity(snapshot.cpuTemperatureCelsius),
            temperatureSeverity(routerTemperature),
            memorySeverity(snapshot.memoryUsedRatio),
            loadSeverity(snapshot.loadAverage1m, cores: snapshot.cpuCoreCount)
        ]
        if snapshot.tailscaleConnected == false { severities.append(.crit) }
        if let flags = snapshot.throttlingFlags, !flags.isEmpty { severities.append(.warn) }
        if telemetryIsStale { severities.append(.warn) }
        if severities.contains(.crit) { return .crit }
        if severities.contains(.warn) { return .warn }
        return .nominal
    }

    public static func formatNumber(_ value: Double?, fractionDigits: Int = 2) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(fractionDigits)f", value)
    }

    public static func formatTemperature(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f°C", value)
    }

    public static func routerBatteryTemperature(
        in sources: [SystemComponentCurrentEnvelope],
        boothId: String?,
        now: Date = Date()
    ) -> Double? {
        guard let boothId = boothId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !boothId.isEmpty else {
            return nil
        }
        return sources
            .filter { $0.source.boothId == boothId && $0.source.isRouter }
            .sorted(by: componentSourceOrder)
            .compactMap { envelope in
                guard let freshnessDate = envelope.freshnessDate,
                      now.timeIntervalSince(freshnessDate) <= 5 * 60 else {
                    return nil
                }
                return envelope.latestSnapshot?.battery?.temperatureCelsius
            }
            .first(where: \.isFinite)
    }

    private static func componentSourceOrder(
        _ lhs: SystemComponentCurrentEnvelope,
        _ rhs: SystemComponentCurrentEnvelope
    ) -> Bool {
        if lhs.source.isRouter != rhs.source.isRouter {
            return lhs.source.isRouter
        }
        let nameOrder = lhs.source.effectiveDisplayName.localizedCaseInsensitiveCompare(
            rhs.source.effectiveDisplayName
        )
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.id < rhs.id
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
