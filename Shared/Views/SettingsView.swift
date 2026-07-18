//
//  SettingsView.swift
//  TelephoneBoothOperatorMobile
//
//  Editable server URL + sign-out action. Presented as a sheet from the
//  LoginView (when no session) and the watch, and as a Settings tab inside
//  the signed-in shell on iOS / iPadOS / visionOS / tvOS. macOS uses the
//  native ⌘, window (`MacSettingsView`) which composes the same building
//  blocks (`ServerURLField`, `OIDCDetailsView`, `NotificationSettingsSection`).
//

import SwiftUI

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthManager.shared
    @State private var config = AppConfig.shared
    @State private var notifications = NotificationManager.shared

    private let isModal: Bool

    /// - Parameter isModal: `true` when shown as a sheet (adds a "Done"
    ///   button). Pass `false` when embedded as a tab so the chrome stays
    ///   native to the host shell.
    public init(isModal: Bool = true) {
        self.isModal = isModal
    }

    #if os(iOS) || os(tvOS)
    private var themeModes: [Theme.IOSThemeMode] {
        #if os(tvOS)
        Theme.IOSThemeMode.tvSelectableCases
        #else
        Theme.IOSThemeMode.allCases
        #endif
    }

    private var themeFooter: String {
        #if os(tvOS)
        return "Choose the booth palette in light, dark, or automatic mode."
        #else
        return "Choose Catppuccin or the system palette, with light, dark, or automatic mode."
        #endif
    }
    #endif

    #if os(tvOS)
    private func idleLabel(_ seconds: Int) -> String {
        seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) sec"
    }
    #endif

    public var body: some View {
        NavigationStack {
            Form {
                if config.isDemoMode {
                    Section {
                        Button {
                            config.disableDemoMode()
                            dismiss()
                        } label: {
                            Label("Exit Demo Mode", systemImage: "sparkles")
                        }
                    } footer: {
                        Text("Demo mode uses bundled sample data and never contacts the operator API.")
                    }
                    .themedSettingsRowBackground()
                }

                #if os(iOS) || os(tvOS)
                Section {
                    Picker("Theme", selection: $config.iosThemeMode) {
                        ForEach(themeModes) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .accessibilityLabel("Theme selection")
                } header: {
                    Text("Appearance")
                } footer: {
                    Text(themeFooter)
                }
                .themedSettingsRowBackground()
                #endif

                #if os(tvOS)
                Section {
                    Toggle("Ambient screensaver", isOn: $config.tvScreensaverEnabled)
                    if config.tvScreensaverEnabled {
                        Picker("Start after", selection: $config.tvScreensaverIdleSeconds) {
                            ForEach(AppConfig.tvScreensaverIdleOptions, id: \.self) { seconds in
                                Text(idleLabel(seconds)).tag(seconds)
                            }
                        }
                    }
                } header: {
                    Text("Screensaver")
                } footer: {
                    Text("Replaces the tvOS system screensaver with a burn-in-safe wall that " +
                         "spotlights live booth stats. The system screensaver stays disabled " +
                         "while the dashboard is on screen.")
                }
                .themedSettingsRowBackground()
                #endif

                Section {
                    ServerURLField()
                } header: {
                    Text("Operator API")
                } footer: {
                    Text("Point at a staging or self-hosted operator instance. " +
                         "Include the scheme (https://) but no trailing slash.")
                }
                .themedSettingsRowBackground()

                Section {
                    #if os(watchOS) || os(tvOS)
                    OIDCDetailsView()
                    #else
                    DisclosureGroup {
                        OIDCDetailsView()
                    } label: {
                        Label("OIDC details", systemImage: "lock.shield")
                    }
                    #endif
                } header: {
                    Text("Authentication")
                } footer: {
                    Text("OIDC settings come from the build's Info.plist and " +
                         "are not editable at runtime.")
                }
                .themedSettingsRowBackground()

                if auth.isSignedIn {
                    #if !os(tvOS)
                    NotificationSettingsSection(notifications: notifications)
                        .themedSettingsRowBackground()
                    #endif
                    Section {
                        Button(role: .destructive) {
                            auth.signOut()
                            dismiss()
                        } label: {
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                    .themedSettingsRowBackground()
                }
            }
            .themedSettingsFormBackground()
            .navigationTitle("Settings")
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 480, idealWidth: 540)
            #endif
            #if !os(tvOS)
            .toolbar {
                if isModal {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            #endif
            .task {
                await notifications.refreshAuthorizationStatus()
            }
        }
    }
}

/// Editable Operator API base-URL row plus its Save button, inline
/// validation feedback, and the "server changed" sign-out alert. Embedded
/// inside a `Form` `Section` by both `SettingsView` and `MacSettingsView`.
public struct ServerURLField: View {
    @Environment(\.dismiss) private var dismiss
    @State private var config = AppConfig.shared
    @State private var apiBaseString: String
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var showHostChangeAlert = false

    public init() {
        _apiBaseString = State(initialValue: AppConfig.shared.apiBaseURL.absoluteString)
    }

    public var body: some View {
        Group {
            TextField("https://operator.example.com", text: $apiBaseString)
                #if os(iOS) || os(visionOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                #endif
            Button("Save server URL", action: save)
                .disabled(apiBaseString == config.apiBaseURL.absoluteString)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.error)
                    .font(Theme.Fonts.bodySmall)
            } else if let savedMessage {
                Label(savedMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.success)
                    .font(Theme.Fonts.bodySmall)
            }
        }
        .alert("Server Changed", isPresented: $showHostChangeAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("You have been signed out because the API server changed. " +
                 "Please sign in again to continue.")
        }
    }

    private func save() {
        errorMessage = nil
        savedMessage = nil
        do {
            let hostChanged = try config.setAPIBase(apiBaseString)
            apiBaseString = config.apiBaseURL.absoluteString
            if hostChanged {
                showHostChangeAlert = true
            } else {
                savedMessage = "Saved"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Read-only OIDC build settings (issuer, client ID, redirect). Text is
/// selectable everywhere except tvOS, which has no text-selection support.
public struct OIDCDetailsView: View {
    @State private var config = AppConfig.shared

    public init() {}

    public var body: some View {
        Group {
            detailRow("OIDC issuer", config.oidcIssuerBase)
            detailRow("Client ID", config.oidcClientID)
            detailRow("Redirect", config.redirectURI)
        }
        .font(Theme.Fonts.bodySmall)
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        #if os(tvOS) || os(watchOS)
        LabeledContent(label, value: value)
        #else
        LabeledContent(label) {
            Text(value)
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        #endif
    }
}

#Preview {
    SettingsView()
}

private extension View {
    @ViewBuilder
    func themedSettingsFormBackground() -> some View {
        #if os(iOS)
        self
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
        #else
        self
        #endif
    }

    @ViewBuilder
    func themedSettingsRowBackground() -> some View {
        #if os(iOS)
        self.listRowBackground(Theme.Colors.secondaryBackground)
        #else
        self
        #endif
    }
}
