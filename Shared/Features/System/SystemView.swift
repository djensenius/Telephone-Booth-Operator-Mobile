//
//  SystemView.swift
//  TelephoneBoothOperatorMobile
//
//  Live cached system snapshot for the booth — host info, CPU, memory,
//  swap, disks, network, audio, tailscale, runtime mode. Pulled from
//  `/v1/system/current` (no booth filter, so the operator returns the
//  primary booth in the single-booth install).
//

import SwiftUI

public struct SystemView: View {
    @State private var envelope: BoothSystemSnapshotEnvelope?
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
                if let envelope {
                    SystemVitalsStrip(snapshot: envelope.snapshot, receivedAt: envelope.receivedAt)
                    SystemHostCard(snapshot: envelope.snapshot, receivedAt: envelope.receivedAt)
                    SystemCPUCard(snapshot: envelope.snapshot)
                    SystemMemoryCard(snapshot: envelope.snapshot)
                    SystemDisksCard(snapshot: envelope.snapshot)
                    SystemNetworkCard(snapshot: envelope.snapshot)
                    SystemAudioCard(snapshot: envelope.snapshot)
                    SystemConnectivityCard(snapshot: envelope.snapshot)
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

    public func refresh() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            envelope = try await client.fetchCurrentSystemEnvelope()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't load system status."
        }
    }
}

// MARK: - Host card

private struct SystemHostCard: View {
    let snapshot: BoothSystemSnapshot
    let receivedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                SectionHeader(text: "Booth \(snapshot.boothId)")
                Spacer(minLength: 0)
                RuntimeModeBadge(mode: snapshot.runtimeMode)
            }
            if let hostname = snapshot.hostname {
                StatRow(label: "Hostname", value: hostname)
            }
            if let osVersion = snapshot.osVersion {
                StatRow(label: "OS", value: osVersion)
            }
            if let kernel = snapshot.kernelVersion {
                StatRow(label: "Kernel", value: kernel)
            }
            if let uptime = snapshot.uptimeSeconds {
                StatRow(label: "Uptime", value: SystemVitals.formatUptime(uptime))
            }
            StatRow(
                label: "Captured",
                value: snapshot.capturedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute().second())
            )
            StatRow(
                label: "Received",
                value: receivedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute().second())
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
    }
}

// MARK: - CPU card

private struct SystemCPUCard: View {
    let snapshot: BoothSystemSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader(text: "CPU")
            if let temp = snapshot.cpuTemperatureCelsius {
                StatRow(label: "Temperature", value: String(format: "%.1f °C", temp))
            }
            if let usage = snapshot.cpuUsageRatio {
                StatRow(label: "Usage", value: SystemVitals.formatPercent(usage))
            }
            if snapshot.loadAverage1m != nil {
                StatRow(label: "Load (1m / 5m / 15m)", value: formatLoad(snapshot))
            }
            if let cores = snapshot.cpuUsageRatioPerCore, !cores.isEmpty {
                StatRow(label: "Cores", value: "\(cores.count)")
                CPUCoreBars(usages: cores)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
    }

    private func formatLoad(_ snapshot: BoothSystemSnapshot) -> String {
        let load1 = SystemVitals.formatNumber(snapshot.loadAverage1m)
        let load5 = SystemVitals.formatNumber(snapshot.loadAverage5m)
        let load15 = SystemVitals.formatNumber(snapshot.loadAverage15m)
        return "\(load1) / \(load5) / \(load15)"
    }
}

private struct CPUCoreBars: View {
    let usages: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(usages.enumerated()), id: \.offset) { index, usage in
                HStack(spacing: 8) {
                    Text("Core \(index)")
                        .font(Theme.Fonts.caption.monospacedDigit())
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 60, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.Colors.textSecondary.opacity(0.15))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(barColor(for: usage))
                                .frame(width: max(2, geo.size.width * CGFloat(max(0, min(1, usage)))))
                        }
                    }
                    .frame(height: 8)
                    Text(SystemVitals.formatPercent(usage))
                        .font(Theme.Fonts.caption.monospacedDigit())
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }

    private func barColor(for usage: Double) -> Color {
        if usage >= 0.9 { return Theme.Colors.error }
        if usage >= 0.7 { return Theme.Colors.warning }
        return Theme.Colors.success
    }
}

// MARK: - Memory card

private struct SystemMemoryCard: View {
    let snapshot: BoothSystemSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            SectionHeader(text: "Memory")
            if let ratio = snapshot.memoryUsedRatio {
                StatRow(label: "RAM used", value: SystemVitals.formatPercent(ratio))
            }
            if let used = snapshot.memoryUsedBytes, let total = snapshot.memoryTotalBytes {
                StatRow(
                    label: "RAM",
                    value: "\(SystemVitals.formatBytes(used)) / \(SystemVitals.formatBytes(total))"
                )
            }
            if let swapRatio = snapshot.swapUsedRatio {
                StatRow(label: "Swap used", value: SystemVitals.formatPercent(swapRatio))
            }
            if let used = snapshot.swapUsedBytes, let total = snapshot.swapTotalBytes, total > 0 {
                StatRow(
                    label: "Swap",
                    value: "\(SystemVitals.formatBytes(used)) / \(SystemVitals.formatBytes(total))"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.large)
        .glassCardBackground()
    }
}

// MARK: - Disks

private struct SystemDisksCard: View {
    let snapshot: BoothSystemSnapshot

    var body: some View {
        if let disks = snapshot.disks, !disks.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                SectionHeader(text: "Disks")
                ForEach(disks) { disk in
                    VStack(alignment: .leading, spacing: 2) {
                        StatRow(
                            label: disk.mountpoint,
                            value: SystemVitals.formatPercent(disk.usedRatio)
                        )
                        let usedStr = SystemVitals.formatBytes(disk.usedBytes)
                        let totalStr = SystemVitals.formatBytes(disk.totalBytes)
                        Text("\(usedStr) used of \(totalStr)")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.large)
            .glassCardBackground()
        }
    }
}

// MARK: - Network

private struct SystemNetworkCard: View {
    let snapshot: BoothSystemSnapshot

    var body: some View {
        if let interfaces = snapshot.networkInterfaces, !interfaces.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                SectionHeader(text: "Network")
                ForEach(interfaces) { iface in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(iface.name)
                            .font(Theme.Fonts.bodyMedium.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        HStack(spacing: 12) {
                            Label(SystemVitals.formatBytes(iface.receivedBytes), systemImage: "arrow.down")
                            Label(SystemVitals.formatBytes(iface.transmittedBytes), systemImage: "arrow.up")
                        }
                        .font(Theme.Fonts.caption.monospacedDigit())
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.large)
            .glassCardBackground()
        }
    }
}

// MARK: - Audio

private struct SystemAudioCard: View {
    let snapshot: BoothSystemSnapshot

    var body: some View {
        let hasContent = snapshot.audioInputDevice != nil
            || snapshot.audioOutputDevice != nil
            || snapshot.audioInputDbfs != nil
            || snapshot.audioOutputDbfs != nil
        if hasContent {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                SectionHeader(text: "Audio")
                if let input = snapshot.audioInputDevice {
                    StatRow(label: "Input", value: input)
                }
                if let dbfs = snapshot.audioInputDbfs {
                    StatRow(label: "Input level", value: String(format: "%.1f dBFS", dbfs))
                }
                if let output = snapshot.audioOutputDevice {
                    StatRow(label: "Output", value: output)
                }
                if let dbfs = snapshot.audioOutputDbfs {
                    StatRow(label: "Output level", value: String(format: "%.1f dBFS", dbfs))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.large)
            .glassCardBackground()
        }
    }
}

// MARK: - Connectivity

private struct SystemConnectivityCard: View {
    let snapshot: BoothSystemSnapshot

    var body: some View {
        let hasContent = snapshot.tailscaleConnected != nil
            || snapshot.tailscaleHostname != nil
            || !(snapshot.throttlingFlags ?? []).isEmpty
        if hasContent {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                SectionHeader(text: "Connectivity")
                if let connected = snapshot.tailscaleConnected {
                    StatRow(label: "Tailscale", value: connected ? "Connected" : "Offline")
                }
                if let hostname = snapshot.tailscaleHostname {
                    StatRow(label: "Tailscale host", value: hostname)
                }
                if let flags = snapshot.throttlingFlags, !flags.isEmpty {
                    StatRow(label: "Throttling", value: flags.joined(separator: ", "))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.large)
            .glassCardBackground()
        }
    }
}
