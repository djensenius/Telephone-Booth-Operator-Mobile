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
    @State private var config = AppConfig.shared
    @Environment(\.scenePhase) private var scenePhase
    private let demoMode: Bool

    public init(demoMode: Bool = false) {
        self.demoMode = demoMode
    }

    public var body: some View {
        Group {
            if effectiveDemoMode {
                SignedInRootView(client: .demo, eventStream: .demo)
            } else {
                liveRoot
            }
        }
        .task {
            guard !effectiveDemoMode else { return }
            await AuthManager.shared.validateSessionOnLaunch()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard !effectiveDemoMode else { return }
            guard newPhase == .active else { return }
            Task { @MainActor in
                _ = await AuthManager.shared.ensureValidToken()
                await PendingMessagesStore.shared.refresh(using: .shared)
            }
        }
        .onChange(of: auth.authState) { _, newState in
            guard newState == .signedOut else { return }
            PendingMessagesStore.shared.stopPolling()
        }
    }

    private var effectiveDemoMode: Bool {
        demoMode || config.isDemoMode
    }

    @ViewBuilder
    private var liveRoot: some View {
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
}

#Preview {
    RootContainerView(demoMode: true)
}
