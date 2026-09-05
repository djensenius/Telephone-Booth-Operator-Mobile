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
        #if os(tvOS)
        // tvOS has its own full-screen, focus-driven sign-in experience;
        // the shared login chrome (badge, marketing copy, full-width demo
        // button) doesn't translate to a 10-foot screen.
        TVDeviceLoginView()
        #elseif os(watchOS)
        WatchLoginView()
        #else
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
        #endif
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
        #else
        oidcSignInButton
        #endif
    }

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

    #if os(watchOS)
    struct WatchLoginView: View {
        @State private var sync = WatchAuthSync.shared
        @State private var showingSettings = false
        @Environment(\.scenePhase) private var scenePhase

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 12) {
                        Image(systemName: "iphone.and.arrow.forward")
                            .font(.title2)
                            .foregroundStyle(Theme.Colors.accent)
                        Text("Use your iPhone")
                            .font(.headline)
                        Button {
                            Task { await sync.connectFromLogin(automatically: false) }
                        } label: {
                            if sync.isConnecting {
                                ProgressView("Connecting")
                            } else {
                                Text("Connect to iPhone")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.Colors.accent)
                        .disabled(sync.isConnecting)
                        .accessibilityIdentifier("watchConnectToPhone")

                        if let message = sync.statusMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.warning)
                                .accessibilityIdentifier("watchSignInStatus")
                        } else {
                            Text("Sign in to Operator on your paired iPhone. "
                                 + "Your watch connects without another password.")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Text("Keep your iPhone nearby to renew your session. "
                             + "The watch uses its own internet connection to load the booth.")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Button("Try Demo Mode") { AppConfig.shared.enableDemoMode() }
                            .disabled(sync.isConnecting)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                }
                .navigationTitle("Operator")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gear")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .task { await sync.connectFromLogin(automatically: true) }
            .onChange(of: sync.connectionRevision) {
                guard scenePhase == .active else { return }
                Task { await sync.connectFromLogin(automatically: true) }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await sync.connectFromLogin(automatically: true) }
            }
        }
    }
    #endif

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
