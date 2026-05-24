//
//  WidgetSnapshotProvider.swift
//  TBOperatorMobileWidgets
//
//  Shared TimelineProvider used by every widget. Reads the snapshot
//  written by the main app from the App Group container and rebuilds
//  the timeline every 15 minutes. WidgetCenter.reloadAllTimelines() is
//  called by the app whenever a new snapshot is written, so the 15-
//  minute fallback is only used when the app hasn't refreshed lately.
//

import Foundation
import SwiftUI
import WidgetKit

struct WidgetSnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct WidgetSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetSnapshotEntry {
        WidgetSnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetSnapshotEntry) -> Void) {
        let entry = WidgetSnapshotEntry(
            date: .now,
            snapshot: WidgetSnapshotStore.read() ?? .placeholder
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetSnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.read()
        let entry = WidgetSnapshotEntry(date: .now, snapshot: snapshot)
        let refresh = Date.now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
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
        case .error: return "Error"
        }
    }

    var widgetSymbol: String {
        switch self {
        case .idle: return "phone.fill"
        case .dialTone, .dialing: return "phone.arrow.up.right"
        case .playingQuestion, .playingMessage, .playingInstructions:
            return "speaker.wave.2.fill"
        case .beep: return "circle.fill"
        case .recording: return "record.circle"
        case .uploading: return "icloud.and.arrow.up"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var widgetTint: Color {
        switch self {
        case .idle: return .secondary
        case .error: return .red
        case .recording, .uploading, .playingMessage,
             .playingQuestion, .playingInstructions, .dialing,
             .beep, .dialTone:
            return .accentColor
        }
    }
}
