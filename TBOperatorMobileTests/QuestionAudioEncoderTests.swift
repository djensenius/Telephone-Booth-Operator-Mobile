//
//  QuestionAudioEncoderTests.swift
//  TBOperatorMobileTests
//

import AVFoundation
import XCTest
@testable import TBOperatorMobile

final class QuestionAudioEncoderTests: XCTestCase {
    func testEncodesAIFFileToFLAC() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("question-\(UUID().uuidString).aif")
        defer { try? FileManager.default.removeItem(at: source) }

        try writeAIF(to: source)
        let encoded = try await QuestionAudioEncoder.encodeToFLAC(source: source)
        defer { try? FileManager.default.removeItem(at: encoded.url) }

        XCTAssertEqual(encoded.url.pathExtension, "flac")
        XCTAssertGreaterThan(encoded.sizeBytes, 0)
        XCTAssertGreaterThan(encoded.durationMs, 0)
        XCTAssertEqual(encoded.sha256.count, 64)
    }

    private func writeAIF(to url: URL) throws {
        let sampleRate = 44_100.0
        let frameCount: AVAudioFrameCount = 4_410
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: true
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0] else {
            XCTFail("Couldn't allocate an AIFF test buffer")
            return
        }

        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            samples[frame] = frame.isMultiple(of: 20) ? 0.25 : -0.25
        }
        try file.write(from: buffer)
    }
}
