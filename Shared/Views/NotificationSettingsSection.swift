//
//  NotificationSettingsSection.swift
//  TelephoneBoothOperatorMobile
//
//  Settings UI block for APNs permission + per-event toggles. tvOS is
//  excluded by the parent because remote-notification UX doesn't fit the
//  big-screen / focus-remote idiom.
//

import SwiftUI

#if !os(tvOS)
public struct NotificationSettingsSection: View {
    @Bindable var notifications: NotificationManager

    public init(notifications: NotificationManager) {
        self.notifications = notifications
    }

    public var body: some View {
        Section {
            switch notifications.authorizationState {
            case .notDetermined, .unknown:
                Button("Enable push notifications", action: requestEnable)
                    .disabled(notifications.isWorking)
            case .denied:
                Label(
                    "Notifications are turned off in System Settings.",
                    systemImage: "bell.slash.fill"
                )
                .foregroundStyle(Theme.Colors.warning)
                .font(Theme.Fonts.bodySmall)
            case .authorized, .provisional:
                eventToggles
                if notifications.deviceId != nil {
                    Button(role: .destructive) {
                        Task { await notifications.disableNotifications() }
                    } label: {
                        Label("Stop sending notifications to this device",
                              systemImage: "bell.slash")
                    }
                    .disabled(notifications.isWorking)
                } else if notifications.apnsToken == nil {
                    Label("Waiting for the system to issue an APNs token…",
                          systemImage: "hourglass")
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .font(Theme.Fonts.bodySmall)
                }
            }
            if let error = notifications.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.error)
                    .font(Theme.Fonts.bodySmall)
            }
        } header: {
            Text("Push notifications")
        } footer: {
            Text(
                "The operator's API server fans out APNs alerts when notable " +
                "events happen at the booth. Toggles below tune the categories " +
                "this device should receive."
            )
        }
    }

    @ViewBuilder
    private var eventToggles: some View {
        Toggle("Call started", isOn: binding(\.callStarted))
            .disabled(notifications.isWorking)
        Toggle("New message received", isOn: binding(\.messageReceived))
            .disabled(notifications.isWorking)
        Toggle("Message flagged by moderation", isOn: binding(\.messageFlagged))
            .disabled(notifications.isWorking)
        Toggle("Moderation queue high", isOn: binding(\.moderationQueueHigh))
            .disabled(notifications.isWorking)
    }

    private func binding(_ keyPath: WritableKeyPath<MobileDevicePreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { notifications.preferences[keyPath: keyPath] },
            set: { value in
                Task { await notifications.updatePreference(keyPath, to: value) }
            }
        )
    }

    private func requestEnable() {
        Task { await notifications.requestAuthorizationAndRegister() }
    }
}
#endif
