//
//  AudioPlayerView.swift
//  TelephoneBoothOperatorMobile
//
//  Compact audio playback widget used inside MessageDetailView.
//

#if !os(watchOS) && !os(tvOS)

import SwiftUI

public struct AudioPlayerView: View {
    public let audio: AudioRef

    @State private var controller = AudioPlaybackController()

    public init(audio: AudioRef) {
        self.audio = audio
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack(spacing: Theme.Spacing.large) {
                Button {
                    controller.togglePlayPause()
                } label: {
                    Image(systemName: playButtonIcon)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
                .disabled(disablePlayButton)

                VStack(alignment: .leading, spacing: 4) {
                    Text(audio.url.lastPathComponent)
                        .font(Theme.Fonts.bodySmall)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                    HStack(spacing: Theme.Spacing.medium) {
                        Text(formatTime(controller.currentTime))
                            .monospacedDigit()
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("/")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(formatTime(displayDuration))
                            .monospacedDigit()
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(Theme.Colors.accent)

            if case let .failed(message) = controller.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.error)
            }
        }
        .onAppear {
            controller.load(url: audio.url, durationMs: audio.durationMs)
        }
        .onDisappear {
            controller.teardown()
        }
    }

    private var playButtonIcon: String {
        switch controller.state {
        case .playing: return "pause.circle.fill"
        case .loading: return "arrow.clockwise.circle"
        case .failed: return "exclamationmark.circle.fill"
        default: return "play.circle.fill"
        }
    }

    private var disablePlayButton: Bool {
        if case .failed = controller.state { return true }
        return false
    }

    private var displayDuration: TimeInterval {
        controller.duration > 0 ? controller.duration : Double(audio.durationMs ?? 0) / 1000.0
    }

    private var progress: Double {
        let total = displayDuration
        guard total > 0 else { return 0 }
        return min(1.0, controller.currentTime / total)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#endif
