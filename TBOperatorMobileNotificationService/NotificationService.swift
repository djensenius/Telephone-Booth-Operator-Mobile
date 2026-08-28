//
//  NotificationService.swift
//  TelephoneBoothOperatorMobile
//

@preconcurrency import UserNotifications

final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    private let stateLock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }

        stateLock.withLock {
            self.contentHandler = contentHandler
            bestAttemptContent = content
        }

        guard MessageNotificationAggregation.isQueueNotification(userInfo: content.userInfo),
              let count = MessageNotificationAggregation.count(userInfo: content.userInfo) else {
            finish(with: content)
            return
        }

        content.title = MessageNotificationAggregation.title(count: count)
        content.body = MessageNotificationAggregation.body(count: count)
        content.badge = NSNumber(value: max(0, count))

        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { [self] notifications in
            let identifiers = notifications.compactMap { notification in
                MessageNotificationAggregation.isQueueNotification(
                    userInfo: notification.request.content.userInfo
                ) ? notification.request.identifier : nil
            }
            if !identifiers.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: identifiers)
            }
            finish(with: content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        let content = stateLock.withLock { bestAttemptContent }
        if let content {
            finish(with: content)
        }
    }

    private func finish(with content: UNNotificationContent) {
        let handler = stateLock.withLock {
            let handler = contentHandler
            contentHandler = nil
            bestAttemptContent = nil
            return handler
        }
        handler?(content)
    }
}
