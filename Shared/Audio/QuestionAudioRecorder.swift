//
//  QuestionAudioRecorder.swift
//  TelephoneBoothOperatorMobile
//
//  Records a question prompt from the device microphone to a temporary
//  PCM file. The recording is later transcoded to FLAC by
//  `QuestionAudioEncoder` so the record and import paths share one
//  upload pipeline.
//

#if !os(watchOS) && !os(tvOS)

import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
public final class QuestionAudioRecorder: NSObject, AVAudioRecorderDelegate {
    public enum RecorderState: Equatable {
        case idle
        case recording
        case finished
        case failed(String)
    }

    public private(set) var state: RecorderState = .idle
    public private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var timer: Timer?

    public override init() { super.init() }

    public var isRecording: Bool { state == .recording }

    /// Requests microphone access and begins recording. Returns `false`
    /// (with `state == .failed`) if permission is denied or setup fails.
    @discardableResult
    public func start() async -> Bool {
        guard await requestPermission() else {
            state = .failed("Microphone access is required to record a question.")
            return false
        }

        #if os(iOS) || os(visionOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            state = .failed("Couldn't start the audio session.")
            return false
        }
        #endif

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("question-rec-\(UUID().uuidString).caf")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            guard recorder.record() else {
                state = .failed("Couldn't start recording.")
                return false
            }
            self.recorder = recorder
            self.fileURL = url
            elapsed = 0
            state = .recording
            startTimer()
            return true
        } catch {
            state = .failed("Couldn't start recording.")
            return false
        }
    }

    /// Stops recording and returns the URL of the captured PCM file.
    @discardableResult
    public func stop() -> URL? {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        #if os(iOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
        if state == .recording { state = .finished }
        return fileURL
    }

    public func reset() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
        elapsed = 0
        state = .idle
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder, recorder.isRecording else { return }
                self.elapsed = recorder.currentTime
            }
        }
        self.timer = timer
    }

    private func requestPermission() async -> Bool {
        #if os(iOS) || os(visionOS)
        return await AVAudioApplication.requestRecordPermission()
        #else
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
        #endif
    }

    public nonisolated func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder,
        successfully flag: Bool
    ) {
        Task { @MainActor in
            if !flag { self.state = .failed("Recording failed.") }
        }
    }
}

#endif
