//
//  TVEventsView.swift
//  TelephoneBoothOperatorMobile
//
//  Live, filterable event tail sized for tvOS.
//

#if os(tvOS)

import SwiftUI

struct TVEventsView: View {
    @State private var events: [BoothEventRecord] = []
    @State private var typeFilter: BoothEventType?
    @State private var historyError: String?
    @State private var streamError: String?
    @State private var isStreaming = false
    @State private var isReconnecting = false
    @State private var streamTask: Task<Void, Never>?
    @State private var reconnectTask: Task<Void, Never>?
    @State private var reconnectDelay: TimeInterval = 0

    private let client: OperatorClient
    private let stream: EventStream
    private let bufferLimit: Int

    init(
        client: OperatorClient = .shared,
        stream: EventStream = .shared,
        bufferLimit: Int = 300
    ) {
        self.client = client
        self.stream = stream
        self.bufferLimit = bufferLimit
    }

    var body: some View {
        TVScreen(
            title: "Events",
            systemImage: "antenna.radiowaves.left.and.right",
            accessory: { statusAccessory },
            content: {
                filterMenu

                if let historyError {
                    TVBanner(message: historyError)
                }
                if let streamError {
                    TVBanner(message: streamError)
                }

                if filteredEvents.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredEvents) { event in
                        TVEventCard(event: event)
                    }
                }
            }
        )
        .autoRefresh(every: .seconds(60)) {
            await loadHistory()
        }
        .task {
            startStream()
        }
        .onDisappear {
            stopStream()
        }
    }

    private var statusAccessory: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(statusColor)
                .frame(width: 14, height: 14)
            VStack(alignment: .trailing, spacing: 2) {
                Text(statusLabel)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("\(filteredEvents.count) shown")
                    .font(TVMetrics.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var statusColor: Color {
        if isStreaming { return Theme.Colors.success }
        if isReconnecting { return Theme.Colors.warning }
        return Theme.Colors.textSecondary
    }

    private var statusLabel: String {
        if isStreaming { return "Live" }
        if isReconnecting { return "Reconnecting…" }
        return "Disconnected"
    }

    private var filterMenu: some View {
        Menu {
            Button {
                typeFilter = nil
            } label: {
                if typeFilter == nil {
                    Label("All events", systemImage: "checkmark")
                } else {
                    Text("All events")
                }
            }
            Divider()
            ForEach(BoothEventType.knownCases, id: \.self) { type in
                Button {
                    typeFilter = type
                } label: {
                    if typeFilter == type {
                        Label(type.displayName, systemImage: "checkmark")
                    } else {
                        Text(type.displayName)
                    }
                }
            }
        } label: {
            Label(
                typeFilter?.displayName ?? "All events",
                systemImage: "line.3.horizontal.decrease.circle"
            )
            .font(.system(size: 30, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
        .buttonStyle(TVSegmentButtonStyle(isSelected: typeFilter != nil))
    }

    private var emptyState: some View {
        TVFocusCard {
            HStack(spacing: 22) {
                ProgressView()
                Text(typeFilter == nil ? "Waiting for booth events…" : "No matching events")
                    .font(TVMetrics.Font.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var filteredEvents: [BoothEventRecord] {
        guard let typeFilter else { return events }
        return events.filter { $0.type == typeFilter }
    }

    private func loadHistory() async {
        do {
            let page = try await client.fetchEvents(limit: 100)
            guard !Task.isCancelled else { return }
            var existing = Set(events.map(\.id))
            var combined = events
            for item in page.items where !existing.contains(item.id) {
                combined.append(item)
                existing.insert(item.id)
            }
            combined.sort { $0.receivedAt > $1.receivedAt }
            events = Array(combined.prefix(bufferLimit))
            historyError = nil
        } catch {
            guard !Task.isCancelled else { return }
            historyError = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't load recent events."
        }
    }

    private func startStream() {
        guard streamTask == nil else { return }
        cancelReconnect()
        streamError = nil
        let eventStream = stream
        streamTask = Task { @MainActor in
            defer {
                streamTask = nil
                isStreaming = false
            }
            do {
                isStreaming = true
                var didReceiveEvent = false
                for try await record in eventStream.subscribe() {
                    if Task.isCancelled { break }
                    if !didReceiveEvent {
                        didReceiveEvent = true
                        reconnectDelay = 0
                    }
                    appendLive(record)
                }
                if !Task.isCancelled {
                    scheduleReconnect()
                }
            } catch is CancellationError {
                return
            } catch {
                streamError = (error as? LocalizedError)?.errorDescription
                    ?? "Live stream disconnected."
                if !Task.isCancelled {
                    scheduleReconnect()
                }
            }
        }
    }

    private func stopStream() {
        streamTask?.cancel()
        streamTask = nil
        cancelReconnect()
        isStreaming = false
    }

    private func scheduleReconnect() {
        let nextDelay = reconnectDelay == 0 ? 1 : min(reconnectDelay * 2, 30)
        reconnectDelay = nextDelay
        isReconnecting = true
        reconnectTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(nextDelay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            isReconnecting = false
            startStream()
        }
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false
    }

    private func appendLive(_ record: BoothEventRecord) {
        guard !events.contains(where: { $0.id == record.id }) else { return }
        events.insert(record, at: 0)
        if events.count > bufferLimit {
            events.removeLast(events.count - bufferLimit)
        }
    }
}

private struct TVEventCard: View {
    let event: BoothEventRecord

    var body: some View {
        TVFocusCard {
            HStack(alignment: .top, spacing: 24) {
                Image(systemName: event.type.tvSymbol)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(event.type.tvTint)
                    .frame(width: 54)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(event.type.displayName)
                            .font(TVMetrics.Font.cardTitle)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer(minLength: 20)
                        Text(
                            event.occurredAt,
                            format: .dateTime.month(.abbreviated)
                                .day().hour().minute().second()
                        )
                        .font(TVMetrics.Font.rowValue)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    HStack(spacing: 28) {
                        Label("Booth \(event.boothId)", systemImage: "phone.fill")
                        if let sessionId = event.sessionId {
                            Label(
                                String(sessionId.prefix(12)),
                                systemImage: "rectangle.connected.to.line.below"
                            )
                        }
                        if let recordingId = event.recordingId {
                            Label(
                                String(recordingId.prefix(12)),
                                systemImage: "waveform"
                            )
                        }
                    }
                    .font(TVMetrics.Font.caption.monospaced())
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }
}

#Preview {
    TVEventsView(client: .demo, stream: .demo)
}

#endif
