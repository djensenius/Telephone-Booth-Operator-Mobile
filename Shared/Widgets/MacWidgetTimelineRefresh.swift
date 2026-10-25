//
//  MacWidgetTimelineRefresh.swift
//  TelephoneBoothOperatorMobile
//

#if os(macOS)
import Foundation

/// A timeline request can run with the host app terminated. No interactive
/// authentication, app launch, or persistent background helper is involved.
enum MacWidgetTimelineRefresh {
    private static let requests = MacWidgetTimelineRequests()

    static func snapshot() async -> WidgetSnapshot? {
        guard let context = MacWidgetSession.read() else { return nil }
        return await requests.snapshot(context: context)
    }

    fileprivate static func fetch(context: MacWidgetSession) async -> WidgetSnapshot? {
        let client = MacWidgetAPIClient(context: context)
        return await snapshot(
            using: client,
            readSnapshot: { WidgetSnapshotStore.read() },
            writeSnapshot: { snapshot in
                (try? MacWidgetFileLock.withStateLock {
                    guard context.isCurrent(), let url = WidgetSnapshotStore.snapshotURL else { return false }
                    let store = WidgetSnapshotFileStore(directoryURL: url.deletingLastPathComponent())
                    _ = try store.writeMergingNewerSections(snapshot)
                    return true
                }) ?? false
            },
            isCurrent: { context.isCurrent() }
        )
    }

    static func snapshot(
        using client: any WidgetDataFetching,
        readSnapshot: @escaping @Sendable () -> WidgetSnapshot?,
        writeSnapshot: @escaping @Sendable (WidgetSnapshot) -> Bool,
        isCurrent: @escaping @Sendable () -> Bool
    ) async -> WidgetSnapshot? {
        guard isCurrent() else { return nil }
        let coordinator = WidgetRefreshCoordinator(readSnapshot: readSnapshot, writeSnapshot: { snapshot in
            guard isCurrent() else { return false }
            return writeSnapshot(snapshot)
        })
        _ = await coordinator.refresh(using: client)
        // Sign-out, demo mode, or a server change must invalidate in-flight work.
        guard isCurrent() else { return nil }
        return readSnapshot()
    }
}

private actor MacWidgetTimelineRequests {
    private var active: (id: UUID, task: Task<WidgetSnapshot?, Never>)?

    func snapshot(context: MacWidgetSession) async -> WidgetSnapshot? {
        if let active, active.id == context.id { return await active.task.value }
        let task = Task { await MacWidgetTimelineRefresh.fetch(context: context) }
        active = (context.id, task)
        let result = await task.value
        if active?.id == context.id { active = nil }
        return result
    }
}

actor MacWidgetAPIClient: WidgetDataFetching {
    let context: MacWidgetSession
    let session: URLSession
    private let access: MacWidgetSessionAccess
    private var bearer: String?

    // Delegate-backed sessions retain their resources until invalidated. Reuse
    // one bounded, ephemeral session for the extension process's lifetime.
    private static let widgetSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 20
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration, delegate: NoWidgetRedirects(), delegateQueue: nil)
    }()

    init(context: MacWidgetSession, session: URLSession? = nil, access: MacWidgetSessionAccess? = nil) {
        self.context = context
        self.access = access ?? .live(context)
        self.session = session ?? Self.widgetSession
    }

    func fetchStatsSummary(timeZone: TimeZone) async throws -> StatsSummary {
        try await get("v1/stats/summary", query: [URLQueryItem(name: "timeZone", value: timeZone.identifier)])
    }

    func fetchStatsOverview(window: StatsWindow) async throws -> StatsOverview {
        try await get("v1/stats/overview", query: [URLQueryItem(name: "window", value: window.rawValue)])
    }

    func fetchMessages(status: MessageStatus?, since: Date?, limit: Int) async throws -> MessageList {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let status { query.append(URLQueryItem(name: "status", value: status.rawValue)) }
        if let since { query.append(URLQueryItem(name: "since", value: OperatorJSON.iso8601String(from: since))) }
        return try await get("v1/messages", query: query)
    }

    func fetchCurrentSystemEnvelope(boothId: String?) async throws -> BoothSystemSnapshotEnvelope? {
        do {
            if let boothId {
                return try await get("v1/system/current", query: [URLQueryItem(name: "boothId", value: boothId)])
            }
            let list: BoothSystemSnapshotList = try await get("v1/system/current")
            return list.items.first
        } catch WidgetRequestError.http(404) { return nil }
    }

    func fetchCurrentSystemComponents() async throws -> [SystemComponentCurrentEnvelope] {
        do {
            let list: SystemComponentCurrentList = try await get("v1/system/components/current")
            return list.items
        } catch WidgetRequestError.http(404) { return [] }
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try Task.checkCancellation()
        guard access.isCurrent() else { throw WidgetRequestError.signedOut }
        var token = try await accessToken()
        guard var url = URLComponents(
            url: context.apiBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false
        ) else { throw URLError(.badURL) }
        url.queryItems = query.isEmpty ? nil : query
        guard let requestURL = url.url else { throw URLError(.badURL) }
        var request = URLRequest(url: requestURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for attempt in 0..<2 {
            guard access.isCurrent() else { throw WidgetRequestError.signedOut }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 401, attempt == 0 {
                token = try await accessToken(rejectedToken: token)
                continue
            }
            guard (200..<300).contains(http.statusCode) else { throw WidgetRequestError.http(http.statusCode) }
            return try OperatorJSON.decoder.decode(T.self, from: data)
        }
        throw WidgetRequestError.http(401)
    }

    private func accessToken(rejectedToken: String? = nil) async throws -> String {
        if let bearer, bearer != rejectedToken { return bearer }
        let lock = try await access.acquireRefreshLock()
        defer { withExtendedLifetime(lock) {} }
        guard access.isCurrent() else { throw WidgetRequestError.signedOut }
        if let bearer, bearer != rejectedToken { return bearer }
        let token = access.readToken("oidc_access_token")
        if let token, token != rejectedToken, let rawExpiry = access.readToken("oidc_token_expiry"),
           let expiry = TimeInterval(rawExpiry), expiry > Date().timeIntervalSince1970 + 60 {
            bearer = token
            return token
        }
        do {
            let refreshed = try await refreshToken()
            bearer = refreshed
            return refreshed
        } catch {
            // A transient proactive-refresh failure needn't discard a usable token.
            if let token, token != rejectedToken, let rawExpiry = access.readToken("oidc_token_expiry"),
               let expiry = TimeInterval(rawExpiry), expiry > Date().timeIntervalSince1970 {
                bearer = token
                return token
            }
            throw error
        }
    }

    private func refreshToken() async throws -> String {
        guard let refresh = access.readToken("oidc_refresh_token") else {
            throw WidgetRequestError.signedOut
        }
        var request = URLRequest(url: context.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([
            ("grant_type", "refresh_token"), ("refresh_token", refresh),
            ("client_id", context.clientID), ("scope", context.scopes)
        ])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            // The extension never signs the host out on a network/provider failure.
            throw URLError(.userAuthenticationRequired)
        }
        let tokens = try JSONDecoder().decode(OIDCTokens.self, from: data)
        // A display-only transition must not lose a rotated refresh token.
        // The atomic save separately verifies the credential lineage, so late
        // replies after explicit sign-out or a new login remain rejected.
        try access.saveTokens(tokens)
        guard access.isCurrent() else { throw WidgetRequestError.signedOut }
        return tokens.accessToken
    }

    static func formBody(_ values: [(String, String)]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let body = values.map { key, value in
            let key = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let value = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(value)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }
}

private enum WidgetRequestError: Error {
    case signedOut
    case http(Int)
}

/// Never follow a redirect with an API bearer or refresh-token POST body.
private final class NoWidgetRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
#endif
