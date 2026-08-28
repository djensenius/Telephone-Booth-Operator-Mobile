//
//  MessageNotificationAggregation.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

enum MessageNotificationAggregation {
    static let notificationKind = "messageQueue"

    static func isQueueNotification(userInfo: [AnyHashable: Any]) -> Bool {
        userInfo["notificationKind"] as? String == notificationKind
    }

    static func count(userInfo: [AnyHashable: Any]) -> Int? {
        for key in ["awaitingModeration", "awaiting_moderation"] {
            if let count = userInfo[key] as? Int {
                return count
            }
            if let count = userInfo[key] as? NSNumber {
                return count.intValue
            }
        }
        return nil
    }

    static func title(count: Int) -> String {
        count == 1 ? "1 message waiting" : "\(count) messages waiting"
    }

    static func body(count: Int) -> String {
        count == 1
            ? "A new booth recording is ready to moderate."
            : "Booth recordings are ready to moderate."
    }
}
