//
//  LoginView.swift
//  TelephoneBoothOperatorMobile
//
//  Sign-in screen — Catppuccin theme + Liquid Glass treatment where the
//  platform supports it. On tvOS this view shows a paired-device message
//  instead; ASWebAuthenticationSession isn't available there.
//

import SwiftUI

public struct LoginView: View {
    @State private var auth = AuthManager.shared
    @State private var config = AppConfig.shared
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var showingSettings = false

    public init() {}

    public var body: some View {
        ZStack {
            Theme.Colors.background
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.extraLarge) {
                Spacer()

                operatorBadge

                Text("Telephone-Booth Operator")
                    .font(Theme.Fonts.headerXL())
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Sign in to monitor and moderate the booth from your pocket.")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.large)

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Fonts.bodySmall)
                        .foregroundStyle(Theme.Colors.error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.large)
                }

                demoButton
                signInButton

                Spacer()
            }
            .padding(Theme.Spacing.large)
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                settingsButton
            }
            .padding(.horizontal, Theme.Spacing.large)
            .padding(.top, Theme.Spacing.small)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private var operatorBadge: some View {
        Image(systemName: "phone.connection")
            .font(.system(size: 72, weight: .regular))
            .foregroundStyle(Theme.Colors.accent)
            .padding(Theme.Spacing.large)
            .modifier(LiquidGlassCircle())
    }

    private var demoButton: some View {
        Button {
            config.enableDemoMode()
        } label: {
            HStack(spacing: Theme.Spacing.small) {
                Image(systemName: "sparkles")
                Text("Try Demo Mode")
                    .font(Theme.Fonts.bodyMedium.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.medium)
        }
        .tint(Theme.Colors.accent)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, Theme.Spacing.large)
        .accessibilityHint("Open the app with sample data and no login")
    }

    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(Theme.Fonts.bodyMedium)
                .padding(Theme.Spacing.small)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.Colors.textSecondary)
        .accessibilityLabel("Settings")
    }

    @ViewBuilder
    private var signInButton: some View {
        #if os(tvOS)
        TVDeviceLoginView()
        #elseif os(watchOS)
        VStack(spacing: Theme.Spacing.small) {
            iPhoneSignInButton
            oidcSignInButton
        }
        .task {
            // Auto-attempt a handoff from the paired phone on appear.
            _ = await WatchAuthSync.shared.ensureBrokeredToken()
        }
        #else
        oidcSignInButton
        #endif
    }

    #if os(watchOS)
    private var iPhoneSignInButton: some View {
        Button {
            Task { await signInFromPhone() }
        } label: {
            HStack(spacing: Theme.Spacing.small) {
                if isSigningIn {
                    ProgressView()
                } else {
                    Image(systemName: "iphone")
                }
                Text(isSigningIn ? "Connecting…" : "Sign in with iPhone")
                    .font(Theme.Fonts.bodyMedium.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.medium)
        }
        .disabled(isSigningIn)
        .tint(Theme.Colors.accent)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, Theme.Spacing.large)
    }

    private func signInFromPhone() async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        if !(await WatchAuthSync.shared.ensureBrokeredToken()) {
            errorMessage = "Couldn't reach your iPhone. Open the Operator app on your "
                + "iPhone, or sign in on your watch instead."
        }
    }
    #endif

    @ViewBuilder
    private var oidcSignInButton: some View {
        Button {
            Task { await signIn() }
        } label: {
            HStack(spacing: Theme.Spacing.small) {
                if isSigningIn {
                    ProgressView()
                } else {
                    Image(systemName: "person.badge.key")
                }
                Text(isSigningIn ? "Signing in…" : "Sign in")
                    .font(Theme.Fonts.bodyMedium.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.medium)
        }
        .disabled(isSigningIn)
        .tint(Theme.Colors.accent)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, Theme.Spacing.large)
    }

    private func signIn() async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            try await AuthManager.shared.signInWithOIDC()
        } catch AuthError.cancelled {
            // user dismissed — no error shown
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Adds a Liquid Glass circular surround when running on Apple platforms
/// that support `.glassEffect`. Falls back to a tinted circle on older
/// targets (the project pins all targets to 26.0 so the fallback should
/// rarely fire, but the modifier stays graceful).
private struct LiquidGlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(visionOS)
        content
            .background(Circle().fill(Theme.Colors.elevatedBackground))
            .glassBackgroundEffect(in: .circle)
        #else
        content
            .background(Circle().fill(Theme.Colors.elevatedBackground))
        #endif
    }
}

#Preview {
    LoginView()
}
