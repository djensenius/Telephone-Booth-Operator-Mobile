//
//  RootContainerView.swift
//  TelephoneBoothOperatorMobile
//
//  Dispatches between the login screen and the signed-in dashboard,
//  validates the cached session on launch, and offers Settings access
//  from the toolbar.
//

import Foundation
import Observation
import os
import SwiftUI

private let navigationLogger = Logger(
    subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
    category: "AppNavigation"
)

/// A destination that can safely be requested by app links and notifications.
public enum AppNavigationTarget: Equatable, Sendable {
    public enum MessageRoute: Equatable, Sendable {
        case list(filter: MessageListFilter)
        case detail(id: String)
    }

    case dashboard
    case stats
    case sessions
    case session(id: String)
    case messages(MessageRoute)
    case thermals
    case system

    public init?(url: URL) {
        guard let parsed = Self.parse(url) else { return nil }
        self = parsed
    }

    public static func parse(_ url: URL) -> AppNavigationTarget? {
        guard let request = DeepLinkRequest(url: url) else { return nil }
        return target(for: request)
    }

    private static func target(for request: DeepLinkRequest) -> AppNavigationTarget? {
        let path = request.path
        let query = request.query

        switch request.host {
        case "dashboard":
            return staticTarget(.dashboard, path: path, query: query)
        case "stats":
            return staticTarget(.stats, path: path, query: query)
        case "sessions":
            return sessionTarget(path: path, query: query)
        case "messages":
            return messageTarget(path: path, query: query)
        case "thermals":
            return staticTarget(.thermals, path: path, query: query)
        case "system":
            return staticTarget(.system, path: path, query: query)
        default:
            return nil
        }
    }

    private static func staticTarget(
        _ target: AppNavigationTarget,
        path: [String],
        query: [String: String]
    ) -> AppNavigationTarget? {
        guard path.isEmpty, query.isEmpty else { return nil }
        return target
    }

    private static func sessionTarget(
        path: [String],
        query: [String: String]
    ) -> AppNavigationTarget? {
        guard query.isEmpty else { return nil }
        if path.isEmpty {
            return .sessions
        }
        guard path.count == 1, DeepLinkIdentifier.isValid(path[0]) else { return nil }
        return .session(id: path[0])
    }

    private static func messageTarget(
        path: [String],
        query: [String: String]
    ) -> AppNavigationTarget? {
        if path.isEmpty {
            guard query.count <= 1 else { return nil }
            guard let value = query["filter"] else {
                return query.isEmpty ? .messages(.list(filter: .all)) : nil
            }
            guard let filter = MessageListFilter(deepLinkValue: value) else { return nil }
            return .messages(.list(filter: filter))
        }
        guard path.count == 1, query.isEmpty, DeepLinkIdentifier.isValid(path[0]) else { return nil }
        return .messages(.detail(id: path[0]))
    }

    private struct DeepLinkRequest {
        let host: String
        let path: [String]
        let query: [String: String]

        init?(url: URL) {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  components.scheme?.lowercased() == "tboperator",
                  components.user == nil,
                  components.password == nil,
                  components.port == nil,
                  components.fragment == nil,
                  let host = components.host?.lowercased(),
                  let path = decodedPathSegments(from: components),
                  let query = decodedQueryItems(from: components) else {
                return nil
            }
            self.host = host
            self.path = path
            self.query = query
        }
    }

    private static func decodedPathSegments(from components: URLComponents) -> [String]? {
        let path = components.percentEncodedPath
        guard !path.isEmpty else { return [] }
        guard path.first == "/" else { return nil }
        let encodedPath = path.dropFirst()
        guard !encodedPath.isEmpty else { return nil }
        let encodedSegments = encodedPath.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !encodedSegments.contains(where: \.isEmpty) else { return nil }
        var decodedSegments: [String] = []
        for segment in encodedSegments {
            guard let decoded = String(segment).removingPercentEncoding else { return nil }
            decodedSegments.append(decoded)
        }
        return decodedSegments
    }

    private static func decodedQueryItems(from components: URLComponents) -> [String: String]? {
        guard let query = components.percentEncodedQuery, !query.isEmpty else { return [:] }
        var values: [String: String] = [:]

        for component in query.split(separator: "&", omittingEmptySubsequences: false) {
            let pair = component.split(
                separator: "=",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            guard pair.count == 2,
                  let name = String(pair[0]).removingPercentEncoding,
                  let value = String(pair[1]).removingPercentEncoding,
                  name == "filter",
                  values[name] == nil else {
                return nil
            }
            values[name] = value
        }
        return values
    }

}

public enum NotificationNavigationTarget: Equatable, Sendable {
    case messages(messageId: String?)
    case reviewQueue
    case session(id: String)

    var appNavigationTarget: AppNavigationTarget {
        switch self {
        case .messages(let messageId):
            if let messageId {
                return .messages(.detail(id: messageId))
            }
            return .messages(.list(filter: .all))
        case .reviewQueue:
            return .messages(.list(filter: .review))
        case .session(let id):
            return .session(id: id)
        }
    }

    init?(appNavigationTarget: AppNavigationTarget) {
        switch appNavigationTarget {
        case .messages(.detail(let id)):
            self = .messages(messageId: id)
        case .messages(.list(let filter)):
            self = filter == .review ? .reviewQueue : .messages(messageId: nil)
        case .session(let id):
            self = .session(id: id)
        default:
            return nil
        }
    }
}

/// Holds at most one navigation request until a signed-in application shell
/// is ready to consume it.
@MainActor
@Observable
public final class AppNavigationStore {
    public static let shared = AppNavigationStore()

    public private(set) var pendingTarget: AppNavigationTarget?
    public private(set) var routeGeneration: UInt = 0

    public init() {}

    @discardableResult
    public func open(_ url: URL) -> Bool {
        guard let target = AppNavigationTarget(url: url) else {
            navigationLogger.warning("Rejected unsupported app navigation URL.")
            return false
        }
        route(to: target)
        return true
    }

    public func route(to target: AppNavigationTarget) {
        pendingTarget = target
        routeGeneration &+= 1
    }

    public func consumePendingTarget() -> AppNavigationTarget? {
        defer { pendingTarget = nil }
        return pendingTarget
    }

    public func clearPendingTarget() {
        pendingTarget = nil
    }
}

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

    /// `-uiScreenshotMessage <id>` opens a specific message after selecting
    /// the Messages tab, allowing screenshot automation to capture its detail.
    public static var screenshotMessageId: String? {
        value(for: "-uiScreenshotMessage")
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
    @State private var navigationStore = AppNavigationStore.shared
    @Environment(\.scenePhase) private var scenePhase
    private let demoMode: Bool

    public init(demoMode: Bool = false) {
        self.demoMode = demoMode
    }

    public var body: some View {
        Group {
            if effectiveDemoMode {
                SignedInRootView(
                    client: .demo,
                    eventStream: .demo,
                    navigationStore: navigationStore
                )
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
            guard !effectiveDemoMode else {
                AuthManager.shared.suspendWidgetRefreshUntilSignIn()
                return
            }
            let wasAlreadySignedIn = AuthManager.shared.authState == .signedIn
            await AuthManager.shared.validateSessionOnLaunch()
            if wasAlreadySignedIn, AuthManager.shared.authState == .signedIn {
                await NotificationManager.shared.synchronizeRegistrationIfAuthorized()
            }
            if AuthManager.shared.authState == .signedIn {
                await refreshWidgetSnapshot()
            } else {
                AuthManager.shared.suspendWidgetRefreshUntilSignIn()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard !effectiveDemoMode else { return }
            guard newPhase == .active else { return }
            Task { @MainActor in
                // A restore that failed while offline is retried here, so
                // coming back to the app is enough to resume the session.
                await AuthManager.shared.validateSessionOnLaunch()
                guard AuthManager.shared.authState == .signedIn else { return }
                _ = await AuthManager.shared.ensureValidToken()
                await PendingMessagesStore.shared.refresh(using: .shared)
                await refreshWidgetSnapshot()
            }
        }
        .onChange(of: auth.authState) { _, newState in
            if newState == .signedIn {
                Task { @MainActor in
                    await NotificationManager.shared.synchronizeRegistrationIfAuthorized()
                    await refreshWidgetSnapshot()
                }
            } else if newState == .signedOut {
                PendingMessagesStore.shared.stopPolling()
            }
        }
        .onOpenURL { url in
            navigationStore.open(url)
        }
    }

    private var effectiveDemoMode: Bool {
        demoMode || config.isDemoMode || LaunchEnv.isScreenshotDemo
    }

    @MainActor
    private func refreshWidgetSnapshot() async {
        #if os(iOS) || os(macOS) || os(visionOS)
        _ = await WidgetRefreshScheduler.refreshNow()
        #endif
    }

    @ViewBuilder
    private var liveRoot: some View {
        switch auth.authState {
        case .unknown:
            #if os(watchOS)
            if auth.getKeychainItem(account: "oidc_refresh_token") != nil {
                SessionRestoreView(restoreFailed: auth.sessionRestoreFailed)
            } else {
                LoginView()
            }
            #else
            SessionRestoreView(restoreFailed: auth.sessionRestoreFailed)
            #endif
        case .signedOut:
            LoginView()
        case .signedIn:
            SignedInRootView(navigationStore: navigationStore)
        }
    }
}

/// Shown while a cached session is being restored. When the provider can't be
/// reached the tokens are kept and retried in the background, so this offers a
/// manual retry instead of dumping the operator back to a sign-in screen.
private struct SessionRestoreView: View {
    let restoreFailed: Bool

    var body: some View {
        VStack(spacing: Theme.Spacing.medium) {
            if restoreFailed {
                Image(systemName: "wifi.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text("Can't reach the booth right now. You're still signed in — we'll keep trying.")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task { await AuthManager.shared.retrySessionRestore() }
                }
                .buttonStyle(.borderedProminent)
                Button("Sign Out", role: .destructive) {
                    Task { await AuthManager.shared.signOutRevokingNotifications() }
                }
                .buttonStyle(.borderless)
            } else {
                ProgressView("Connecting to the booth…")
                    .progressViewStyle(.circular)
            }
        }
        .padding(Theme.Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }
}

#Preview {
    RootContainerView(demoMode: true)
}
