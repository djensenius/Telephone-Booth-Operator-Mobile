//
//  LiveActivityEventObserver.swift
//  TelephoneBoothOperatorMobile
//
//  Subscribes to the SSE event stream and forwards call lifecycle
//  events to LiveActivityManager to start/update/end Live Activities.
//  Attached as a background task to the signed-in root view.
//

#if canImport(ActivityKit) && !os(macOS)
import ActivityKit
import Foundation
import os

private let logger = Logger(
    subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
    category: "LiveActivityEventObserver"
)

@MainActor
public final class LiveActivityEventObserver {
    public static let shared = LiveActivityEventObserver()

    private var observeTask: Task<Void, Never>?
    private let stream: EventStream
    private let manager: LiveActivityManager

    public init(
        stream: EventStream = .shared,
        manager: LiveActivityManager = .shared
    ) {
        self.stream = stream
        self.manager = manager
    }

    /// Starts observing the SSE stream for call lifecycle events.
    /// Automatically reconnects with backoff on transient failures.
    public func start() {
        guard observeTask == nil else { return }
        observeTask = Task { [weak self] in
            guard let self else { return }
            await self.observeLoop()
        }
    }

    /// Stops the observation loop and ends any running activities.
    public func stop() {
        observeTask?.cancel()
        observeTask = nil
    }

    private func observeLoop() async {
        var backoff: UInt64 = 1_000_000_000 // 1 second initial
        let maxBackoff: UInt64 = 30_000_000_000 // 30 seconds max

        while !Task.isCancelled {
            do {
                for try await event in stream.subscribe() {
                    if Task.isCancelled { break }
                    backoff = 1_000_000_000
                    handleEvent(event)
                }
            } catch is CancellationError {
                break
            } catch {
                logger.warning(
                    "Live Activity observer stream error: \(error.localizedDescription, privacy: .public)"
                )
            }

            guard !Task.isCancelled else { break }
            try? await Task.sleep(nanoseconds: backoff)
            backoff = min(backoff * 2, maxBackoff)
        }
    }

    private func handleEvent(_ event: BoothEventRecord) {
        switch event.type {
        case .callStarted:
            manager.callStarted(
                sessionId: event.sessionId ?? event.id,
                boothName: event.boothId,
                boothState: BoothState.dialing.rawValue,
                startedAt: event.occurredAt
            )

        case .stateTransition:
            guard let sessionId = event.sessionId else { return }
            manager.callUpdated(
                sessionId: sessionId,
                boothState: "active"
            )

        case .callEnded:
            let sessionId = event.sessionId ?? event.id
            manager.callEnded(sessionId: sessionId)

        default:
            break
        }
    }
}
#endif
