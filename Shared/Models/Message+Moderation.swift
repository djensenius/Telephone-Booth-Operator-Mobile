//
//  Message+Moderation.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

extension Message {
    public var latestApplicableModeration: Moderation? {
        guard let moderation = latestModeration else { return nil }
        guard moderation.status == .succeeded else { return nil }
        guard let transcription = latestTranscription else { return nil }
        if let transcriptionId = moderation.transcriptionId,
           transcriptionId != transcription.id {
            return nil
        }
        let moderatedAt = moderation.completedAt ?? moderation.createdAt
        let transcribedAt = transcription.completedAt ?? transcription.createdAt
        guard moderatedAt >= transcribedAt else { return nil }
        if let translatedAt = transcription.translationCompletedAt {
            guard moderatedAt >= translatedAt else { return nil }
        }
        return moderation
    }
}
