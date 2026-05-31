//
//  EventsFeedView.swift
//  TelephoneBoothOperatorMobile
//
//  Live tail of booth events using the operator's /v1/events/stream SSE
//  endpoint, with a paged /v1/events fallback that backfills history on
//  first open. Filter chips narrow the feed by event type without
//  reconnecting (the filter is applied client-side over the live stream).
//

#if !os(watchOS) && !os(tvOS)

import SwiftUI

public struct EventsFeedView: View {
    @State private var events: [BoothEventRecord] = []
    @State private var streamError: String?
    @State private var historyError: String?
    @State private var typeFilter: BoothEventType?
    @State private var isStreaming: Bool = false
    @State private var isReconnecting: Bool = false
    @State private var streamTask: Task<Void, Never>?
    @State private var reconnectTask: Task<Void, Never>?
    @State private var reconnectDelay: TimeInterval = 0

    private let client: OperatorClient
    private let stream: EventStream
    private let bufferLimit: Int

    public init(
        client: OperatorClient = .shared,
        stream: EventStream = .shared,
        bufferLimit: Int = 300
    ) {
        self.client = client
        self.stream = stream
        self.bufferLimit = bufferLimit
    }

    public var body: some View {
        List {
            statusHeader
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if let streamError {
                BannerView(message: streamError, kind: .error)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if filteredEvents.isEmpty {
                emptyRow
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(filteredEvents) { event in
                    BoothEventFeedRow(event: event)
                        .operatorListRowBackground()
                }
            }
        }
        .operatorListStyle()
        .background(Theme.Colors.background)
        .toolbar {
            ToolbarItem(placement: operatorFilterPlacement) {
                filterMenu
            }
        }
        .task {
            await loadHistory()
            startStream()
        }
        .onDisappear {
            stopStream()
        }
        .refreshableIfAvailable {
            await loadHistory()
        }
    }

    private var statusHeader: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Circle()
                .fill(isStreaming ? Theme.Colors.success
                      : isReconnecting ? Theme.Colors.warning
                      : Theme.Colors.textSecondary)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(isStreaming ? "Live"
                 : isReconnecting ? "Reconnecting…"
                 : "Disconnected")
                .font(Theme.Fonts.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            if let typeFilter {
                Text("• \(typeFilter.displayName)")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            if let historyError {
                Text(historyError)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.error)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, Theme.Spacing.small)
    }

    private var emptyRow: some View {
        VStack(spacing: Theme.Spacing.medium) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(typeFilter == nil ? "Waiting for booth events…" : "No matching events yet")
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.extraLarge)
    }

    private var filterMenu: some View {
        Menu {
            Button {
                typeFilter = nil
            } label: {
                Label("All events", systemImage: typeFilter == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(BoothEventType.knownCases, id: \.self) { type in
                Button {
                    typeFilter = type
                } label: {
                    Label(type.displayName, systemImage: typeFilter == type ? "checkmark" : "")
                }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter events by type")
    }

    private var filteredEvents: [BoothEventRecord] {
        guard let typeFilter else { return events }
        return events.filter { $0.type == typeFilter }
    }

    private func loadHistory() async {
        historyError = nil
        do {
            let page = try await client.fetchEvents(limit: 100)
            var existing = Set(events.map(\.id))
            var combined = events
            for item in page.items where !existing.contains(item.id) {
                combined.append(item)
                existing.insert(item.id)
            }
            combined.sort { $0.receivedAt > $1.receivedAt }
            events = Array(combined.prefix(bufferLimit))
        } catch {
            historyError = (error as? LocalizedError)?.errorDescription ?? "Couldn't load recent events."
        }
    }

    private static let maxReconnectDelay: TimeInterval = 30
    private static let initialReconnectDelay: TimeInterval = 1

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
                // Intentional teardown — no reconnect
            } catch {
                streamError = (error as? LocalizedError)?.errorDescription ?? "Live stream disconnected."
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
        isReconnecting = false
    }

    private func scheduleReconnect() {
        let nextDelay = reconnectDelay == 0
            ? Self.initialReconnectDelay
            : min(reconnectDelay * 2, Self.maxReconnectDelay)
        reconnectDelay = nextDelay
        isReconnecting = true
        reconnectTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(nextDelay))
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
        if events.contains(where: { $0.id == record.id }) { return }
        events.insert(record, at: 0)
        if events.count > bufferLimit {
            events.removeLast(events.count - bufferLimit)
        }
    }
}

struct BoothEventFeedRow: View {
    let event: BoothEventRecord

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                Label(event.type.displayName, systemImage: icon(for: event.type))
                    .font(Theme.Fonts.bodyMedium.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text(event.occurredAt, format: .dateTime.hour().minute().second())
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            HStack(spacing: Theme.Spacing.medium) {
                Label(event.boothId, systemImage: "phone.fill")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                if let sessionId = event.sessionId {
                    Label(String(sessionId.prefix(8)), systemImage: "rectangle.connected.to.line.below")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                if let recordingId = event.recordingId {
                    Label(String(recordingId.prefix(8)), systemImage: "waveform")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.small)
    }

    private func icon(for type: BoothEventType) -> String {
        BoothEventFeedRow.icons[type] ?? "dot.circle"
    }

    private static let icons: [BoothEventType: String] = [
        .callStarted: "phone.arrow.up.right",
        .callEnded: "phone.down",
        .digitDialed: "number",
        .stateTransition: "arrow.right.circle",
        .recordingStarted: "record.circle",
        .recordingStopped: "stop.circle",
        .uploadStarted: "arrow.up.circle",
        .uploadCompleted: "checkmark.circle",
        .uploadFailed: "xmark.circle",
        .gpioEdge: "bolt",
        .audioDeviceChange: "speaker.wave.2",
        .operatorRequest: "person.crop.circle.badge.questionmark",
        .operatorResponse: "person.crop.circle.badge.checkmark",
        .error: "exclamationmark.triangle.fill",
        .log: "doc.text",
        .systemSample: "waveform.path.ecg"
    ]
}

#endif
