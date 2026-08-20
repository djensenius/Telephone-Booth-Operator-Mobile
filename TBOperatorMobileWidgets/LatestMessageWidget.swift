//
//  LatestMessageWidget.swift
//  TBOperatorMobileWidgets
//
//  Surfaces only the *metadata* of the most recent message: its
//  identifier, moderation status, and received/created time. Transcript
//  text, translations, moderation reasons, notes, and audio never enter
//  the snapshot, so they can never be rendered here. Tapping opens the
//  exact message detail for review.
//

import SwiftUI
import WidgetKit

struct LatestMessageWidget: Widget {
    let kind = "LatestMessageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetSnapshotProvider()) { entry in
            LatestMessageWidgetView(entry: entry)
                .widgetURL(entry.latestMessageState.value.flatMap { WidgetDeepLink.message(id: $0.id) })
        }
        .configurationDisplayName("Latest message")
        .description("Status and time of the most recent message. No transcript is shown.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct LatestMessageWidgetView: View {
    let entry: WidgetSnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetContainerBackground(family)
    }

    @ViewBuilder
    private var content: some View {
        switch entry.latestMessageState {
        case .noSnapshot:
            WidgetUnavailableView(
                title: "Latest message",
                systemImage: "waveform",
                message: "Open the app to load recent messages."
            )
        case .missingSection:
            WidgetUnavailableView(
                title: "Latest message",
                systemImage: "waveform",
                message: "No messages recorded yet."
            )
        case let .current(message, _):
            layout(message, stale: false)
        case let .stale(message, _):
            layout(message, stale: true)
        }
    }

    private func layout(_ message: WidgetSnapshot.LatestMessage, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 10) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                    .widgetAccentable()
                Text("Latest message")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if stale { WidgetStaleBadge() }
            }
            Spacer(minLength: 0)
            statusBadge(message.status)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text("Received")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(message.occurredAt, style: .relative)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .privacySensitive()
            }
            if family != .systemSmall {
                Text("Tap to review — no transcript shown here.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Latest message status \(message.status.displayName)")
    }

    private func statusBadge(_ status: MessageStatus) -> some View {
        HStack(spacing: 8) {
            Image(systemName: status.widgetSymbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(status.widgetTint)
                .widgetAccentable()
            Text(status.displayName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .privacySensitive()
    }
}

private extension MessageStatus {
    var widgetSymbol: String {
        switch self {
        case .uploading: return "icloud.and.arrow.up"
        case .received: return "tray.and.arrow.down.fill"
        case .pending: return "clock.badge.questionmark"
        case .approved: return "checkmark.seal.fill"
        case .rejected: return "xmark.seal.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var widgetTint: Color {
        switch self {
        case .approved: return Theme.Colors.success
        case .rejected: return Theme.Colors.error
        case .pending, .received: return Theme.Colors.warning
        case .uploading: return Theme.Colors.info
        case .unknown: return .secondary
        }
    }
}

#Preview("Latest message · small", as: .systemSmall) {
    LatestMessageWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
    WidgetSnapshotEntry.sample(minutesAgo: 45, treatAsFresh: false)
    WidgetSnapshotEntry.emptySections()
}

#Preview("Latest message · medium", as: .systemMedium) {
    LatestMessageWidget()
} timeline: {
    WidgetSnapshotEntry.sample()
    WidgetSnapshotEntry.noSnapshot()
}
