//
//  CallInProgressLiveActivity.swift
//  TBOperatorMobileWidgets
//
//  Live Activity UI for an active phone call at the booth. Renders on
//  the Lock Screen, Dynamic Island (compact + expanded), and StandBy.
//  iOS-only — Live Activities are not offered on macOS or visionOS in
//  this app. The single action is a read-only "View call" deep link;
//  moderation is never performed from a Live Activity.
//

#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

struct CallInProgressLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CallInProgressAttributes.self) { context in
            lockScreenView(context: context)
                .widgetURL(WidgetDeepLink.session(id: context.attributes.sessionId))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.boothName, systemImage: "phone.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .privacySensitive()
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.stateDisplayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .privacySensitive()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let digits = context.state.digitsDialed {
                            Text(digits)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .privacySensitive()
                        }
                        Spacer()
                        if let url = WidgetDeepLink.session(id: context.attributes.sessionId) {
                            Link(destination: url) {
                                Label("View call", systemImage: "arrow.up.forward.app")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "phone.fill")
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer)
                    .monospacedDigit()
                    .frame(width: 48)
                    .privacySensitive()
            } minimal: {
                Image(systemName: "phone.fill")
                    .foregroundStyle(.green)
            }
            .widgetURL(WidgetDeepLink.session(id: context.attributes.sessionId))
        }
    }

    @ViewBuilder
    private func lockScreenView(
        context: ActivityViewContext<CallInProgressAttributes>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "phone.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.boothName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(context.state.stateDisplayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            }
            Spacer()
            Text(context.state.startedAt, style: .timer)
                .font(.title3.monospacedDigit())
                .foregroundStyle(.primary)
                .privacySensitive()
        }
        .padding()
        .activityBackgroundTint(.black.opacity(0.7))
    }
}

private let callPreviewAttributes = CallInProgressAttributes(
    boothName: "Bell Canada Booth",
    sessionId: "preview-session"
)

private let callPreviewState = CallInProgressAttributes.ContentState(
    boothState: "connected",
    startedAt: .now.addingTimeInterval(-93),
    digitsDialed: "514 555 0123"
)

#Preview("Call · Lock Screen", as: .content, using: callPreviewAttributes) {
    CallInProgressLiveActivity()
} contentStates: {
    callPreviewState
}

#Preview("Call · Dynamic Island expanded", as: .dynamicIsland(.expanded), using: callPreviewAttributes) {
    CallInProgressLiveActivity()
} contentStates: {
    callPreviewState
}

#Preview("Call · Dynamic Island compact", as: .dynamicIsland(.compact), using: callPreviewAttributes) {
    CallInProgressLiveActivity()
} contentStates: {
    callPreviewState
}

#Preview("Call · Dynamic Island minimal", as: .dynamicIsland(.minimal), using: callPreviewAttributes) {
    CallInProgressLiveActivity()
} contentStates: {
    callPreviewState
}
#endif
