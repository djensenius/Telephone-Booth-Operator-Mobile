import XCTest
@testable import TBOperatorMobile

@MainActor
final class WatchBrokerTests: XCTestCase {
    private func reply(token: String = "watch-access") -> WatchBrokerReply {
        let config = AppConfig.shared
        return .token(
            accessToken: token,
            expiry: Date().addingTimeInterval(300).timeIntervalSince1970,
            issuer: config.oidcIssuerBase,
            clientID: config.oidcClientID,
            apiBase: config.apiBaseURL.absoluteString
        )
    }

    func testFirstSignInPersistsOnlyAccessTokenAndRestoresSession() async {
        let auth = AuthManager(keychainStore: TestKeychainStore())
        let response = reply()
        let sync = WatchAuthSync(auth: auth) { _ in response }
        auth.sessionRestoreFailed = true

        let connected = await sync.ensureBrokeredToken()

        XCTAssertTrue(connected)
        XCTAssertEqual(auth.authState, .signedIn)
        XCTAssertFalse(auth.sessionRestoreFailed)
        XCTAssertEqual(auth.getAccessToken(), "watch-access")
        XCTAssertNil(auth.getKeychainItem(account: "oidc_refresh_token"))
    }

    func testAutomaticLoginNeverReplacesAnIndependentWatchSession() async {
        let auth = AuthManager(keychainStore: TestKeychainStore())
        auth.storeTokens(OIDCTokens(
            accessToken: "expired-independent", refreshToken: "independent-refresh",
            idToken: nil, expiresIn: -10, tokenType: "Bearer"
        ))
        auth.resetStateForTesting()
        let sync = WatchAuthSync(auth: auth) { _ in
            XCTFail("An independent watch session must refresh itself, not contact the phone")
            return .failure(.signedOut)
        }

        await sync.connectFromLogin(automatically: true)

        XCTAssertEqual(auth.getKeychainItem(account: "oidc_refresh_token"), "independent-refresh")
        XCTAssertEqual(auth.getAccessToken(), "expired-independent")
        XCTAssertEqual(auth.authState, .unknown)
    }

    func testConcurrentRequestsCoalesce() async {
        let auth = AuthManager(keychainStore: TestKeychainStore())
        let response = reply()
        var requests = 0
        let sync = WatchAuthSync(auth: auth) { _ in
            requests += 1
            await Task.yield()
            return response
        }

        async let first = sync.ensureBrokeredToken()
        async let second = sync.ensureBrokeredToken()
        let results = await (first, second)

        XCTAssertTrue(results.0)
        XCTAssertTrue(results.1)
        XCTAssertEqual(requests, 1)
        XCTAssertFalse(sync.isConnecting)
    }

    func testValidCacheAvoidsPhoneButUnauthorizedForcesRenewal() async {
        let auth = AuthManager(keychainStore: TestKeychainStore())
        XCTAssertTrue(auth.applyBrokeredAccessToken(
            accessToken: "cached", expiry: Date().addingTimeInterval(300).timeIntervalSince1970
        ))
        var forcedRequests: [Bool] = []
        let response = reply()
        let sync = WatchAuthSync(auth: auth) { force in
            forcedRequests.append(force)
            return response
        }

        let cached = await sync.ensureBrokeredToken()
        XCTAssertTrue(cached)
        XCTAssertTrue(forcedRequests.isEmpty)
        let refreshed = await sync.ensureBrokeredToken(forceRefresh: true)
        XCTAssertTrue(refreshed)
        XCTAssertEqual(forcedRequests, [true])
        XCTAssertEqual(auth.getAccessToken(), "watch-access")
    }

    func testTransientPhoneFailurePreservesCredentials() async {
        let auth = AuthManager(keychainStore: TestKeychainStore())
        XCTAssertTrue(auth.applyBrokeredAccessToken(
            accessToken: "cached", expiry: Date().addingTimeInterval(30).timeIntervalSince1970
        ))
        let sync = WatchAuthSync(auth: auth) { _ in .failure(.unavailable) }

        let connected = await sync.ensureBrokeredToken()

        XCTAssertFalse(connected)
        XCTAssertEqual(auth.getAccessToken(), "cached")
        XCTAssertEqual(auth.authState, .signedIn)
        XCTAssertEqual(sync.statusMessage, WatchBrokerFailure.unavailable.message)
    }

    func testForcedRenewalDoesNotJoinAnOrdinaryCacheRequest() async {
        let auth = AuthManager(keychainStore: TestKeychainStore())
        let response = reply()
        var requests: [Bool] = []
        var release: CheckedContinuation<Void, Never>?
        let sync = WatchAuthSync(auth: auth) { forced in
            requests.append(forced)
            if !forced {
                await withCheckedContinuation { release = $0 }
            }
            return response
        }
        let ordinary = Task { await sync.ensureBrokeredToken() }
        while release == nil { await Task.yield() }
        let forced = Task { await sync.ensureBrokeredToken(forceRefresh: true) }
        await Task.yield()
        release?.resume()
        let ordinaryResult = await ordinary.value
        let forcedResult = await forced.value
        XCTAssertTrue(ordinaryResult)
        XCTAssertTrue(forcedResult)
        XCTAssertEqual(requests, [false, true])
    }

    func testExplicitPhoneSignOutClearsWatchCredentials() async {
        let auth = AuthManager(keychainStore: TestKeychainStore())
        XCTAssertTrue(auth.applyBrokeredAccessToken(
            accessToken: "cached", expiry: Date().addingTimeInterval(30).timeIntervalSince1970
        ))
        let sync = WatchAuthSync(auth: auth) { _ in .failure(.signedOut) }

        let connected = await sync.ensureBrokeredToken()

        XCTAssertFalse(connected)
        XCTAssertNil(auth.getAccessToken())
        XCTAssertEqual(auth.authState, .signedOut)
    }

    func testLateReplyCannotUndoSignOut() async {
        let auth = AuthManager(keychainStore: TestKeychainStore())
        let response = reply()
        let sync = WatchAuthSync(auth: auth) { _ in
            auth.signOut()
            return response
        }

        let connected = await sync.ensureBrokeredToken()

        XCTAssertFalse(connected)
        XCTAssertNil(auth.getAccessToken())
        XCTAssertEqual(auth.authState, .signedOut)
    }

    func testMismatchedServerOrIssuerOrClientIsRejected() async {
        let config = AppConfig.shared
        for mismatch in 0..<3 {
            let auth = AuthManager(keychainStore: TestKeychainStore())
            let sync = WatchAuthSync(auth: auth) { _ in
                .token(
                    accessToken: "wrong-config",
                    expiry: Date().addingTimeInterval(300).timeIntervalSince1970,
                    issuer: mismatch == 0 ? "https://wrong.example" : config.oidcIssuerBase,
                    clientID: mismatch == 1 ? "wrong-client" : config.oidcClientID,
                    apiBase: mismatch == 2 ? "https://wrong.example" : config.apiBaseURL.absoluteString
                )
            }
            let connected = await sync.ensureBrokeredToken()
            XCTAssertFalse(connected)
            XCTAssertNil(auth.getAccessToken())
            XCTAssertEqual(sync.statusMessage, WatchBrokerFailure.configuration.message)
        }
    }

    func testInvalidCredentialCannotBeStored() {
        let auth = AuthManager(keychainStore: TestKeychainStore())
        for expiry in [Double.nan, .infinity, -.infinity, Date().timeIntervalSince1970 - 1] {
            XCTAssertFalse(auth.applyBrokeredAccessToken(accessToken: "invalid", expiry: expiry))
        }
        XCTAssertFalse(auth.applyBrokeredAccessToken(
            accessToken: " ", expiry: Date().addingTimeInterval(300).timeIntervalSince1970
        ))
        XCTAssertNil(auth.getAccessToken())
        XCTAssertEqual(auth.authState, .signedOut)
    }

    func testExpiryWriteFailureDoesNotLeaveUsableAccessToken() {
        let store = FailingWatchKeychain()
        let auth = AuthManager(keychainStore: store)
        XCTAssertFalse(auth.applyBrokeredAccessToken(
            accessToken: "new", expiry: Date().addingTimeInterval(300).timeIntervalSince1970
        ))
        XCTAssertNil(auth.getAccessToken())
        XCTAssertNil(auth.getKeychainItem(account: "oidc_token_expiry"))
        XCTAssertEqual(auth.authState, .signedOut)
    }

    func testLegacyPhoneReplyExplainsRequiredUpdate() {
        let reply = WatchBrokerReply(message: [
            "tbo_ok": true, "access_token": "legacy", "expiry": 123.0
        ])
        guard case .failure(.updatePhone) = reply else {
            return XCTFail("Missing configuration must not be accepted")
        }
    }

    func testReplyTimeoutAndLateCompletionAreSafe() async {
        var waiter: WatchBrokerReplyWaiter?
        let result = await withCheckedContinuation { continuation in
            waiter = WatchBrokerReplyWaiter(continuation, timeout: .milliseconds(1))
        }
        guard case .failure(.timeout) = result else { return XCTFail("Expected a bounded timeout") }
        waiter?.finish(reply())
        waiter?.finish(.failure(.unreachable))
    }
}

@MainActor
private final class FailingWatchKeychain: KeychainStoring {
    private var values: [String: String] = [:]
    func migrateAccessibility(service: String, accounts: [String], to accessibility: KeychainAccessibility) {}
    func set(service: String, account: String, value: String, accessibility: KeychainAccessibility) -> Bool {
        guard account != "oidc_token_expiry" else { return false }
        values[account] = value
        return true
    }
    func get(service: String, account: String) -> String? { values[account] }
    func delete(service: String, account: String) { values[account] = nil }
}
