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
    }
}

#Preview {
    RootContainerView()
}
