//
//  CallInProgressAttributes.swift
//  TelephoneBoothOperatorMobile
//
//  ActivityAttributes for the "call in progress" Live Activity. Shared
//  between the widget extension (which renders the UI) and the main app
//  (which starts/updates/ends the activity via LiveActivityManager).
//

#if canImport(ActivityKit) && !os(macOS)
import ActivityKit
import Foundation

public struct CallInProgressAttributes: ActivityAttributes, Sendable {
    /// Static context set when the activity is started.
    public let boothName: String
    public let sessionId: String

    public init(boothName: String, sessionId: String) {
        self.boothName = boothName
        self.sessionId = sessionId
    }

    /// Dynamic state pushed via content updates.
    public struct ContentState: Codable, Hashable, Sendable {
        public let boothState: String
        public let startedAt: Date
        public let digitsDialed: String?
        public let installationState: InstallationState?
        public var showsCallTimer: Bool { installationState != .betweenExhibitions }

        public init(
            boothState: String,
            startedAt: Date,
            digitsDialed: String? = nil,
            installationState: InstallationState? = nil
        ) {
            self.boothState = boothState
            self.startedAt = startedAt
            self.digitsDialed = digitsDialed
            self.installationState = installationState
        }

        /// Human-readable label for the current booth state.
        public var stateDisplayName: String {
            if installationState == .betweenExhibitions { return "Between exhibitions" }
            var words: [String] = []
            var currentWord = ""

            for character in boothState {
                if character == "_" {
                    if !currentWord.isEmpty {
                        words.append(currentWord)
                        currentWord.removeAll(keepingCapacity: true)
                    }
                    continue
                }

                if character.isUppercase, currentWord.last?.isLowercase == true {
                    words.append(currentWord)
                    currentWord.removeAll(keepingCapacity: true)
                }

                currentWord.append(character)
            }

            if !currentWord.isEmpty {
                words.append(currentWord)
            }

            return words
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }
}
#endif
