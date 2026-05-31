//
//  QuestionAudioFile.swift
//  TelephoneBoothOperatorMobile
//
//  Encodes recorded or imported audio into the FLAC container the booth
//  pipeline expects, and computes the metadata (`sha256`, `sizeBytes`,
//  `durationMs`) required by the operator's upload + question-create
//  endpoints.
//

#if !os(watchOS) && !os(tvOS)

import AVFoundation
import CryptoKit
import Foundation

/// A FLAC-encoded audio clip staged on disk, ready to upload.
public struct QuestionAudioFile: Sendable, Equatable {
    public let url: URL
    public let data: Data
    public let sha256: String
    public let sizeBytes: Int
    public let durationMs: Int

    public init(url: URL, data: Data, sha256: String, sizeBytes: Int, durationMs: Int) {
        self.url = url
        self.data = data
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
        self.durationMs = durationMs
    }
}

public enum QuestionAudioError: LocalizedError {
    case emptyAudio
    case unreadableSource
    case tooLong(maxMinutes: Int)
    case encodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyAudio:
            return "The recording was empty. Please try again."
        case .unreadableSource:
            return "That file couldn't be read as audio."
        case .tooLong(let maxMinutes):
            return "That audio is too long. The maximum is \(maxMinutes) minutes."
        case .encodingFailed(let detail):
            return "Couldn't prepare the audio: \(detail)"
        }
    }
}

public enum QuestionAudioEncoder {
    /// Mirrors the operator's `MAX_AUDIO_DURATION_MS` (5 minutes) so we
    /// reject over-long clips before encoding and uploading them.
    public static let maxDurationMs = 300_000

    /// Transcodes any AVFoundation-readable audio file (WAV, CAF, m4a/AAC,
    /// AIFF, MP3, FLAC…) into a mono-or-stereo FLAC file in the temporary
    /// directory and returns its upload metadata. Runs off the main actor.
    public static func encodeToFLAC(source: URL) async throws -> QuestionAudioFile {
        try await Task.detached(priority: .userInitiated) {
            try encodeToFLACSync(source: source)
        }.value
    }

    private static func encodeToFLACSync(source: URL) throws -> QuestionAudioFile {
        let needsScopedAccess = source.startAccessingSecurityScopedResource()
        defer { if needsScopedAccess { source.stopAccessingSecurityScopedResource() } }

        let input: AVAudioFile
        do {
            input = try AVAudioFile(forReading: source)
        } catch {
            throw QuestionAudioError.unreadableSource
        }

        let format = input.processingFormat
        guard input.length > 0 else { throw QuestionAudioError.emptyAudio }

        let durationMs = Int((Double(input.length) / format.sampleRate) * 1000.0)
        guard durationMs <= maxDurationMs else {
            throw QuestionAudioError.tooLong(maxMinutes: maxDurationMs / 60_000)
        }

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("question-\(UUID().uuidString).flac")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatFLAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitDepthHintKey: 16
        ]

        do {
            try writeFLAC(input: input, format: format, settings: settings, to: outURL)
        } catch let error as QuestionAudioError {
            throw error
        } catch {
            throw QuestionAudioError.encodingFailed(error.localizedDescription)
        }

        let data: Data
        do {
            data = try Data(contentsOf: outURL)
        } catch {
            throw QuestionAudioError.encodingFailed(error.localizedDescription)
        }
        guard !data.isEmpty else { throw QuestionAudioError.emptyAudio }

        let digest = SHA256.hash(data: data)
        let sha256 = digest.map { String(format: "%02x", $0) }.joined()

        return QuestionAudioFile(
            url: outURL,
            data: data,
            sha256: sha256,
            sizeBytes: data.count,
            durationMs: max(durationMs, 1)
        )
    }

    private static func writeFLAC(
        input: AVAudioFile,
        format: AVAudioFormat,
        settings: [String: Any],
        to outURL: URL
    ) throws {
        // Match the writer's client (PCM) format to the reader's so
        // `write(from:)` accepts the buffers we read; Core Audio handles
        // the float-PCM → FLAC integer conversion.
        let output = try AVAudioFile(
            forWriting: outURL,
            settings: settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        let frameCapacity: AVAudioFrameCount = 8192
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            throw QuestionAudioError.encodingFailed("buffer allocation failed")
        }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
        }
    }
}

#endif
