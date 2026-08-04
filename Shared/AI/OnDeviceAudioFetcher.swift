//
//  OnDeviceAudioFetcher.swift
//  TelephoneBoothOperatorMobile
//

import CryptoKit
import Foundation
import os

private let audioFetchLogger = Logger(
    subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
    category: "OnDeviceAudio"
)

private final class SizeLimitingDataDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maxBytes: Int64
    private let destinationURL: URL
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var completionError: Error?
    private var downloadSession: URLSession?
    private var fileHandle: FileHandle?
    private var response: URLResponse?
    private var receivedBytes: Int64 = 0
    private var limitExceeded = false
    private var insecureRedirect = false

    init(maxBytes: Int, destinationURL: URL) {
        self.maxBytes = Int64(maxBytes)
        self.destinationURL = destinationURL
    }

    func download(
        request: URLRequest,
        configuration: URLSessionConfiguration
    ) async throws -> (URL, URLResponse) {
        guard FileManager.default.createFile(
            atPath: destinationURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw AudioFetchError.fetchFailed
        }
        fileHandle = try FileHandle(forWritingTo: destinationURL)
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            let session = URLSession(
                configuration: configuration,
                delegate: self,
                delegateQueue: nil
            )
            downloadSession = session
            lock.unlock()
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        self.response = response
        if response.expectedContentLength > maxBytes {
            limitExceeded = true
        }
        let disposition: URLSession.ResponseDisposition = limitExceeded ? .cancel : .allow
        lock.unlock()
        completionHandler(disposition)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        guard !limitExceeded, !insecureRedirect else {
            lock.unlock()
            return
        }
        receivedBytes += Int64(data.count)
        guard receivedBytes <= maxBytes else {
            limitExceeded = true
            lock.unlock()
            dataTask.cancel()
            return
        }
        do {
            try fileHandle?.write(contentsOf: data)
        } catch {
            completionError = error
        }
        let shouldCancel = completionError != nil
        lock.unlock()
        if shouldCancel {
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard request.url?.scheme?.lowercased() == "https" else {
            lock.lock()
            insecureRedirect = true
            lock.unlock()
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        try? fileHandle?.close()
        fileHandle = nil
        let result: Result<(URL, URLResponse), Error>
        if insecureRedirect {
            result = .failure(AudioFetchError.insecureURL)
        } else if limitExceeded {
            result = .failure(AudioFetchError.tooLarge)
        } else if let error = completionError ?? error {
            result = .failure(error)
        } else if let response {
            result = .success((destinationURL, response))
        } else {
            result = .failure(AudioFetchError.fetchFailed)
        }
        let downloadSession = self.downloadSession
        self.downloadSession = nil
        lock.unlock()

        downloadSession?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }
}

public enum AudioFetchError: Error, Sendable, Equatable {
    case invalidExpectedHash
    case tooLarge
    case hashMismatch
    case insecureURL
    case fetchFailed
}

public protocol AudioFetching: Sendable {
    func withFetchedAudioFile<T: Sendable>(
        url: URL,
        expectedSHA256: String,
        maxBytes: Int,
        _ body: @Sendable (URL) async throws -> T
    ) async throws -> T
}

public struct URLSessionAudioFetcher: AudioFetching {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func withFetchedAudioFile<T: Sendable>(
        url: URL,
        expectedSHA256: String,
        maxBytes: Int,
        _ body: @Sendable (URL) async throws -> T
    ) async throws -> T {
        guard let expected = Self.normalizedSHA256(expectedSHA256) else {
            throw AudioFetchError.invalidExpectedHash
        }
        guard url.scheme?.lowercased() == "https" else {
            throw AudioFetchError.insecureURL
        }

        let (downloadedURL, response) = try await download(url: url, maxBytes: maxBytes)
        defer { try? FileManager.default.removeItem(at: downloadedURL) }
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw AudioFetchError.fetchFailed
        }
        if response.expectedContentLength > Int64(maxBytes) {
            throw AudioFetchError.tooLarge
        }

        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("tboperator-ai-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? fileManager.removeItem(at: directory) }

        let fileExtension = Self.safeExtension(url.pathExtension)
        let stagedURL = directory.appendingPathComponent("audio.\(fileExtension)")
        do {
            try fileManager.copyItem(at: downloadedURL, to: stagedURL)
            let values = try stagedURL.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize, size <= maxBytes else {
                throw AudioFetchError.tooLarge
            }
            guard try Self.sha256(of: stagedURL) == expected else {
                throw AudioFetchError.hashMismatch
            }
        } catch let error as AudioFetchError {
            throw error
        } catch {
            throw AudioFetchError.fetchFailed
        }
        return try await body(stagedURL)
    }

    private func download(url: URL, maxBytes: Int) async throws -> (URL, URLResponse) {
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tboperator-download-\(UUID().uuidString)")
        let delegate = SizeLimitingDataDelegate(
            maxBytes: maxBytes,
            destinationURL: destinationURL
        )
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData
        )
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let configuration = session.configuration
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        do {
            return try await delegate.download(request: request, configuration: configuration)
        } catch let error as AudioFetchError {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            audioFetchLogger.error("Audio download failed: \(String(describing: type(of: error)), privacy: .public)")
            throw AudioFetchError.fetchFailed
        }
    }

    public static func normalizedSHA256(_ value: String) -> String? {
        guard value.count == 64 else { return nil }
        let lowered = value.lowercased()
        guard lowered.allSatisfy({ $0.isHexDigit }) else { return nil }
        return lowered
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 64 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func safeExtension(_ value: String) -> String {
        guard !value.isEmpty,
              value.count <= 8,
              value.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            return "flac"
        }
        return value.lowercased()
    }
}
