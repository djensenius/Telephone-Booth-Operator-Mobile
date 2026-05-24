//
//  SystemView.swift
//  TelephoneBoothOperatorMobile
//
//  Latest cached system snapshot for the booth. Pulled from
//  `/v1/system/current` (no booth filter, so the operator returns the
//  primary booth in the single-booth install).
//

import SwiftUI

public struct SystemView: View {
    @State private var snapshot: BoothSystemSnapshot?
    @State private var loading = false
    @State private var errorMessage: String?

    private let client: OperatorClient

    public init(client: OperatorClient = .shared) {
        self.client = client
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                if let errorMessage {
                    BannerView(message: errorMessage, kind: .error)
                }
                if let snapshot {
                    snapshotCard(snapshot)
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(Theme.Spacing.extraLarge)
                } else {
                    Text("No system snapshot has been received yet.")
                        .font(Theme.Fonts.bodySmall)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(Theme.Spacing.extraLarge)
                }
            }
            .padding(Theme.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Colors.background)
        .task { await refresh() }
        .refreshableIfAvailable { await refresh() }
    }

    private func snapshotCard(_ snapshot: BoothSystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(text: "Booth \(snapshot.boothId)")
            StatRow(
                label: "Captured",
                value: snapshot.capturedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute().second())
            )
            if let uptime = snapshot.uptimeSeconds {
                StatRow(label: "Uptime", value: formatUptime(uptime))
            }
            if snapshot.loadAverage1m != nil {
                StatRow(label: "Load (1m / 5m / 15m)", value: formatLoad(snapshot))
            }
            if let usage = snapshot.cpuUsageRatio {
                StatRow(label: "CPU usage", value: percent(usage))
            }
            if let temp = snapshot.cpuTemperatureCelsius {
                StatRow(label: "CPU temperature", value: String(format: "%.1f °C", temp))
            }
            if let ratio = snapshot.memoryUsedRatio {
                StatRow(label: "Memory used", value: percent(ratio))
            }
            if let tailscale = snapshot.tailscaleConnected {
                StatRow(label: "Tailscale", value: tailscale ? "Connected" : "Offline")
            }
            if let flags = snapshot.throttlingFlags, !flags.isEmpty {
                StatRow(label: "Throttling", value: flags.joined(separator: ", "))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
    }

    public func refresh() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            snapshot = try await client.fetchCurrentSystem()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't load system status."
        }
    }

    private func formatUptime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatLoad(_ snapshot: BoothSystemSnapshot) -> String {
        func fmt(_ value: Double?) -> String {
            guard let value else { return "—" }
            return String(format: "%.2f", value)
        }
        return "\(fmt(snapshot.loadAverage1m)) / \(fmt(snapshot.loadAverage5m)) / \(fmt(snapshot.loadAverage15m))"
    }

    private func percent(_ ratio: Double) -> String {
        let bounded = max(0, min(1, ratio))
        return String(format: "%.0f%%", bounded * 100)
    }
}
