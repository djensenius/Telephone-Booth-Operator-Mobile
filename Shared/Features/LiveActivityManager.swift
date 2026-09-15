//
//  LiveActivityManager.swift
//  TelephoneBoothOperatorMobile
//
//  Manages the lifecycle of the CallInProgress Live Activity. Starts
//  it when a call begins, updates it on state transitions, and ends it
//  when the call concludes. Only compiled on platforms with ActivityKit.
//

#if canImport(ActivityKit) && !os(macOS)
import ActivityKit
import Foundation
import os

private let logger = Logger(
    subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
    category: "LiveActivityManager"
)

@MainActor
public final class LiveActivityManager {
    public static let shared = LiveActivityManager()

    typealias ActivityRequest = (
        CallInProgressAttributes, ActivityContent<CallInProgressAttributes.ContentState>
    ) throws -> String
    private let activitiesEnabled: () -> Bool
    private let requestActivity: ActivityRequest
    private let endActivities: (InstallationState?) -> Void

    init(
        activitiesEnabled: @escaping () -> Bool = { ActivityAuthorizationInfo().areActivitiesEnabled },
        requestActivity: @escaping ActivityRequest = { attributes, content in
            try Activity.request(attributes: attributes, content: content, pushType: nil).id
        },
        endActivities: @escaping (InstallationState?) -> Void = { state in
            LiveActivityManager.endAllActivities(installationState: state)
        }
    ) {
        self.activitiesEnabled = activitiesEnabled
        self.requestActivity = requestActivity
        self.endActivities = endActivities
    }
    public private(set) var installationState: InstallationState?

    public func setInstallationState(_ state: InstallationState?) {
        guard let state else { return }
        installationState = state
        if state == .betweenExhibitions { endAll(installationState: state) }
    }

    func resetInstallationState(_ state: InstallationState?) {
        installationState = state
        endAll(installationState: state)
    }

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
        guard installationState != .betweenExhibitions else { return }
        guard activitiesEnabled() else {
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
        if let existing = Self.existingActivity(sessionId: sessionId) {
            let mergedState = CallInProgressAttributes.ContentState(
                boothState: boothState,
                startedAt: startedAt,
                digitsDialed: digitsDialed ?? existing.content.state.digitsDialed
            )
            Task {
                await Self.updateActivity(
                    sessionId: sessionId,
                    state: mergedState
                )
            }
            return
        }

        do {
            let content = ActivityContent(state: state, staleDate: nil)
            let activityID = try requestActivity(attributes, content)
            logger.info(
                "Started Live Activity \(activityID, privacy: .public) for session \(sessionId, privacy: .public)"
            )
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
        guard installationState != .betweenExhibitions else { return }
        guard let activity = Self.existingActivity(sessionId: sessionId) else {
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
            await Self.updateActivity(
                sessionId: sessionId,
                state: newState
            )
        }
    }

    /// Ends the Live Activity for the given session.
    public func callEnded(sessionId: String) {
        guard let activity = Self.existingActivity(sessionId: sessionId) else {
            logger.debug("No active Live Activity for session \(sessionId, privacy: .public); ignoring end")
            return
        }

        let finalState = activity.content.state
        Task {
            await Self.endActivity(
                sessionId: sessionId,
                state: finalState,
                dismissalPolicy: .after(.now + 30)
            )
            logger.info("Ended Live Activity for session \(sessionId, privacy: .public)")
        }
    }

    /// Ends all running call activities. Useful on sign-out or app reset.
    public func endAll(installationState: InstallationState? = nil) {
        endActivities(installationState)
    }

    private static func endAllActivities(installationState: InstallationState?) {
        let activeSessions = Activity<CallInProgressAttributes>.activities.map {
            (sessionId: $0.attributes.sessionId, state: $0.content.state)
        }

        for activeSession in activeSessions {
            Task {
                await Self.endActivity(
                    sessionId: activeSession.sessionId,
                    state: CallInProgressAttributes.ContentState(
                        boothState: activeSession.state.boothState,
                        startedAt: activeSession.state.startedAt,
                        digitsDialed: activeSession.state.digitsDialed,
                        installationState: installationState
                    ),
                    dismissalPolicy: .immediate
                )
            }
        }
    }

    // MARK: - Private

    private nonisolated static func updateActivity(
        sessionId: String,
        state: CallInProgressAttributes.ContentState
    ) async {
        guard let activity = existingActivity(sessionId: sessionId) else {
            return
        }

        await activity.update(
            ActivityContent(state: state, staleDate: nil)
        )
    }

    private nonisolated static func endActivity(
        sessionId: String,
        state: CallInProgressAttributes.ContentState,
        dismissalPolicy: ActivityUIDismissalPolicy
    ) async {
        guard let activity = existingActivity(sessionId: sessionId) else {
            return
        }

        await activity.end(
            ActivityContent(state: state, staleDate: nil),
            dismissalPolicy: dismissalPolicy
        )
    }

    private nonisolated static func existingActivity(
        sessionId: String
    ) -> Activity<CallInProgressAttributes>? {
        Activity<CallInProgressAttributes>.activities.first {
            $0.attributes.sessionId == sessionId
        }
    }
}
#endif
