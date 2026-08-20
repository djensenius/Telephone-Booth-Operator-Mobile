//
//  StatsViewComponents.swift
//  TelephoneBoothOperatorMobile
//
//  Small reusable SwiftUI primitives for the stats screen — tiles, bar
//  rows, and digit cells. Extracted from StatsView.swift so the main
//  file stays under the file-length lint threshold.
//

import SwiftUI

struct StatsSectionColumnsLayout: Layout {
    let spacing: CGFloat = Theme.Spacing.large
    let twoColumnWidth: CGFloat = 900

    struct Arrangement {
        let containerSize: CGSize
        let frames: [CGRect]

        static let empty = Arrangement(containerSize: .zero, frames: [])
    }

    struct Cache {
        var arrangement = Arrangement.empty
    }

    static func usesTwoColumns(
        availableWidth: CGFloat?,
        itemCount: Int,
        twoColumnWidth: CGFloat = 900
    ) -> Bool {
        guard itemCount > 1, let availableWidth, availableWidth.isFinite else { return false }
        return availableWidth >= twoColumnWidth
    }

    static func arrangement(
        for itemSizes: [CGSize],
        availableWidth: CGFloat?,
        spacing: CGFloat = Theme.Spacing.large,
        twoColumnWidth: CGFloat = 900
    ) -> Arrangement {
        guard !itemSizes.isEmpty else { return .empty }

        if usesTwoColumns(
            availableWidth: availableWidth,
            itemCount: itemSizes.count,
            twoColumnWidth: twoColumnWidth
        ), let availableWidth {
            let columnWidth = max(0, (availableWidth - spacing) / 2)
            var frames: [CGRect] = []
            frames.reserveCapacity(itemSizes.count)

            var leftY: CGFloat = 0
            var rightY: CGFloat = 0
            var hasLeftColumn = false
            var hasRightColumn = false

            for (index, size) in itemSizes.enumerated() {
                if index.isMultiple(of: 2) {
                    frames.append(CGRect(x: 0, y: leftY, width: columnWidth, height: size.height))
                    leftY += size.height + spacing
                    hasLeftColumn = true
                } else {
                    frames.append(CGRect(x: columnWidth + spacing, y: rightY, width: columnWidth, height: size.height))
                    rightY += size.height + spacing
                    hasRightColumn = true
                }
            }

            let totalHeight = max(
                hasLeftColumn ? leftY - spacing : 0,
                hasRightColumn ? rightY - spacing : 0
            )
            return Arrangement(
                containerSize: CGSize(width: availableWidth, height: totalHeight),
                frames: frames
            )
        }

        var frames: [CGRect] = []
        frames.reserveCapacity(itemSizes.count)

        var currentY: CGFloat = 0
        var maxMeasuredWidth: CGFloat = 0

        for size in itemSizes {
            let width = availableWidth ?? size.width
            frames.append(CGRect(x: 0, y: currentY, width: width, height: size.height))
            currentY += size.height + spacing
            maxMeasuredWidth = max(maxMeasuredWidth, size.width)
        }

        return Arrangement(
            containerSize: CGSize(
                width: availableWidth ?? maxMeasuredWidth,
                height: max(0, currentY - spacing)
            ),
            frames: frames
        )
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews, proposal: ProposedViewSize) {
        let proposalWidth = sanitizedWidth(proposal.width)
        let childWidth = childWidth(for: proposalWidth, itemCount: subviews.count)
        let childProposal = ProposedViewSize(width: childWidth, height: nil)
        let itemSizes = subviews.map { $0.sizeThatFits(childProposal) }

        cache.arrangement = Self.arrangement(
            for: itemSizes,
            availableWidth: proposalWidth,
            spacing: spacing,
            twoColumnWidth: twoColumnWidth
        )
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        updateCache(&cache, subviews: subviews, proposal: proposal)
        return cache.arrangement.containerSize
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        updateCache(&cache, subviews: subviews, proposal: proposal)

        for (subview, frame) in zip(subviews, cache.arrangement.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func childWidth(for availableWidth: CGFloat?, itemCount: Int) -> CGFloat? {
        guard let availableWidth else { return nil }
        if Self.usesTwoColumns(
            availableWidth: availableWidth,
            itemCount: itemCount,
            twoColumnWidth: twoColumnWidth
        ) {
            return max(0, (availableWidth - spacing) / 2)
        }
        return availableWidth
    }

    private func sanitizedWidth(_ width: CGFloat?) -> CGFloat? {
        guard let width, width.isFinite else { return nil }
        return max(0, width)
    }
}

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
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
            let width = value > 0 ? Swift.max(2, proxy.size.width * ratio) : 0
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
        VStack(spacing: 4) {
            Text(digit)
                .font(Theme.Fonts.bodyMedium.weight(.bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("\(count)")
                .font(Theme.Fonts.bodySmall.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
            StatsBarTrack(value: count, max: max)
                .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 58)
        .padding(.vertical, Theme.Spacing.small)
        .padding(.horizontal, 6)
        .background(
            Theme.Colors.background,
            in: RoundedRectangle(cornerRadius: Theme.cornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.Colors.textPrimary.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Digit \(digit)")
        .accessibilityValue("\(count) \(count == 1 ? "time" : "times") dialed")
    }
}

// MARK: - Section cards

struct StatsSelectionDetailTile: View {
    let title: String
    let selectionLabel: String
    let selectionCount: Int
    let outcomeLabel: String
    let outcomeCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text(title.uppercased())
                .font(Theme.Fonts.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
            StatRow(
                label: selectionLabel,
                value: StatsFormat.numberString(selectionCount)
            )
            StatRow(
                label: outcomeLabel,
                value: StatsFormat.optionalNumberString(outcomeCount)
            )
        }
        .padding(Theme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.Colors.background,
            in: RoundedRectangle(cornerRadius: Theme.cornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.Colors.textPrimary.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

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
                        Text(
                            "\(StatsFormat.numberString(entry.interactionCount)) "
                                + "\(entry.interactionCount == 1 ? "pickup" : "pickups")"
                        )
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

    static func numberString(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? "0"
    }

    static func optionalNumberString(_ value: Int?) -> String {
        guard let value else { return "—" }
        return numberString(value)
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
