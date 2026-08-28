//
//  MessageNotificationAggregation.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

enum MessageNotificationAggregation {
    static func count(userInfo: [AnyHashable: Any]) -> Int? {
        for key in ["awaitingModeration", "awaiting_moderation"] {
            if let count = intValue(userInfo[key]) { return count }
        }
        let aps = userInfo["aps"] as? [AnyHashable: Any]
        return intValue(aps?["badge"])
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        return (value as? NSNumber)?.intValue
    }
}
