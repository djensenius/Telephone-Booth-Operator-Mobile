//
//  TVSystemView.swift
//  TelephoneBoothOperatorMobile
//
//  Big-screen System dashboard for tvOS. Read-only by design. Uses the
//  `TVDashboardKit` scaffold so the whole thing scrolls (each card is
//  focusable) and stays inside the title-safe area — fixing the previous
//  build where content ran under the sidebar and off the bottom with no
//  way to reach the CPU cores, memory, disks, etc.
//

#if os(tvOS)

import SwiftUI

struct TVSystemView: View {
    @State private var envelope: BoothSystemSnapshotEnvelope?
    @State private var loading = false
    @State private var errorMessage: String?

    private let client: OperatorClient

    init(client: OperatorClient = .shared) {
        self.client = client
    }

    var body: some View {
        TVScreen(title: "System", systemImage: "cpu", accessory: { accessory }, content: {
            if let envelope {
                content(envelope: envelope)
            } else if loading {
                loadingState
            } else {
                emptyState
            }
        })
        .task { await pollLoop() }
    }

    @ViewBuilder
    private var accessory: some View {
        if let envelope {
            HStack(spacing: 18) {
                RuntimeModeBadge(mode: envelope.snapshot.runtimeMode)
                    .scaleEffect(1.4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Updated")
                        .font(TVMetrics.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(envelope.receivedAt, style: .time)
                        .font(.system(size: 30, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private func content(envelope: BoothSystemSnapshotEnvelope) -> some View {
        let snapshot = envelope.snapshot

        if let errorMessage {
            TVBanner(message: errorMessage)
        }

        TVSystemVitals(snapshot: snapshot)

        TVCardGrid {
            TVSystemHostCard(
                boothId: envelope.boothId,
                snapshot: snapshot,
                receivedAt: envelope.receivedAt,
                version: envelope.version
            )
            TVSystemCPUCard(snapshot: snapshot)
            TVSystemMemoryCard(snapshot: snapshot)
            TVSystemDisksCard(snapshot: snapshot)
            TVSystemNetworkCard(snapshot: snapshot)
            TVSystemAudioConnectivityCard(snapshot: snapshot)
        }
    }

    private var loadingState: some View {
        TVFocusCard {
            HStack(spacing: 20) {
                ProgressView()
                Text("Loading system status…")
                    .font(TVMetrics.Font.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var emptyState: some View {
        TVFocusCard {
            VStack(alignment: .leading, spacing: 10) {
                TVCardHeader(title: "No snapshot yet", systemImage: "clock.arrow.circlepath")
                Text("No system snapshot has been received from the booth yet.")
                    .font(TVMetrics.Font.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(10))
        }
    }

    private func refresh() async {
        if envelope == nil { loading = true }
        defer { loading = false }
        do {
            envelope = try await client.fetchCurrentSystemEnvelope()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't load system status."
        }
    }
}

// MARK: - Vitals strip

private struct TVSystemVitals: View {
    let snapshot: BoothSystemSnapshot

    var body: some View {
        TVFocusCard {
            VStack(alignment: .leading, spacing: 24) {
                TVCardHeader(title: "Live vitals", systemImage: "waveform.path.ecg")
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 20),
                        count: 5
                    ),
                    spacing: 20
                ) {
                    TVStatTile(
                        label: "CPU temp",
                        value: temperature,
                        tint: SystemVitals.temperatureSeverity(snapshot.cpuTemperatureCelsius).tint
                    )
                    TVStatTile(label: "CPU", value: cpuUsage)
                    TVStatTile(
                        label: "Load 1m",
                        value: SystemVitals.formatNumber(snapshot.loadAverage1m),
                        tint: SystemVitals.loadSeverity(
                            snapshot.loadAverage1m,
                            cores: snapshot.cpuCoreCount
                        ).tint
                    )
                    TVStatTile(
                        label: "Memory",
                        value: SystemVitals.formatPercent(snapshot.memoryUsedRatio),
                        tint: SystemVitals.memorySeverity(snapshot.memoryUsedRatio).tint
                    )
                    TVStatTile(
                        label: "Uptime",
                        value: SystemVitals.formatUptime(snapshot.uptimeSeconds)
                    )
                }
            }
        }
    }

    private var temperature: String {
        guard let temp = snapshot.cpuTemperatureCelsius else { return "—" }
        return String(format: "%.1f°", temp)
    }

    private var cpuUsage: String {
        guard let ratio = snapshot.cpuUsageRatio else { return "—" }
        return String(format: "%.0f%%", max(0, min(1, ratio)) * 100)
    }
}

// MARK: - Host

private struct TVSystemHostCard: View {
    let boothId: String
    let snapshot: BoothSystemSnapshot
    let receivedAt: Date
    let version: String?

    var body: some View {
        TVFocusCard {
            VStack(alignment: .leading, spacing: 16) {
                TVCardHeader(title: "Booth \(boothId)", systemImage: "server.rack")
                if let version, !version.isEmpty {
                    TVKeyValueRow(key: "Client version", value: version)
                }
                if let hostname = snapshot.hostname {
                    TVKeyValueRow(key: "Hostname", value: hostname)
                }
                if let osVersion = snapshot.osVersion {
                    TVKeyValueRow(key: "OS", value: osVersion)
                }
                if let kernel = snapshot.kernelVersion {
                    TVKeyValueRow(key: "Kernel", value: kernel)
                }
                if let uptime = snapshot.uptimeSeconds {
                    TVKeyValueRow(key: "Uptime", value: SystemVitals.formatUptime(uptime))
                }
                TVKeyValueRow(
                    key: "Received",
                    value: receivedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                )
            }
        }
    }
}

// MARK: - CPU

private struct TVSystemCPUCard: View {
    let snapshot: BoothSystemSnapshot

    var body: some View {
        TVFocusCard {
            VStack(alignment: .leading, spacing: 16) {
                TVCardHeader(title: "CPU", systemImage: "cpu")
                if let temp = snapshot.cpuTemperatureCelsius {
                    TVKeyValueRow(key: "Temperature", value: String(format: "%.1f °C", temp))
                }
                if let usage = snapshot.cpuUsageRatio {
                    TVKeyValueRow(key: "Usage", value: SystemVitals.formatPercent(usage))
                }
                if snapshot.loadAverage1m != nil {
                    TVKeyValueRow(key: "Load 1 / 5 / 15m", value: load)
                }
                if let cores = snapshot.cpuUsageRatioPerCore, !cores.isEmpty {
                    Divider().overlay(Theme.Colors.textSecondary.opacity(0.25))
                    ForEach(Array(cores.enumerated()), id: \.offset) { index, usage in
                        TVCoreBar(index: index, usage: usage)
                    }
                }
            }
        }
    }

    private var load: String {
        let load1 = SystemVitals.formatNumber(snapshot.loadAverage1m)
        let load5 = SystemVitals.formatNumber(snapshot.loadAverage5m)
        let load15 = SystemVitals.formatNumber(snapshot.loadAverage15m)
        return "\(load1) / \(load5) / \(load15)"
    }
}

private struct TVCoreBar: View {
    let index: Int
    let usage: Double

    var body: some View {
        HStack(spacing: 18) {
            Text("Core \(index)")
                .font(TVMetrics.Font.body.monospacedDigit())
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 130, alignment: .leading)
            GeometryReader { proxy in
                let clamped = max(0, min(1, usage))
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.textSecondary.opacity(0.18))
                    Capsule()
                        .fill(color)
                        .frame(width: max(6, proxy.size.width * clamped))
                }
            }
            .frame(height: 14)
            Text(SystemVitals.formatPercent(usage))
                .font(TVMetrics.Font.rowValue)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: 90, alignment: .trailing)
        }
    }

    private var color: Color {
        if usage >= 0.9 { return Theme.Colors.error }
        if usage >= 0.7 { return Theme.Colors.warning }
        return Theme.Colors.success
    }
}

// MARK: - Memory

private struct TVSystemMemoryCard: View {
    let snapshot: BoothSystemSnapshot

    var body: some View {
        TVFocusCard {
            VStack(alignment: .leading, spacing: 16) {
                TVCardHeader(title: "Memory", systemImage: "memorychip")
                if let ratio = snapshot.memoryUsedRatio {
                    TVKeyValueRow(key: "RAM used", value: SystemVitals.formatPercent(ratio))
                }
                if let used = snapshot.memoryUsedBytes, let total = snapshot.memoryTotalBytes {
                    TVKeyValueRow(
                        key: "RAM",
                        value: "\(SystemVitals.formatBytes(used)) / \(SystemVitals.formatBytes(total))"
                    )
                }
                if let swapRatio = snapshot.swapUsedRatio {
                    TVKeyValueRow(key: "Swap used", value: SystemVitals.formatPercent(swapRatio))
                }
                if let used = snapshot.swapUsedBytes, let total = snapshot.swapTotalBytes, total > 0 {
                    TVKeyValueRow(
                        key: "Swap",
                        value: "\(SystemVitals.formatBytes(used)) / \(SystemVitals.formatBytes(total))"
                    )
                }
            }
        }
    }
}

// MARK: - Disks

private struct TVSystemDisksCard: View {
    let snapshot: BoothSystemSnapshot

    var body: some View {
        if let disks = snapshot.disks, !disks.isEmpty {
            TVFocusCard {
                VStack(alignment: .leading, spacing: 16) {
                    TVCardHeader(title: "Disks", systemImage: "internaldrive")
                    ForEach(disks) { disk in
                        VStack(alignment: .leading, spacing: 4) {
                            TVKeyValueRow(
                                key: disk.mountpoint,
                                value: SystemVitals.formatPercent(disk.usedRatio)
                            )
                            Text(
                                "\(SystemVitals.formatBytes(disk.usedBytes)) used of "
                                + SystemVitals.formatBytes(disk.totalBytes)
                            )
                            .font(TVMetrics.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Network

private struct TVSystemNetworkCard: View {
    let snapshot: BoothSystemSnapshot

    var body: some View {
        if let interfaces = snapshot.networkInterfaces, !interfaces.isEmpty {
            TVFocusCard {
                VStack(alignment: .leading, spacing: 16) {
                    TVCardHeader(title: "Network", systemImage: "network")
                    ForEach(interfaces) { iface in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(iface.name)
                                .font(TVMetrics.Font.rowValue)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            if !iface.ipAddresses.isEmpty {
                                Text(iface.ipAddresses.joined(separator: ", "))
                                    .font(TVMetrics.Font.caption.monospaced())
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            HStack(spacing: 28) {
                                Label(
                                    SystemVitals.formatBytes(iface.receivedBytes),
                                    systemImage: "arrow.down"
                                )
                                Label(
                                    SystemVitals.formatBytes(iface.transmittedBytes),
                                    systemImage: "arrow.up"
                                )
                            }
                            .font(TVMetrics.Font.caption.monospacedDigit())
                            .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Audio + connectivity

private struct TVSystemAudioConnectivityCard: View {
    let snapshot: BoothSystemSnapshot

    private var hasAudio: Bool {
        snapshot.audioInputDevice != nil
            || snapshot.audioOutputDevice != nil
            || snapshot.audioInputDbfs != nil
            || snapshot.audioOutputDbfs != nil
    }

    private var hasConnectivity: Bool {
        snapshot.tailscaleConnected != nil
            || snapshot.tailscaleHostname != nil
            || !(snapshot.throttlingFlags ?? []).isEmpty
    }

    var body: some View {
        if hasAudio || hasConnectivity {
            TVFocusCard {
                VStack(alignment: .leading, spacing: 20) {
                    if hasAudio {
                        VStack(alignment: .leading, spacing: 16) {
                            TVCardHeader(title: "Audio", systemImage: "speaker.wave.2")
                            if let input = snapshot.audioInputDevice {
                                TVKeyValueRow(key: "Input", value: input)
                            }
                            if let dbfs = snapshot.audioInputDbfs {
                                TVKeyValueRow(key: "Input level", value: String(format: "%.1f dBFS", dbfs))
                            }
                            if let output = snapshot.audioOutputDevice {
                                TVKeyValueRow(key: "Output", value: output)
                            }
                            if let dbfs = snapshot.audioOutputDbfs {
                                TVKeyValueRow(key: "Output level", value: String(format: "%.1f dBFS", dbfs))
                            }
                        }
                    }
                    if hasConnectivity {
                        if hasAudio {
                            Divider().overlay(Theme.Colors.textSecondary.opacity(0.25))
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            TVCardHeader(title: "Connectivity", systemImage: "point.3.connected.trianglepath.dotted")
                            if let connected = snapshot.tailscaleConnected {
                                TVKeyValueRow(
                                    key: "Tailscale",
                                    value: connected ? "Connected" : "Offline",
                                    valueTint: connected ? Theme.Colors.success : Theme.Colors.error
                                )
                            }
                            if let hostname = snapshot.tailscaleHostname {
                                TVKeyValueRow(key: "Tailscale host", value: hostname)
                            }
                            if let flags = snapshot.throttlingFlags, !flags.isEmpty {
                                TVKeyValueRow(
                                    key: "Throttling",
                                    value: flags.joined(separator: ", "),
                                    valueTint: Theme.Colors.warning
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Banner

struct TVBanner: View {
    let message: String

    var body: some View {
        TVFocusCard {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(TVMetrics.Font.body)
                .foregroundStyle(Theme.Colors.error)
        }
    }
}

#Preview {
    TVSystemView(client: .demo)
}

#endif
