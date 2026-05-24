//
//  Question.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

public struct Question: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let prompt: String
    public let audio: AudioRef
    public let createdAt: Date
    public let retiredAt: Date?

    public init(
        id: String,
        prompt: String,
        audio: AudioRef,
        createdAt: Date,
        retiredAt: Date? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.audio = audio
        self.createdAt = createdAt
        self.retiredAt = retiredAt
    }
}

public struct QuestionList: Codable, Sendable, Equatable {
    public let items: [Question]
    public let nextCursor: String?

    public init(items: [Question], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

public struct EventList: Codable, Sendable, Equatable {
    public let items: [BoothEventRecord]
    public let nextCursor: String?

    public init(items: [BoothEventRecord], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}
