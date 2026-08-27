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

        let firstChunk = Data(repeating: 1, count: 32)
        let remainingChunks = Data(repeating: 2, count: 1_024)
        AudioFetcherURLProtocol.resetStreamingState()
        AudioFetcherURLProtocol.scenario = .stream(firstChunk, remainingChunks)
        await assertFetchError(.tooLarge) {
            try await fetcher.withFetchedAudioFile(
                url: Self.audioURL,
                expectedSHA256: expectedHash,
                maxBytes: 16
            ) { _ in true }
        }
        let stopLoadingWasCalled = await AudioFetcherURLProtocol.waitForStopLoading()
        XCTAssertTrue(stopLoadingWasCalled)

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

    func testRejectsInvalidHashBeforeNetworking() async {
        let fetcher = URLSessionAudioFetcher()
        do {
            _ = try await fetcher.withFetchedAudioFile(
                url: Self.audioURL,
                expectedSHA256: "invalid",
                maxBytes: 10
            ) { _ in true }
            XCTFail("Expected invalid hash failure")
        } catch {
            XCTAssertEqual(error as? AudioFetchError, .invalidExpectedHash)
        }
    }

    func testRejectsInsecureURLBeforeNetworking() async {
        let fetcher = URLSessionAudioFetcher()
        do {
            _ = try await fetcher.withFetchedAudioFile(
                url: URL(string: "http://example.com/audio.flac")!,
                expectedSHA256: String(repeating: "a", count: 64),
                maxBytes: 10
            ) { _ in true }
            XCTFail("Expected insecure URL failure")
        } catch {
            XCTAssertEqual(error as? AudioFetchError, .insecureURL)
        }
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
        case stream(Data, Data)
    }

    nonisolated(unsafe) static var scenario = Scenario.body(Data())
    nonisolated(unsafe) static var lastRequest: URLRequest?
    private static let streamingLock = NSLock()
    private nonisolated(unsafe) static var stopLoadingWasCalled = false
    private let stateLock = NSLock()
    private var stopped = false

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    static func resetStreamingState() {
        streamingLock.withLock {
            stopLoadingWasCalled = false
        }
    }

    static func waitForStopLoading() async -> Bool {
        for _ in 0..<100 {
            if wasStopLoadingCalled { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private static var wasStopLoadingCalled: Bool {
        streamingLock.withLock { stopLoadingWasCalled }
    }

    override func stopLoading() {
        stateLock.lock()
        stopped = true
        stateLock.unlock()
        Self.streamingLock.withLock {
            Self.stopLoadingWasCalled = true
        }
    }

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
            client?.urlProtocolDidFinishLoading(self)
        case .stream(let firstChunk, let remainingChunks):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            let reference = URLProtocolReference(self)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                guard let protocolInstance = reference.value else { return }
                _ = protocolInstance.deliver(firstChunk)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                guard let protocolInstance = reference.value,
                      protocolInstance.deliver(remainingChunks) else {
                    return
                }
                protocolInstance.client?.urlProtocolDidFinishLoading(protocolInstance)
            }
        }
    }

    private final class URLProtocolReference: @unchecked Sendable {
        weak var value: AudioFetcherURLProtocol?

        init(_ value: AudioFetcherURLProtocol) {
            self.value = value
        }
    }

    @discardableResult
    private func deliver(_ data: Data) -> Bool {
        stateLock.lock()
        guard !stopped else {
            stateLock.unlock()
            return false
        }
        stateLock.unlock()
        client?.urlProtocol(self, didLoad: data)
        return true
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
