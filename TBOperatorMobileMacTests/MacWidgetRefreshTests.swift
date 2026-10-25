//
//  MacWidgetRefreshTests.swift
//

import os
import XCTest
@testable import Operator

final class MacWidgetRefreshTests: XCTestCase {
    func testWidgetFetchesWithoutHostAuthenticationManager() async throws {
        let fixture = WidgetSessionFixture()
        let expected = DemoData.statsSummary
        let client = fixture.client { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer cached-access")
            XCTAssertEqual(request.url?.path, "/operator/v1/stats/summary")
            let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(query?.first?.name, "timeZone")
            return (200, try OperatorJSON.encoder.encode(expected))
        }
        let actual = try await client.fetchStatsSummary(timeZone: .gmt)
        XCTAssertEqual(actual.messages.pending, expected.messages.pending)
        XCTAssertEqual(fixture.saved.withLock { $0 }, 0)
    }

    func testExpiredTokenRotatesAndPersistsBeforeAPIRequest() async throws {
        let fixture = WidgetSessionFixture(expiry: -60)
        let client = fixture.client { request in
            if request.httpMethod == "POST" {
                XCTAssertTrue(request.url?.absoluteString.hasSuffix("/token/") == true)
                return (200, Self.tokenResponse)
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer renewed-access")
            XCTAssertEqual(fixture.values.withLock { $0["oidc_refresh_token"] }, "renewed-refresh")
            return (200, try OperatorJSON.encoder.encode(DemoData.statsSummary))
        }
        _ = try await client.fetchStatsSummary(timeZone: .gmt)
        XCTAssertEqual(fixture.saved.withLock { $0 }, 1)
    }

    func testUnauthorizedRequestRefreshesAndRetriesOnce() async throws {
        let fixture = WidgetSessionFixture()
        let requests = OSAllocatedUnfairLock(initialState: 0)
        let client = fixture.client { request in
            if request.httpMethod == "POST" { return (200, Self.tokenResponse) }
            let count = requests.withLock { $0 += 1; return $0 }
            return count == 1 ? (401, Data()) : (200, try OperatorJSON.encoder.encode(DemoData.statsSummary))
        }
        _ = try await client.fetchStatsSummary(timeZone: .gmt)
        XCTAssertEqual(requests.withLock { $0 }, 2)
        XCTAssertEqual(fixture.saved.withLock { $0 }, 1)
    }

    func testRepeatedUnauthorizedResponseStopsRetrying() async {
        let fixture = WidgetSessionFixture()
        let requests = OSAllocatedUnfairLock(initialState: 0)
        let client = fixture.client { request in
            if request.httpMethod == "POST" { return (200, Self.tokenResponse) }
            requests.withLock { $0 += 1 }
            return (401, Data())
        }
        do {
            _ = try await client.fetchStatsSummary(timeZone: .gmt)
            XCTFail("A repeated 401 must fail")
        } catch {}
        XCTAssertEqual(requests.withLock { $0 }, 2)
    }

    func testTransientRefreshFailureUsesStillValidToken() async throws {
        let fixture = WidgetSessionFixture(expiry: 30)
        let client = fixture.client { request in
            if request.httpMethod == "POST" { return (503, Data()) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer cached-access")
            return (200, try OperatorJSON.encoder.encode(DemoData.statsSummary))
        }
        _ = try await client.fetchStatsSummary(timeZone: .gmt)
        XCTAssertEqual(fixture.saved.withLock { $0 }, 0)
        XCTAssertEqual(fixture.values.withLock { $0["oidc_refresh_token"] }, "cached-refresh")
    }

    func testSignOutDuringRefreshCannotSaveOrUseReturnedTokens() async {
        let fixture = WidgetSessionFixture(expiry: -60)
        let client = fixture.client { request in
            XCTAssertEqual(request.httpMethod, "POST")
            fixture.current.withLock { $0 = false }
            return (200, Self.tokenResponse)
        }
        do {
            _ = try await client.fetchStatsSummary(timeZone: .gmt)
            XCTFail("An invalidated session must fail")
        } catch {}
        XCTAssertEqual(fixture.saved.withLock { $0 }, 0)
        XCTAssertEqual(fixture.values.withLock { $0["oidc_access_token"] }, "cached-access")
    }

    func testSessionInvalidatedWhileWaitingForRefreshLockDoesNotRequest() async {
        let fixture = WidgetSessionFixture(expiry: -60)
        let client = fixture.client(invalidateOnLock: true) { _ in
            XCTFail("Invalidated sessions must not make network requests")
            return (500, Data())
        }
        do {
            _ = try await client.fetchStatsSummary(timeZone: .gmt)
            XCTFail("An invalidated session must fail")
        } catch {}
    }

    func testTransientNetworkFailureKeepsCachedSnapshot() async {
        let fixture = WidgetSessionFixture()
        let cached = WidgetSnapshot.placeholder
        let client = fixture.client { _ in throw URLError(.notConnectedToInternet) }
        let result = await MacWidgetTimelineRefresh.snapshot(
            using: client, readSnapshot: { cached },
            writeSnapshot: { _ in XCTFail("Failed requests must not replace cache"); return false },
            isCurrent: { true }
        )
        XCTAssertEqual(result, cached)
    }

    func testIndependentTimelineWritesSuccessfulSectionsAndPreservesFailedOnes() async throws {
        let fixture = WidgetSessionFixture()
        let cache = OSAllocatedUnfairLock(initialState: WidgetSnapshot.placeholder)
        let previousMessage = cache.withLock { $0.latestMessage }
        let client = fixture.client { request in
            if request.url?.path.hasSuffix("stats/summary") == true {
                return (200, try OperatorJSON.encoder.encode(DemoData.rebasedStats()))
            }
            return (503, Data())
        }
        let result = await MacWidgetTimelineRefresh.snapshot(
            using: client, readSnapshot: { cache.withLock { $0 } },
            writeSnapshot: { snapshot in cache.withLock { $0 = snapshot }; return true },
            isCurrent: { true }
        )
        XCTAssertEqual(result?.latestMessage, previousMessage)
        XCTAssertNotNil(result?.summary)
        XCTAssertGreaterThan(try XCTUnwrap(result?.summary?.refreshedAt),
                             try XCTUnwrap(WidgetSnapshot.placeholder.summary?.refreshedAt))
    }

    func testInvalidatedTimelineDoesNotExposeCachedPrivateData() async {
        let fixture = WidgetSessionFixture()
        let client = fixture.client { _ in
            fixture.current.withLock { $0 = false }
            throw URLError(.cancelled)
        }
        let result = await MacWidgetTimelineRefresh.snapshot(
            using: client, readSnapshot: { .placeholder }, writeSnapshot: { _ in false },
            isCurrent: { fixture.current.withLock { $0 } }
        )
        XCTAssertNil(result)
    }

    func testMergingRetainsNewerSectionsFromOtherProcess() throws {
        let older = WidgetSnapshot.placeholder
        let date = older.writtenAt.addingTimeInterval(60)
        let newer = WidgetSnapshot(summary: .init(stats: DemoData.statsSummary, refreshedAt: date), writtenAt: date)
        let merged = older.mergingNewerSections(from: newer)
        XCTAssertEqual(merged.summary, newer.summary)
        XCTAssertEqual(merged.latestMessage, older.latestMessage)
        XCTAssertEqual(merged.systemHealth, older.systemHealth)
        XCTAssertEqual(merged.activity, older.activity)
        XCTAssertEqual(newer.mergingNewerSections(from: older), merged)
    }

    func testLaterFetchCannotReplaceNewerBoothSourceData() {
        let source = Date(timeIntervalSince1970: 2_000_000_000)
        func snapshot(source: Date, fetched: Date) -> WidgetSnapshot {
            WidgetSnapshot(summary: .init(
                boothState: .idle, boothUpdatedAt: source, pendingMessages: 1, receivedToday: 1,
                interactionsToday: 1, interactionsInProgress: 0, wsClients: 1, runtimeMode: nil,
                sourceGeneratedAt: source, refreshedAt: fetched
            ), writtenAt: fetched)
        }
        let live = snapshot(source: source, fetched: source)
        let cachedServerResponse = snapshot(
            source: source.addingTimeInterval(-10), fetched: source.addingTimeInterval(5)
        )
        XCTAssertEqual(cachedServerResponse.mergingNewerSections(from: live).summary, live.summary)
        XCTAssertEqual(live.mergingNewerSections(from: cachedServerResponse).summary, live.summary)
    }

    func testEmptyMessageRefreshCannotResurrectDeletedMetadata() throws {
        let previous = WidgetSnapshot.placeholder
        let checkedAt = previous.writtenAt.addingTimeInterval(60)
        let empty = WidgetSnapshot(latestMessageRefreshedAt: checkedAt, writtenAt: checkedAt)
        let merged = previous.mergingNewerSections(from: empty)
        XCTAssertNil(merged.latestMessage)
        XCTAssertEqual(merged.latestMessageRefreshedAt, checkedAt)
        XCTAssertNil(merged.mergingNewerSections(from: previous).latestMessage)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(merged))
        XCTAssertEqual(decoded.latestMessageRefreshedAt, checkedAt)
    }

    func testFileLockExcludesOtherDescriptorsAndReleasesOnScopeExit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let lock = try MacWidgetFileLock.acquire(name: "test.lock", wait: false, directoryURL: directory)
            XCTAssertThrowsError(try MacWidgetFileLock.acquire(name: "test.lock", wait: false, directoryURL: directory))
            withExtendedLifetime(lock) {}
        }
        XCTAssertNoThrow(try MacWidgetFileLock.acquire(name: "test.lock", wait: false, directoryURL: directory))
    }

    func testRefreshFormEscapesReservedCharacters() {
        let body = MacWidgetAPIClient.formBody([("refresh_token", "a+b&c=d /?"), ("scope", "openid offline_access")])
        XCTAssertEqual(String(data: body, encoding: .utf8),
                       "refresh_token=a%2Bb%26c%3Dd%20%2F%3F&scope=openid%20offline_access")
    }

    func testSubsecondCacheOrderingPreservesSuccessfulEmptyMessageRefresh() throws {
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.snapshotURL.deletingLastPathComponent()) }
        let base = Date(timeIntervalSince1970: 2_000_000_000)
        let older = WidgetSnapshot(latestMessage: .init(
            id: "deleted", status: .received, occurredAt: base, refreshedAt: base.addingTimeInterval(0.1)
        ), writtenAt: base.addingTimeInterval(0.1))
        let newer = WidgetSnapshot(latestMessageRefreshedAt: base.addingTimeInterval(0.8),
                                   writtenAt: base.addingTimeInterval(0.8))
        _ = try store.writeMergingNewerSections(older)
        _ = try store.writeMergingNewerSections(newer)
        _ = try store.writeMergingNewerSections(older)
        let read = try XCTUnwrap(store.read())
        XCTAssertNil(read.latestMessage)
        XCTAssertEqual(try XCTUnwrap(read.latestMessageRefreshedAt).timeIntervalSince1970,
                       base.timeIntervalSince1970 + 0.8, accuracy: 0.000001)
    }

    func testCacheStillDecodesInstalledISO8601Snapshots() throws {
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.snapshotURL.deletingLastPathComponent()) }
        let data = Data("""
        {"schemaVersion":2,"writtenAt":"2023-11-14T22:13:20Z"}
        """.utf8)
        try data.write(to: store.snapshotURL)
        XCTAssertEqual(try store.read()?.writtenAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testMalformedCacheIsRepairedByFreshData() throws {
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.snapshotURL.deletingLastPathComponent()) }
        try Data("{damaged".utf8).write(to: store.snapshotURL)
        XCTAssertTrue(try store.writeMergingNewerSections(.placeholder))
        XCTAssertEqual(try store.read(), .placeholder)
    }

    func testCacheMergeStillPropagatesWriteFailures() throws {
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.snapshotURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: store.snapshotURL, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.writeMergingNewerSections(.placeholder))
    }

    func testSuccessfulEmptyTelemetryResponseClearsOldHealthAcrossWriters() async throws {
        let fixture = WidgetSessionFixture()
        let cache = OSAllocatedUnfairLock(initialState: WidgetSnapshot.placeholder)
        let client = fixture.client { request in
            switch request.url?.lastPathComponent {
            case "summary": return (200, try OperatorJSON.encoder.encode(DemoData.rebasedStats()))
            case "current", "messages": return (200, Data("{\"items\":[]}".utf8))
            default: return (503, Data())
            }
        }
        let result = await MacWidgetTimelineRefresh.snapshot(
            using: client, readSnapshot: { cache.withLock { $0 } },
            writeSnapshot: { snapshot in
                cache.withLock { $0 = snapshot.mergingNewerSections(from: $0) }
                return true
            }, isCurrent: { true }
        )
        XCTAssertNil(result?.systemHealth)
        XCTAssertNotNil(result?.systemHealthRefreshedAt)
        XCTAssertNil(result?.mergingNewerSections(from: .placeholder).systemHealth)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(decoded.systemHealthRefreshedAt, result?.systemHealthRefreshedAt)
    }

    func testDefaultWidgetClientsReuseOneNetworkSession() async {
        let context = MacWidgetSession(
            id: UUID(), apiBaseURL: URL(string: "https://example.test")!,
            tokenURL: URL(string: "https://example.test/token/")!, clientID: "test", scopes: "openid"
        )
        let first = MacWidgetAPIClient(context: context)
        let second = MacWidgetAPIClient(context: context)
        let firstSession = await first.session
        let secondSession = await second.session
        XCTAssertTrue(firstSession === secondSession)
    }

    private func temporaryStore() throws -> WidgetSnapshotFileStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return WidgetSnapshotFileStore(directoryURL: directory)
    }

    private static let tokenResponse = Data("""
    {"access_token":"renewed-access","refresh_token":"renewed-refresh","expires_in":3600,"token_type":"Bearer"}
    """.utf8)
}

private struct WidgetSessionFixture: Sendable {
    let values: OSAllocatedUnfairLock<[String: String]>
    let current = OSAllocatedUnfairLock(initialState: true)
    let saved = OSAllocatedUnfairLock(initialState: 0)

    init(expiry: TimeInterval = 3_600) {
        values = OSAllocatedUnfairLock(initialState: [
            "oidc_access_token": "cached-access", "oidc_refresh_token": "cached-refresh",
            "oidc_token_expiry": String(Date().timeIntervalSince1970 + expiry)
        ])
    }

    func client(
        invalidateOnLock: Bool = false,
        handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)
    ) -> MacWidgetAPIClient {
        let identifier = UUID().uuidString.lowercased()
        WidgetHTTPStub.handlers.withLock { $0[identifier] = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WidgetHTTPStub.self]
        let context = MacWidgetSession(
            id: UUID(), apiBaseURL: URL(string: "https://\(identifier)/operator")!,
            tokenURL: URL(string: "https://\(identifier)/token/")!,
            clientID: "test-client", scopes: "openid offline_access"
        )
        return MacWidgetAPIClient(
            context: context, session: URLSession(configuration: configuration),
            access: MacWidgetSessionAccess(
                isCurrent: { current.withLock { $0 } },
                readToken: { account in values.withLock { $0[account] } },
                saveTokens: { tokens in
                    guard current.withLock({ $0 }) else { throw URLError(.cancelled) }
                    saved.withLock { $0 += 1 }
                    values.withLock {
                        $0["oidc_access_token"] = tokens.accessToken
                        if let refresh = tokens.refreshToken { $0["oidc_refresh_token"] = refresh }
                        $0["oidc_token_expiry"] = String(Date().timeIntervalSince1970 + Double(tokens.expiresIn ?? 0))
                    }
                },
                acquireRefreshLock: {
                    if invalidateOnLock { current.withLock { $0 = false } }
                    return nil
                }
            )
        )
    }
}

private class WidgetHTTPStub: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)
    static let handlers = OSAllocatedUnfairLock(initialState: [String: Handler]())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            let handler = try XCTUnwrap(Self.handlers.withLock { $0[url.host ?? ""] })
            let (status, data) = try handler(request)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url, statusCode: status, httpVersion: nil, headerFields: nil
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
