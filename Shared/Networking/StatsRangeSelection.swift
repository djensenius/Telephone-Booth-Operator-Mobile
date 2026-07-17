//
//  StatsRangeSelection.swift
//  TelephoneBoothOperatorMobile
//
//  Describes what time span the Stats screen is showing. Either a preset
//  window (24h/7d/30d/all) mapped straight onto `?window=`, or a custom
//  range mapped onto `?start=&end=`, where the end can be pinned to "now".
//

import Foundation

public enum StatsRangeSelection: Sendable, Hashable {
    case window(StatsWindow)
    /// A custom range. `endIsNow` pins the upper bound to the current time
    /// (sent as `end=now`); otherwise `end` supplies the explicit upper bound.
    case custom(start: Date?, endIsNow: Bool, end: Date?)

    public static let `default` = StatsRangeSelection.window(.last7d)

    /// Query items for `GET /v1/stats/overview`.
    public var queryItems: [URLQueryItem] {
        switch self {
        case .window(let window):
            return [URLQueryItem(name: "window", value: window.rawValue)]
        case .custom(let start, let endIsNow, let end):
            var items: [URLQueryItem] = []
            if let start {
                items.append(
                    URLQueryItem(name: "start", value: OperatorJSON.iso8601String(from: start))
                )
            }
            if endIsNow {
                items.append(URLQueryItem(name: "end", value: "now"))
            } else if let end {
                items.append(
                    URLQueryItem(name: "end", value: OperatorJSON.iso8601String(from: end))
                )
            }
            return items
        }
    }

    /// A short human label for the current selection.
    public var displayName: String {
        switch self {
        case .window(let window):
            return window.displayName
        case .custom:
            return "Custom range"
        }
    }

    public var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }
}
