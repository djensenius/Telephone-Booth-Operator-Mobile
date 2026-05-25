//
//  CallInProgressLiveActivity.swift
//  TBOperatorMobileWidgets
//
//  Live Activity UI for an active phone call at the booth. Renders on
//  the Lock Screen, Dynamic Island (compact + expanded), and StandBy.
//

#if canImport(ActivityKit) && !os(macOS)
import ActivityKit
import SwiftUI
import WidgetKit

struct CallInProgressLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CallInProgressAttributes.self) { context in
            lockScreenView(context: context)
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
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.stateDisplayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let digits = context.state.digitsDialed {
                            Text(digits)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Link(destination: approveURL(sessionId: context.attributes.sessionId)) {
                            Label("Approve", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
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
            } minimal: {
                Image(systemName: "phone.fill")
                    .foregroundStyle(.green)
            }
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
            }
            Spacer()
            Text(context.state.startedAt, style: .timer)
                .font(.title3.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding()
        .activityBackgroundTint(.black.opacity(0.7))
    }

    private func approveURL(sessionId: String) -> URL {
        let allowedPathCharacters = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))

        guard let encodedSessionId = sessionId.addingPercentEncoding(withAllowedCharacters: allowedPathCharacters),
              let url = URL(string: "tboperator://call/\(encodedSessionId)/approve") else {
            // swiftlint:disable:next force_unwrapping
            return URL(string: "tboperator://dashboard")!
        }

        return url
    }
}
#endif
