//
//  Question.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

public struct Question: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let prompt: String
    public let status: QuestionStatus
    public let audio: AudioRef
    public let createdAt: Date
    public let retiredAt: Date?
    public let messageCount: Int?

    public init(
        id: String,
        prompt: String,
        status: QuestionStatus = .draft,
        audio: AudioRef,
        createdAt: Date,
        retiredAt: Date? = nil,
        messageCount: Int? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.status = status
        self.audio = audio
        self.createdAt = createdAt
        self.retiredAt = retiredAt
        self.messageCount = messageCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, prompt, status, audio, createdAt, retiredAt, messageCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        prompt = try container.decode(String.self, forKey: .prompt)
        // Older operator builds may omit `status`; default to `draft`.
        status = try container.decodeIfPresent(QuestionStatus.self, forKey: .status) ?? .draft
        audio = try container.decode(AudioRef.self, forKey: .audio)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        retiredAt = try container.decodeIfPresent(Date.self, forKey: .retiredAt)
        messageCount = try container.decodeIfPresent(Int.self, forKey: .messageCount)
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

extension Question {
    func updatingMessageCount(_ messageCount: Int?) -> Question {
        Question(
            id: id,
            prompt: prompt,
            status: status,
            audio: audio,
            createdAt: createdAt,
            retiredAt: retiredAt,
            messageCount: messageCount
        )
    }

    func preservingMessageCount(from previous: Question) -> Question {
        guard messageCount == nil else { return self }
        return updatingMessageCount(previous.messageCount)
    }
}
