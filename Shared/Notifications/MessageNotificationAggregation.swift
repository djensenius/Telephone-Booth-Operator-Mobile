//
//  MessageNotificationAggregation.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

enum MessageNotificationAggregation {
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
}
