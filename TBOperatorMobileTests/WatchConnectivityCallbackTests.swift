import XCTest
import WatchConnectivity
#if os(watchOS)
@testable import TBOperatorMobileWatch
#else
@testable import TBOperatorMobile
#endif

@MainActor
final class WatchConnectivityCallbackTests: XCTestCase {
    #if os(iOS) && targetEnvironment(simulator)
    // Swift-only callback mocks miss actor checks in Objective-C block thunks.
    func testActualWatchConnectivityFailure() async throws {
        guard WCSession.isSupported(), !AppConfig.shared.isDemoMode else {
            throw XCTSkip("Requires WatchConnectivity on a non-demo simulator")
        }
        WatchAuthSync.shared.activate()
        let session = WCSession.default
        for _ in 0..<25 {
            if session.activationState == .activated { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        guard session.activationState == .activated, !session.isPaired else {
            throw XCTSkip("Requires an activated, unpaired session to exercise framework callback delivery")
        }
        let result = await WatchAuthSync.shared.ensureBrokeredToken(forceRefresh: true)
        XCTAssertFalse(result)
        XCTAssertEqual(WatchAuthSync.shared.statusMessage, WatchBrokerFailure.unreachable.message)
    }
    #endif

    func testTokenReplyFromBackgroundQueue() async {
        let result = await withCheckedContinuation { continuation in
            let waiter = WatchBrokerReplyWaiter(continuation, timeout: .seconds(5))
            let callbacks = CallbackDelivery(waiter: waiter)
            DispatchQueue.global(qos: .utility).async {
                callbacks.reply([
                    "tbo_ok": true, "access_token": "test-token", "expiry": 12345.0,
                    "iss": "test-issuer", "cid": "test-client", "api_base": "https://example.invalid"
                ])
            }
        }
        guard case .token(let token, let expiry, let issuer, let client, let apiBase) = result else {
            return XCTFail("Expected the background reply to resume with a token")
        }
        XCTAssertEqual(token, "test-token")
        XCTAssertEqual(expiry, 12345)
        XCTAssertEqual(issuer, "test-issuer")
        XCTAssertEqual(client, "test-client")
        XCTAssertEqual(apiBase, "https://example.invalid")
    }

    func testTransportErrorFromBackgroundQueue() async {
        let result = await withCheckedContinuation { continuation in
            let waiter = WatchBrokerReplyWaiter(continuation, timeout: .seconds(5))
            let callbacks = CallbackDelivery(waiter: waiter)
            DispatchQueue.global(qos: .utility).async {
                callbacks.error(URLError(.notConnectedToInternet))
            }
        }
        guard case .failure(.unreachable) = result else {
            return XCTFail("Expected a recoverable transport error")
        }
    }

    func testReplyThenErrorOnlyCompletesOnce() async {
        let result = await withCheckedContinuation { continuation in
            let waiter = WatchBrokerReplyWaiter(continuation, timeout: .seconds(5))
            let callbacks = CallbackDelivery(waiter: waiter)
            DispatchQueue.global(qos: .utility).async {
                callbacks.reply(["tbo_ok": false, "reason": "signed_out"])
                callbacks.error(URLError(.timedOut))
            }
        }
        guard case .failure(.signedOut) = result else {
            return XCTFail("The first callback should complete the request")
        }
    }

    func testCallbacksAfterTimeoutDoNotResumeAgain() async {
        var callbacks: CallbackDelivery?
        let result = await withCheckedContinuation { continuation in
            let waiter = WatchBrokerReplyWaiter(continuation, timeout: .milliseconds(1))
            callbacks = CallbackDelivery(waiter: waiter)
        }
        guard case .failure(.timeout) = result, let callbacks else {
            return XCTFail("Expected a bounded timeout")
        }
        await Task.detached {
            callbacks.reply(["tbo_ok": false, "reason": "signed_out"])
            callbacks.error(URLError(.timedOut))
        }.value
    }
}

private struct CallbackDelivery: Sendable {
    let reply: @Sendable ([String: Any]) -> Void
    let error: @Sendable (Error) -> Void

    @MainActor
    init(waiter: WatchBrokerReplyWaiter) {
        reply = waiter.replyHandler
        error = waiter.errorHandler
    }
}
