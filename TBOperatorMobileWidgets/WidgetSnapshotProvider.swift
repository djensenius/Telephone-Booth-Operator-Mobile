//
//  WidgetSnapshotProvider.swift
//  TBOperatorMobileWidgets
//
//  Shared TimelineProvider used by every widget. Reads the snapshot
//  written by the main app from the App Group container and rebuilds
//  the timeline every 15 minutes. `WidgetCenter.reloadAllTimelines()`
//  is called by the app whenever a new snapshot is written, so the
//  15-minute fallback is only used when the app hasn't refreshed lately.
//  When a section is about to flip stale sooner than that, the provider
//  reloads at the transition instead so the "stale" chrome appears on
//  time. Extensions never authenticate or perform network requests.
//

import Foundation
import SwiftUI
import WidgetKit

struct WidgetSnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// True for gallery/placeholder entries built from `.placeholder`
    /// sample data, which must never render as stale.
    var isPlaceholder = false
}

struct WidgetSnapshotProvider: TimelineProvider {
    private static let refreshInterval: TimeInterval = 15 * 60
    private let readSnapshot: @Sendable () -> WidgetSnapshot?
    private let now: @Sendable () -> Date

    init(
        readSnapshot: @escaping @Sendable () -> WidgetSnapshot? = {
            WidgetSnapshotStore.read()
        },
        now: @escaping @Sendable () -> Date = {
            Date.now
        }
    ) {
        self.readSnapshot = readSnapshot
        self.now = now
    }

    func placeholder(in context: Context) -> WidgetSnapshotEntry {
        WidgetSnapshotEntry(date: now(), snapshot: .placeholder, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetSnapshotEntry) -> Void) {
        if context.isPreview {
            completion(WidgetSnapshotEntry(date: now(), snapshot: .placeholder, isPlaceholder: true))
        } else {
            completion(WidgetSnapshotEntry(date: now(), snapshot: readSnapshot()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetSnapshotEntry>) -> Void) {
        completion(makeTimeline())
    }

    func makeTimeline() -> Timeline<WidgetSnapshotEntry> {
        let currentDate = now()
        let entry = WidgetSnapshotEntry(date: currentDate, snapshot: readSnapshot())
        return Timeline(entries: [entry], policy: .after(nextReloadDate(for: entry)))
    }

    func nextReloadDate(for entry: WidgetSnapshotEntry) -> Date {
        let fallback = entry.date.addingTimeInterval(Self.refreshInterval)
        let nextStale = entry.staleTransitionDates(after: entry.date).first
        let reload = min(nextStale ?? fallback, fallback)
        return reload
    }
}

extension BoothState {
    var widgetDisplayName: String {
        switch self {
        case .idle: return "Idle"
        case .dialTone: return "Dial tone"
        case .dialing: return "Dialing"
        case .playingQuestion: return "Playing question"
        case .beep: return "Beep"
        case .recording: return "Recording"
        case .uploading: return "Uploading"
        case .playingMessage: return "Playing message"
        case .playingInstructions: return "Instructions"
        case .callUnavailable: return "Call unavailable"
        case .error: return "Error"
        case .unknown(let value): return value.capitalized
        }
    }

    var widgetSymbol: String {
        switch self {
        case .idle: return "phone.fill"
        case .dialTone, .dialing: return "phone.arrow.up.right"
        case .playingQuestion, .playingMessage, .playingInstructions:
            return "speaker.wave.2.fill"
        case .callUnavailable: return "phone.down.fill"
        case .beep: return "circle.fill"
        case .recording: return "record.circle"
        case .uploading: return "icloud.and.arrow.up"
        case .error: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var widgetTint: Color {
        switch self {
        case .idle: return .secondary
        case .error: return .red
        case .recording, .uploading, .playingMessage,
             .playingQuestion, .playingInstructions, .dialing,
             .beep, .dialTone, .callUnavailable:
            return .accentColor
        case .unknown: return .secondary
        }
    }
}
