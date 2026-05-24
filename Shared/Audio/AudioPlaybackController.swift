//
//  AudioPlaybackController.swift
//  TelephoneBoothOperatorMobile
//
//  Thin wrapper around AVPlayer that exposes an @Observable interface
//  for SwiftUI views. FLAC playback works directly via AVPlayer on
//  iOS 11+, iPadOS 11+, macOS 10.13+, watchOS 4+, tvOS 11+, and
//  visionOS — no extra decoding is required.
//
//  This controller intentionally streams from the short-lived SAS URL
//  returned by the operator API rather than downloading to disk, so
//  the UI feels responsive on the first tap and we don't hold long-
//  lived copies of recorded audio on the device.
//

#if !os(watchOS) && !os(tvOS)

import AVFoundation
import Combine
import Foundation
import Observation

@MainActor
@Observable
public final class AudioPlaybackController {
    public enum PlaybackState: Equatable {
        case idle
        case loading
        case playing
        case paused
        case finished
        case failed(String)
    }

    public private(set) var state: PlaybackState = .idle
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    public init() {}

    public func load(url: URL, durationMs: Int?) {
        teardown()
        state = .loading
        if let durationMs {
            duration = Double(durationMs) / 1000.0
        }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds.isFinite ? max(0, time.seconds) : 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = seconds
                if let itemDuration = self.player?.currentItem?.duration.seconds,
                   itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.state = .finished
                self?.currentTime = self?.duration ?? 0
            }
        }
    }

    public func play() {
        guard let player else { return }
        if case .finished = state {
            player.seek(to: .zero)
        }
        player.play()
        state = .playing
    }

    public func pause() {
        player?.pause()
        state = .paused
    }

    public func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .paused, .finished, .idle, .loading: play()
        case .failed: break
        }
    }

    public func seek(to seconds: TimeInterval) {
        guard let player else { return }
        let bounded = max(0, seconds.isFinite ? seconds : 0)
        player.seek(to: CMTime(seconds: bounded, preferredTimescale: 600))
        currentTime = bounded
    }

    public func teardown() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        timeObserver = nil
        endObserver = nil
        player?.pause()
        player = nil
        currentTime = 0
        duration = 0
        state = .idle
    }
}

#endif
