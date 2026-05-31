//
//  RootContainerView.swift
//  TelephoneBoothOperatorMobile
//
//  Dispatches between the login screen and the signed-in dashboard,
//  validates the cached session on launch, and offers Settings access
//  from the toolbar.
//

import SwiftUI

public struct RootContainerView: View {
    @State private var auth = AuthManager.shared
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        Group {
            switch auth.authState {
            case .unknown:
                ProgressView("Connecting to the booth…")
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.background)
            case .signedOut:
                LoginView()
            case .signedIn:
                SignedInRootView()
            }
        }
        .task {
            await AuthManager.shared.validateSessionOnLaunch()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Pre-warm the access token whenever the app comes to the
            // foreground so the first user-driven request after a long
            // sleep doesn't pay the refresh latency (and so we surface
            // expired refresh tokens before the user taps anything).
            guard newPhase == .active else { return }
            Task { @MainActor in
                _ = await AuthManager.shared.ensureValidToken()
            }
        }
    }
}

#Preview {
    RootContainerView()
}
