//
//  OnDeviceAudioFetcherTests.swift
//  TBOperatorMobileTests
//

import CryptoKit
import Foundation
import XCTest
@testable import TBOperatorMobile

final class OnDeviceAudioFetcherTests: XCTestCase {
    func testDownloadSecurityLimitsHashAndCleanup() async throws {
        let audio = Data("test audio".utf8)
        let expectedHash = SHA256.hash(data: audio)
            .map { String(format: "%02x", $0) }
            .joined()
        let fetcher = makeFetcher()
        let stagedURL = CapturedURL()

        AudioFetcherURLProtocol.scenario = .body(audio)
        let received = try await fetcher.withFetchedAudioFile(
            url: Self.audioURL,
            expectedSHA256: expectedHash,
            maxBytes: 1_024
        ) { url in
            await stagedURL.set(url)
            return try Data(contentsOf: url)
        }
        XCTAssertEqual(received, audio)
        XCTAssertEqual(AudioFetcherURLProtocol.lastRequest?.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(
            AudioFetcherURLProtocol.lastRequest?.cachePolicy,
            .reloadIgnoringLocalAndRemoteCacheData
        )
        let stagedFileExists = await stagedURL.fileExists
        XCTAssertFalse(stagedFileExists)

        AudioFetcherURLProtocol.scenario = .body(audio)
        await assertFetchError(.tooLarge) {
            try await fetcher.withFetchedAudioFile(
                url: Self.audioURL,
                expectedSHA256: expectedHash,
                maxBytes: audio.count - 1
            ) { _ in true }
        }

        AudioFetcherURLProtocol.scenario = .body(audio)
        await assertFetchError(.hashMismatch) {
            try await fetcher.withFetchedAudioFile(
                url: Self.audioURL,
                expectedSHA256: String(repeating: "0", count: 64),
                maxBytes: 1_024
            ) { _ in true }
        }

        AudioFetcherURLProtocol.scenario = .insecureRedirect(audio)
        await assertFetchError(.insecureURL) {
            try await fetcher.withFetchedAudioFile(
                url: Self.audioURL,
                expectedSHA256: expectedHash,
                maxBytes: 1_024
            ) { _ in true }
        }

        AudioFetcherURLProtocol.scenario = .body(audio)
        let throwingBodyURL = CapturedURL()
        do {
            _ = try await fetcher.withFetchedAudioFile(
                url: Self.audioURL,
                expectedSHA256: expectedHash,
                maxBytes: 1_024
            ) { url in
                await throwingBodyURL.set(url)
                throw BodyFailure.requested
            }
            XCTFail("Expected the body to throw")
        } catch BodyFailure.requested {}
        let throwingBodyFileExists = await throwingBodyURL.fileExists
        XCTAssertFalse(throwingBodyFileExists)
    }

    private static let audioURL = URL(string: "https://example.com/audio.flac")!

    private func makeFetcher() -> URLSessionAudioFetcher {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AudioFetcherURLProtocol.self]
        return URLSessionAudioFetcher(session: URLSession(configuration: configuration))
    }

    private func assertFetchError<T: Sendable>(
        _ expected: AudioFetchError,
        operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)")
        } catch let error as AudioFetchError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private enum BodyFailure: Error {
    case requested
}

private actor CapturedURL {
    private var value: URL?

    var fileExists: Bool {
        value.map { FileManager.default.fileExists(atPath: $0.path) } ?? true
    }

    func set(_ url: URL) {
        value = url
    }
}

private final class AudioFetcherURLProtocol: URLProtocol {
    enum Scenario {
        case body(Data)
        case insecureRedirect(Data)
    }

    nonisolated(unsafe) static var scenario = Scenario.body(Data())
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lastRequest = request
        switch Self.scenario {
        case .body(let data):
            respond(with: data)
        case .insecureRedirect(let data):
            if request.url?.scheme == "http" {
                respond(with: data)
                return
            }
            let redirected = URLRequest(url: URL(string: "http://example.com/audio.flac")!)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": redirected.url!.absoluteString]
            )!
            client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
        }
    }

    private func respond(with data: Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": String(data.count)]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
