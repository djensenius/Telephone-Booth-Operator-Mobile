//
//  SettingsView.swift
//  TelephoneBoothOperatorMobile
//
//  Editable server URL + sign-out action. Surfaced from the LoginView
//  (when no session) and from the dashboard toolbar (when signed in).
//

import SwiftUI

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthManager.shared
    @State private var config = AppConfig.shared
    @State private var notifications = NotificationManager.shared

    @State private var apiBaseString: String
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var showHostChangeAlert = false

    public init() {
        _apiBaseString = State(initialValue: AppConfig.shared.apiBaseURL.absoluteString)
    }

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
                }

                Section {
                    TextField("https://operator.example.com", text: $apiBaseString)
                        #if os(iOS) || os(visionOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        #endif
                    Button("Save server URL", action: saveAPIBase)
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
                } header: {
                    Text("Operator API")
                } footer: {
                    Text("Point at a staging or self-hosted operator instance. " +
                         "Include the scheme (https://) but no trailing slash.")
                }

                Section {
                    #if os(watchOS) || os(tvOS)
                    oidcDetails
                    #else
                    DisclosureGroup {
                        oidcDetails
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

                if auth.isSignedIn {
                    #if !os(tvOS)
                    NotificationSettingsSection(notifications: notifications)
                    #endif
                    Section {
                        Button(role: .destructive) {
                            auth.signOut()
                            dismiss()
                        } label: {
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 480, idealWidth: 540)
            #endif
            #if !os(tvOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
            .task {
                await notifications.refreshAuthorizationStatus()
            }
            .alert("Server Changed", isPresented: $showHostChangeAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("You have been signed out because the API server changed. " +
                     "Please sign in again to continue.")
            }
        }
    }

    @ViewBuilder
    private var oidcDetails: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            LabeledContent("OIDC issuer") {
                Text(config.oidcIssuerBase)
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(Theme.Fonts.bodySmall)
            LabeledContent("Client ID") {
                Text(config.oidcClientID)
                    .textSelection(.enabled)
            }
            .font(Theme.Fonts.bodySmall)
            LabeledContent("Redirect") {
                Text(config.redirectURI)
                    .textSelection(.enabled)
            }
            .font(Theme.Fonts.bodySmall)
        }
        #else
        LabeledContent("OIDC issuer", value: config.oidcIssuerBase)
            .font(Theme.Fonts.bodySmall)
        LabeledContent("Client ID", value: config.oidcClientID)
            .font(Theme.Fonts.bodySmall)
        LabeledContent("Redirect", value: config.redirectURI)
            .font(Theme.Fonts.bodySmall)
        #endif
    }

    private func saveAPIBase() {
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

#Preview {
    SettingsView()
}
