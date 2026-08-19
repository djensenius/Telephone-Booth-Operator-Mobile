//
//  DurationFormatting.swift
//  TelephoneBoothOperatorMobile
//
//  Centralised millisecond → "Xm YYs" / "Ys" formatting used by the
//  session list, session detail, and any future view that surfaces
//  call duration.
//

import Foundation

public enum DurationFormatter {
    /// Render a millisecond count as `Xm YYs` (with leading 'm' dropped
    /// for sub-minute durations), or nil when the input is nil or
    /// non-positive (negative / zero / overflow).
    public static func shortString(milliseconds durationMs: Int?) -> String? {
        guard let durationMs, durationMs > 0 else { return nil }
        let totalSeconds = Int((Double(durationMs) / 1000.0).rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        }
        return "\(seconds)s"
    }

    /// Compact elapsed time for live status surfaces, including hours and days.
    public static func compactString(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }
}
