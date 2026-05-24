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

    @State private var apiBaseString: String
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    public init() {
        _apiBaseString = State(initialValue: AppConfig.shared.apiBaseURL.absoluteString)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://operator.example.com", text: $apiBaseString)
                        .textFieldStyle(.automatic)
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
                    LabeledContent("OIDC issuer", value: config.oidcIssuerBase)
                        .font(Theme.Fonts.bodySmall)
                    LabeledContent("Client ID", value: config.oidcClientID)
                        .font(Theme.Fonts.bodySmall)
                    LabeledContent("Redirect", value: config.redirectURI)
                        .font(Theme.Fonts.bodySmall)
                } header: {
                    Text("Authentication")
                } footer: {
                    Text("OIDC settings come from the build's Info.plist and " +
                         "are not editable at runtime.")
                }

                if auth.isSignedIn {
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
            #if !os(tvOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
        }
    }

    private func saveAPIBase() {
        errorMessage = nil
        savedMessage = nil
        do {
            try config.setAPIBase(apiBaseString)
            apiBaseString = config.apiBaseURL.absoluteString
            savedMessage = "Saved"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SettingsView()
}
