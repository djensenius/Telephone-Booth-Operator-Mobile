//
//  WidgetSnapshotStore.swift
//  TelephoneBoothOperatorMobile
//

import Foundation
import os
#if canImport(WidgetKit) && !os(tvOS)
import WidgetKit
#endif

public struct WidgetSnapshotFileStore: Sendable {
    public let snapshotURL: URL

    public init(directoryURL: URL) {
        snapshotURL = directoryURL.appendingPathComponent(
            WidgetSnapshotStore.snapshotFilename,
            isDirectory: false
        )
    }

    public func read() throws -> WidgetSnapshot? {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: snapshotURL)
        return try Self.decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Returns true when the file changed.
    @discardableResult
    public func write(_ snapshot: WidgetSnapshot) throws -> Bool {
        let data = try Self.encoder.encode(snapshot)
        if FileManager.default.fileExists(atPath: snapshotURL.path),
           try Data(contentsOf: snapshotURL) == data {
            return false
        }
        try data.write(to: snapshotURL, options: [.atomic])
        return true
    }

    /// Returns true when a file was removed.
    @discardableResult
    public func clear() throws -> Bool {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            return false
        }
        try FileManager.default.removeItem(at: snapshotURL)
        return true
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum WidgetSnapshotStore {
    public static let appGroup = "group.org.davidjensenius.TelephoneBoothOperatorMobile"

    static let snapshotFilename = "widget-snapshot.json"
    private static let reloadTimestampFilename = "widget-last-reload"
    private static let reloadThrottleInterval: TimeInterval = 60
    private static let writesEnabled = OSAllocatedUnfairLock(initialState: false)
    private static let logger = Logger(
        subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
        category: "Widgets"
    )

    public static var snapshotURL: URL? {
        fileStore?.snapshotURL
    }

    @discardableResult
    public static func write(_ snapshot: WidgetSnapshot) -> Bool {
        writesEnabled.withLock { enabled in
            guard enabled else {
                logger.notice("Skipped widget snapshot write while signed out")
                return false
            }
            guard let store = fileStore else {
                logger.error("Widget App Group container is unavailable")
                return false
            }
            do {
                let changed = try store.write(snapshot)
                guard changed else { return true }
                #if canImport(WidgetKit) && !os(tvOS)
                reloadTimelinesIfNeeded()
                #endif
                return true
            } catch {
                logger.error(
                    "Widget snapshot write failed: \(error.localizedDescription, privacy: .public)"
                )
                return false
            }
        }
    }

    public static func read() -> WidgetSnapshot? {
        guard let store = fileStore else { return nil }
        do {
            return try store.read()
        } catch {
            logger.error(
                "Widget snapshot read failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    @discardableResult
    public static func clear() -> Bool {
        guard let store = fileStore else { return false }
        do {
            let changed = try store.clear()
            guard changed else { return true }
            removeReloadTimestamp()
            #if canImport(WidgetKit) && !os(tvOS)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
            return true
        } catch {
            logger.error(
                "Widget snapshot clear failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    @discardableResult
    static func disableWritesAndClear() -> Bool {
        writesEnabled.withLock { enabled in
            enabled = false
            return clear()
        }
    }

    static func enableWrites() {
        writesEnabled.withLock { $0 = true }
    }

    private static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        )
    }

    private static var fileStore: WidgetSnapshotFileStore? {
        containerURL.map(WidgetSnapshotFileStore.init(directoryURL:))
    }

    private static var reloadTimestampURL: URL? {
        containerURL?.appendingPathComponent(
            reloadTimestampFilename,
            isDirectory: false
        )
    }

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

    private static func readLastReloadDate() -> Date? {
        guard let url = reloadTimestampURL else { return nil }
        do {
            let data = try Data(contentsOf: url)
            guard let string = String(data: data, encoding: .utf8),
                  let interval = TimeInterval(string) else {
                logger.error("Widget reload timestamp is malformed")
                return nil
            }
            return Date(timeIntervalSince1970: interval)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            logger.error(
                "Widget reload timestamp read failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private static func writeLastReloadDate(_ date: Date) {
        guard let url = reloadTimestampURL,
              let data = String(date.timeIntervalSince1970).data(using: .utf8) else {
            return
        }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            logger.error(
                "Widget reload timestamp write failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
    #endif

    private static func removeReloadTimestamp() {
        guard let url = reloadTimestampURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            logger.error(
                "Widget reload timestamp clear failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
