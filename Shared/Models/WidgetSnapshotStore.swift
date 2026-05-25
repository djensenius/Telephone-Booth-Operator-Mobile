//
//  WidgetSnapshotStore.swift
//  TelephoneBoothOperatorMobile
//
//  Tiny shared-container store for WidgetSnapshot. The main app calls
//  `write(_:)` after every stats refresh; the widget extension calls
//  `read()` from its TimelineProvider. The store is process-safe and
//  doesn't require keychain access.
//

import Foundation
#if canImport(WidgetKit) && !os(tvOS)
import WidgetKit
#endif

public enum WidgetSnapshotStore {
    /// App Group identifier shared between the main app, widget extension,
    /// and watch app. Keep this in sync with the per-target entitlements.
    public static let appGroup = "group.org.davidjensenius.TelephoneBoothOperatorMobile"

    private static let filename = "widget-snapshot.json"
    private static let reloadTimestampFilename = "widget-last-reload"

    /// Minimum interval between `reloadAllTimelines()` calls (seconds).
    private static let reloadThrottleInterval: TimeInterval = 60

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Returns the App Group container URL for the snapshot file, or nil
    /// if App Groups aren't configured (e.g., on tvOS builds today).
    public static var snapshotURL: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else { return nil }
        return container.appendingPathComponent(filename, isDirectory: false)
    }

    private static var reloadTimestampURL: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else { return nil }
        return container.appendingPathComponent(reloadTimestampFilename, isDirectory: false)
    }

    /// Persist a snapshot for widget consumption. Writes are atomic so the
    /// widget never reads a partially-written file. Timeline reloads are
    /// skipped when the snapshot is unchanged, and throttled to at most
    /// once per 60 seconds to avoid storming WidgetKit.
    @discardableResult
    public static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = snapshotURL else { return false }

        // Change detection: skip write entirely if data hasn't changed.
        if let existing = read(), existing == snapshot {
            return true
        }

        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
            #if canImport(WidgetKit) && !os(tvOS)
            reloadTimelinesIfNeeded()
            #endif
            return true
        } catch {
            return false
        }
    }

    /// Returns the latest snapshot, or nil if none has been written yet.
    public static func read() -> WidgetSnapshot? {
        guard let url = snapshotURL else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(WidgetSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Reload Throttling

    #if canImport(WidgetKit) && !os(tvOS)
    private static func reloadTimelinesIfNeeded() {
        let now = Date()
        if let lastReload = readLastReloadDate(),
           now.timeIntervalSince(lastReload) < reloadThrottleInterval {
            return
        }
        WidgetCenter.shared.reloadAllTimelines()
        writeLastReloadDate(now)
    }
    #endif

    private static func readLastReloadDate() -> Date? {
        guard let url = reloadTimestampURL,
              let data = try? Data(contentsOf: url),
              let string = String(data: data, encoding: .utf8),
              let interval = TimeInterval(string) else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }

    private static func writeLastReloadDate(_ date: Date) {
        guard let url = reloadTimestampURL else { return }
        let string = String(date.timeIntervalSince1970)
        try? string.data(using: .utf8)?.write(to: url, options: [.atomic])
    }
}
