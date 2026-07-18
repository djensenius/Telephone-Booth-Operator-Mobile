//
//  RootContainerView.swift
//  TelephoneBoothOperatorMobile
//
//  Dispatches between the login screen and the signed-in dashboard,
//  validates the cached session on launch, and offers Settings access
//  from the toolbar.
//

import SwiftUI

/// Reads ephemeral launch arguments used by the screenshot/UI-automation
/// tooling. These are only ever passed by `scripts/` during App Store
/// screenshot capture; in normal launches every value is absent, so
/// production behaviour is unchanged.
public enum LaunchEnv {
    private static let args = ProcessInfo.processInfo.arguments

    /// `-uiTestDemoMode YES` forces the login-free demo experience so App
    /// Review (and automated capture) can reach the UI without the private
    /// OIDC login.
    public static var isScreenshotDemo: Bool {
        value(for: "-uiTestDemoMode").map { ($0 as NSString).boolValue } ?? false
    }

    /// `-uiScreenshotTab <id>` selects the initial tab so each screen can be
    /// captured by relaunching the app.
    public static var screenshotTab: String? {
        value(for: "-uiScreenshotTab")
    }

    /// `-uiScreensaverPreview YES` forces the tvOS ambient screensaver to show
    /// immediately (the headless simulator can't inject remote idle), so it can
    /// be captured during screenshot automation.
    public static var screensaverPreview: Bool {
        value(for: "-uiScreensaverPreview").map { ($0 as NSString).boolValue } ?? false
    }

    private static func value(for flag: String) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}

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
        #if os(iOS) || os(tvOS)
        .preferredColorScheme(config.iosThemeMode.preferredColorScheme)
        #endif
        #if os(iOS)
        // Force a full rebuild on theme change so UIKit-backed appearance
        // refreshes. Not applied on tvOS: there it would recreate the signed-in
        // shell and eject the user back to the Dashboard tab (and dismiss the
        // login sheet). tvOS only switches light/dark, which the dynamic theme
        // colors already pick up via `preferredColorScheme`.
        .id(config.iosThemeMode)
        #endif
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
        demoMode || config.isDemoMode || LaunchEnv.isScreenshotDemo
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
