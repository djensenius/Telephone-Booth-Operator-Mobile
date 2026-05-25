//
//  LiveActivityManager.swift
//  TelephoneBoothOperatorMobile
//
//  Manages the lifecycle of the CallInProgress Live Activity. Starts
//  it when a call begins, updates it on state transitions, and ends it
//  when the call concludes. Only compiled on platforms with ActivityKit.
//

#if canImport(ActivityKit)
import ActivityKit
import Foundation
import os

private let logger = Logger(
    subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
    category: "LiveActivityManager"
)

@MainActor
public final class LiveActivityManager: Sendable {
    public static let shared = LiveActivityManager()

    private init() {}

    // MARK: - Public API

    /// Starts a new Live Activity for the given call session. If one is
    /// already running for this session it is updated instead.
    public func callStarted(
        sessionId: String,
        boothName: String,
        boothState: String,
        startedAt: Date,
        digitsDialed: String? = nil
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.info("Live Activities disabled by user; skipping start")
            return
        }

        let attributes = CallInProgressAttributes(
            boothName: boothName,
            sessionId: sessionId
        )
        let state = CallInProgressAttributes.ContentState(
            boothState: boothState,
            startedAt: startedAt,
            digitsDialed: digitsDialed
        )

        // If an activity for this session already exists, update it.
        if let existing = existingActivity(sessionId: sessionId) {
            Task {
                await existing.update(
                    ActivityContent(state: state, staleDate: nil)
                )
            }
            return
        }

        do {
            let content = ActivityContent(state: state, staleDate: nil)
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            logger.info("Started Live Activity \(activity.id, privacy: .public) for session \(sessionId, privacy: .public)")
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Updates the running Live Activity for the given session with a new
    /// booth state (e.g. on state_transition events).
    public func callUpdated(
        sessionId: String,
        boothState: String,
        digitsDialed: String? = nil
    ) {
        guard let activity = existingActivity(sessionId: sessionId) else {
            logger.debug("No active Live Activity for session \(sessionId, privacy: .public); ignoring update")
            return
        }

        // Preserve the original startedAt from the current content state.
        let currentState = activity.content.state
        let newState = CallInProgressAttributes.ContentState(
            boothState: boothState,
            startedAt: currentState.startedAt,
            digitsDialed: digitsDialed ?? currentState.digitsDialed
        )

        Task {
            await activity.update(
                ActivityContent(state: newState, staleDate: nil)
            )
        }
    }

    /// Ends the Live Activity for the given session.
    public func callEnded(sessionId: String) {
        guard let activity = existingActivity(sessionId: sessionId) else {
            logger.debug("No active Live Activity for session \(sessionId, privacy: .public); ignoring end")
            return
        }

        let finalState = activity.content.state
        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .after(.now + 30)
            )
            logger.info("Ended Live Activity for session \(sessionId, privacy: .public)")
        }
    }

    /// Ends all running call activities. Useful on sign-out or app reset.
    public func endAll() {
        for activity in Activity<CallInProgressAttributes>.activities {
            let state = activity.content.state
            Task {
                await activity.end(
                    ActivityContent(state: state, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
        }
    }

    // MARK: - Private

    private func existingActivity(
        sessionId: String
    ) -> Activity<CallInProgressAttributes>? {
        Activity<CallInProgressAttributes>.activities.first {
            $0.attributes.sessionId == sessionId
        }
    }
}
#endif
