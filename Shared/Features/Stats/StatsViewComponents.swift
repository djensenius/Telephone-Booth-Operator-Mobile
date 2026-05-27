//
//  StatsViewComponents.swift
//  TelephoneBoothOperatorMobile
//
//  Small reusable SwiftUI primitives for the stats screen — tiles, bar
//  rows, and digit cells. Extracted from StatsView.swift so the main
//  file stays under the file-length lint threshold.
//

import SwiftUI

struct StatsSummaryTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(Theme.Fonts.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Fonts.bodyLarge.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Theme.Colors.elevatedBackground.opacity(0.7))
        )
    }
}

struct StatsBarRow: View {
    let label: String
    let value: Int
    let max: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Text(label)
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: 160, alignment: .leading)
                .lineLimit(1)
            StatsBarTrack(value: value, max: max)
            Text("\(value)")
                .font(Theme.Fonts.bodySmall.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
        }
    }
}

struct StatsBarTrack: View {
    let value: Int
    let max: Int

    var body: some View {
        GeometryReader { proxy in
            let ratio = max > 0 ? Double(value) / Double(max) : 0
            let width = Swift.max(2, proxy.size.width * ratio)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.Colors.accent.opacity(0.15))
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.Colors.accent)
                    .frame(width: width)
            }
        }
        .frame(height: 6)
    }
}

struct StatsDigitTile: View {
    let digit: String
    let count: Int
    let max: Int

    var body: some View {
        let intensity = max > 0 ? Double(count) / Double(max) : 0
        VStack(spacing: 2) {
            Text(digit)
                .font(Theme.Fonts.bodyMedium.weight(.bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("\(count)")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Theme.Colors.accent.opacity(0.15 + intensity * 0.55))
        )
    }
}

// MARK: - Section cards

struct StatsTopQuestionsCard: View {
    let overview: StatsOverview

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(text: "Top questions")
            if overview.topQuestions.isEmpty {
                Text("No question responses in this window.")
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                content
            }
        }
        .padding(Theme.Spacing.large)
        .frame(maxWidth: .infinity)
        .glassCardBackground()
    }

    private var content: some View {
        let max = overview.topQuestions.map(\.messageCount).max() ?? 0
        return ForEach(Array(overview.topQuestions.enumerated()), id: \.element.id) { index, question in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(index + 1).")
                        .font(Theme.Fonts.bodySmall.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(question.prompt)
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                    if question.retiredAt != nil {
                        Text("(retired)")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    Text(StatsFormat.numberFormatter.string(from: NSNumber(value: question.messageCount)) ?? "0")
                        .font(Theme.Fonts.bodyMedium.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .monospacedDigit()
                }
                StatsBarTrack(value: question.messageCount, max: max)
            }
        }
    }
}

struct StatsBoothBreakdownCard: View {
    let overview: StatsOverview

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(text: "By booth")
            Text("Only shown when more than one booth has activity in this window.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            ForEach(overview.boothBreakdown) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.boothId)
                            .font(Theme.Fonts.bodyMedium.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Text("\(entry.calls) calls")
                            .font(Theme.Fonts.bodySmall)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .monospacedDigit()
                    }
                    Text("Last seen \(StatsFormat.timeAgoString(entry.lastSeenAt))")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .padding(Theme.Spacing.large)
        .frame(maxWidth: .infinity)
        .glassCardBackground()
    }
}

// MARK: - Format helpers

enum StatsFormat {
    static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    static func percentString(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f%%", value * 100)
    }

    static func durationString(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        let seconds = Int((value / 1000).rounded())
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(minutes)m \(remainder)s"
    }

    static func timeAgoString(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let delta = max(0, Int(Date().timeIntervalSince(date)))
        if delta < 60 { return "\(delta)s ago" }
        let minutes = delta / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    static func formatHour(_ hour: Int) -> String {
        let isAM = hour < 12
        let display = hour % 12 == 0 ? 12 : hour % 12
        return "\(display) \(isAM ? "AM" : "PM") UTC"
    }

    static func shortDateLabel(_ isoDay: String) -> String {
        let parts = isoDay.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else {
            return isoDay
        }
        return "\(month)/\(day)"
    }
}
