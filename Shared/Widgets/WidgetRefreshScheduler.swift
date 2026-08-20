//
//  WidgetRefreshScheduler.swift
//  TelephoneBoothOperatorMobile
//

import Foundation
import os

@MainActor
public enum WidgetRefreshScheduler {
    public static let taskIdentifier = "org.davidjensenius.TBOperatorMobile.widget-refresh"
    public static let refreshInterval: TimeInterval = 15 * 60

    nonisolated static let logger = Logger(
        subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
        category: "WidgetRefreshScheduler"
    )

    public static func refreshNow() async -> WidgetRefreshResult {
        guard !Task.isCancelled else {
            logger.notice("Widget refresh was cancelled before it started")
            return .failed
        }

        guard await AuthManager.shared.prepareWidgetRefresh() else {
            logger.notice("Skipped widget refresh without a valid signed-in session")
            return .failed
        }

        guard !Task.isCancelled else {
            logger.notice("Widget refresh was cancelled while preparing its session")
            return .failed
        }

        #if os(iOS) || os(macOS) || os(visionOS)
        resume()
        #endif

        let result = await WidgetRefreshCoordinator.shared.refresh(using: OperatorClient.shared)

        guard !Task.isCancelled else {
            logger.notice("Widget refresh was cancelled before completion")
            return .failed
        }

        if result == .failed {
            logger.error("Widget refresh failed")
        }
        return result
    }

    public static func stop() async {
        #if canImport(BackgroundTasks) && (os(iOS) || os(visionOS))
        isSchedulingEnabled = false
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        logger.debug("Stopped widget background refresh scheduling")
        #elseif os(macOS)
        isSchedulingEnabled = false
        macScheduler?.invalidate()
        macScheduler = nil
        logger.debug("Stopped macOS widget background refresh scheduling")
        #endif

        await WidgetRefreshCoordinator.shared.cancelActiveRefresh()
    }

    public static func stopAndClear() async {
        await stop()
        await WidgetRefreshCoordinator.shared.clear()
    }
}

#if canImport(BackgroundTasks) && (os(iOS) || os(visionOS))
import BackgroundTasks

extension WidgetRefreshScheduler {
    private static var hasRegistered = false
    private static var isSchedulingEnabled = false

    public static func register() {
        guard !hasRegistered else {
            logger.debug("Widget background refresh task is already registered")
            return
        }

        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                logger.error("Received unexpected background task type for widget refresh")
                task.setTaskCompleted(success: false)
                schedule()
                return
            }
            handle(refreshTask)
        }

        guard registered else {
            logger.error("Failed to register widget background refresh task")
            return
        }

        hasRegistered = true
        logger.debug("Registered widget background refresh task")
        if isSchedulingEnabled {
            schedule()
        }
    }

    public static func resume() {
        guard hasRegistered else {
            logger.error("Cannot resume widget background refresh before registration")
            return
        }
        guard !isSchedulingEnabled else {
            logger.debug("Widget background refresh scheduling is already active")
            return
        }

        isSchedulingEnabled = true
        schedule()
    }

    public static func schedule() {
        guard hasRegistered, isSchedulingEnabled else {
            logger.debug("Skipped widget background refresh scheduling while stopped")
            return
        }

        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        // The system treats this as a discretionary earliest opportunity, not a deadline.
        request.earliestBeginDate = Date.now.addingTimeInterval(refreshInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.debug("Scheduled widget background refresh task")
        } catch {
            logger.error(
                "Failed to schedule widget background refresh task: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        let completion = WidgetBackgroundTaskCompletion(task: task)
        let refreshOperation = Task { @MainActor in
            let result = await refreshNow()
            let completedSuccessfully = !Task.isCancelled && result != .failed
            completion.finish(success: completedSuccessfully)
            schedule()
        }

        task.expirationHandler = {
            logger.notice("Widget background refresh task expired")
            refreshOperation.cancel()
            Task { @MainActor in
                completion.finish(success: false)
            }
        }
    }
}

@MainActor
private final class WidgetBackgroundTaskCompletion {
    private let task: BGAppRefreshTask
    private var hasFinished = false

    init(task: BGAppRefreshTask) {
        self.task = task
    }

    func finish(success: Bool) {
        guard !hasFinished else { return }
        hasFinished = true
        task.setTaskCompleted(success: success)
    }
}
#endif

#if os(macOS)
extension WidgetRefreshScheduler {
    private static var hasRegistered = false
    private static var isSchedulingEnabled = false
    private static var macScheduler: NSBackgroundActivityScheduler?

    public static func register() {
        guard !hasRegistered else {
            logger.debug("macOS widget background refresh activity is already registered")
            return
        }

        hasRegistered = true
        if isSchedulingEnabled {
            schedule()
        }
    }

    public static func resume() {
        guard hasRegistered else {
            logger.error("Cannot resume macOS widget background refresh before registration")
            return
        }
        guard !isSchedulingEnabled else {
            logger.debug("macOS widget background refresh scheduling is already active")
            return
        }

        isSchedulingEnabled = true
        schedule()
    }

    private static func schedule() {
        let scheduler = NSBackgroundActivityScheduler(identifier: taskIdentifier)
        // macOS schedules this discretionary activity approximately every 15 minutes.
        scheduler.interval = refreshInterval
        scheduler.tolerance = refreshInterval / 3
        scheduler.repeats = true
        scheduler.qualityOfService = .utility
        scheduler.schedule { completion in
            Task { @MainActor in
                guard isSchedulingEnabled else {
                    completion(.deferred)
                    return
                }

                let result = await refreshNow()
                completion(result == .failed ? .deferred : .finished)
            }
        }
        macScheduler = scheduler
        logger.debug("Registered and scheduled macOS widget background refresh activity")
    }
}
#endif
