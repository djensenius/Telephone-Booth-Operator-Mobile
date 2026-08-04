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
    private final class DownloadState: @unchecked Sendable {
        let maxBytes: Int64
        let destinationURL: URL
        let continuation: CheckedContinuation<(URL, URLResponse), Error>
        var fileHandle: FileHandle?
        var response: URLResponse?
        var receivedBytes: Int64 = 0
        var completionError: Error?
        var limitExceeded = false
        var insecureRedirect = false

        init(
            maxBytes: Int,
            destinationURL: URL,
            fileHandle: FileHandle,
            continuation: CheckedContinuation<(URL, URLResponse), Error>
        ) {
            self.maxBytes = Int64(maxBytes)
            self.destinationURL = destinationURL
            self.fileHandle = fileHandle
            self.continuation = continuation
        }
    }

    private let lock = NSLock()
    private var downloads: [Int: DownloadState] = [:]

    func download(
        session: URLSession,
        request: URLRequest,
        maxBytes: Int,
        destinationURL: URL
    ) async throws -> (URL, URLResponse) {
        guard FileManager.default.createFile(
            atPath: destinationURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw AudioFetchError.fetchFailed
        }
        let fileHandle = try FileHandle(forWritingTo: destinationURL)
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request)
            let state = DownloadState(
                maxBytes: maxBytes,
                destinationURL: destinationURL,
                fileHandle: fileHandle,
                continuation: continuation
            )
            lock.lock()
            downloads[task.taskIdentifier] = state
            lock.unlock()
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        guard let state = downloads[dataTask.taskIdentifier] else {
            lock.unlock()
            completionHandler(.cancel)
            return
        }
        state.response = response
        if response.expectedContentLength > state.maxBytes {
            state.limitExceeded = true
        }
        let disposition: URLSession.ResponseDisposition = state.limitExceeded ? .cancel : .allow
        lock.unlock()
        completionHandler(disposition)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        guard let state = downloads[dataTask.taskIdentifier],
              !state.limitExceeded,
              !state.insecureRedirect else {
            lock.unlock()
            return
        }
        state.receivedBytes += Int64(data.count)
        guard state.receivedBytes <= state.maxBytes else {
            state.limitExceeded = true
            lock.unlock()
            dataTask.cancel()
            return
        }
        do {
            try state.fileHandle?.write(contentsOf: data)
        } catch {
            state.completionError = error
        }
        let shouldCancel = state.completionError != nil
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
            downloads[task.taskIdentifier]?.insecureRedirect = true
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
        guard let state = downloads.removeValue(forKey: task.taskIdentifier) else {
            lock.unlock()
            return
        }
        try? state.fileHandle?.close()
        state.fileHandle = nil
        let result: Result<(URL, URLResponse), Error>
        if state.insecureRedirect {
            result = .failure(AudioFetchError.insecureURL)
        } else if state.limitExceeded {
            result = .failure(AudioFetchError.tooLarge)
        } else if let error = state.completionError ?? error {
            result = .failure(error)
        } else if let response = state.response {
            result = .success((state.destinationURL, response))
        } else {
            result = .failure(AudioFetchError.fetchFailed)
        }
        lock.unlock()
        state.continuation.resume(with: result)
    }
}

private final class BoundedAudioSession: @unchecked Sendable {
    private let delegate: SizeLimitingDataDelegate
    private let session: URLSession

    init(configuration: URLSessionConfiguration) {
        let delegate = SizeLimitingDataDelegate()
        self.delegate = delegate
        session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    deinit {
        session.invalidateAndCancel()
    }

    func download(
        request: URLRequest,
        maxBytes: Int,
        destinationURL: URL
    ) async throws -> (URL, URLResponse) {
        try await delegate.download(
            session: session,
            request: request,
            maxBytes: maxBytes,
            destinationURL: destinationURL
        )
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
    private static let sharedDownloadSession = makeDownloadSession(from: .shared)
    private let downloadSession: BoundedAudioSession

    public init(session: URLSession = .shared) {
        downloadSession = session === URLSession.shared
            ? Self.sharedDownloadSession
            : Self.makeDownloadSession(from: session)
    }

    private static func makeDownloadSession(from session: URLSession) -> BoundedAudioSession {
        let configuration = session.configuration
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return BoundedAudioSession(configuration: configuration)
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
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData
        )
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        do {
            return try await downloadSession.download(
                request: request,
                maxBytes: maxBytes,
                destinationURL: destinationURL
            )
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
