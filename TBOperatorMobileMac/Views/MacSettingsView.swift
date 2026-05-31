//
//  MacSettingsView.swift
//  TBOperatorMobileMac
//
//  Native macOS Settings window (⌘,). A standard preferences `TabView`
//  with toolbar-style tab panes — General, Authentication, Notifications —
//  instead of the iOS sheet. Each pane composes the same shared building
//  blocks used by `SettingsView` (`ServerURLField`, `OIDCDetailsView`,
//  `NotificationSettingsSection`) so behaviour never drifts.
//

import SwiftUI

struct MacSettingsView: View {
    private enum Pane: Hashable {
        case general, authentication, notifications
    }

    @State private var selection: Pane = .general

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Pane.general)

            AuthenticationSettingsPane()
                .tabItem { Label("Authentication", systemImage: "lock.shield") }
                .tag(Pane.authentication)

            NotificationsSettingsPane()
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
                .tag(Pane.notifications)
        }
        .frame(width: 520, height: 420)
    }
}

private struct GeneralSettingsPane: View {
    @State private var config = AppConfig.shared

    var body: some View {
        Form {
            if config.isDemoMode {
                Section {
                    Button {
                        config.disableDemoMode()
                    } label: {
                        Label("Exit Demo Mode", systemImage: "sparkles")
                    }
                } footer: {
                    Text("Demo mode uses bundled sample data and never contacts the operator API.")
                }
            }

            Section {
                ServerURLField()
            } header: {
                Text("Operator API")
            } footer: {
                Text("Point at a staging or self-hosted operator instance. " +
                     "Include the scheme (https://) but no trailing slash.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct AuthenticationSettingsPane: View {
    @State private var auth = AuthManager.shared

    var body: some View {
        Form {
            Section {
                OIDCDetailsView()
            } header: {
                Text("OIDC")
            } footer: {
                Text("OIDC settings come from the build's Info.plist and " +
                     "are not editable at runtime.")
            }

            if auth.isSignedIn {
                Section {
                    Button(role: .destructive) {
                        auth.signOut()
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } footer: {
                    Text("Signing out clears the cached tokens from the Keychain.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct NotificationsSettingsPane: View {
    @State private var auth = AuthManager.shared
    @State private var notifications = NotificationManager.shared

    var body: some View {
        Form {
            if auth.isSignedIn {
                NotificationSettingsSection(notifications: notifications)
            } else {
                Section {
                    Text("Sign in to manage push notifications for this Mac.")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task {
            await notifications.refreshAuthorizationStatus()
        }
    }
}

#Preview {
    MacSettingsView()
}
