//
//  Upload.swift
//  TelephoneBoothOperatorMobile
//
//  Wire types for the two-step audio upload flow shared by messages and
//  questions: request a short-lived Azure blob SAS slot, PUT the FLAC
//  bytes to it, then reference the returned `audioFileId` when creating
//  the owning record.
//

import Foundation

/// `POST /v1/uploads/sas` request body.
public struct UploadSasRequest: Codable, Sendable, Equatable {
    public let kind: String
    public let sha256: String
    public let sizeBytes: Int
    public let contentType: String

    public init(kind: String, sha256: String, sizeBytes: Int, contentType: String = "audio/flac") {
        self.kind = kind
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
        self.contentType = contentType
    }
}

/// `POST /v1/uploads/sas` response. `audioFileId` is only present for
/// `question-audio` uploads (the server pre-creates the `File` row).
public struct UploadSlot: Codable, Sendable, Equatable {
    public let uploadUrl: URL
    public let blobName: String
    public let expiresAt: Date
    public let audioFileId: String?

    public init(uploadUrl: URL, blobName: String, expiresAt: Date, audioFileId: String?) {
        self.uploadUrl = uploadUrl
        self.blobName = blobName
        self.expiresAt = expiresAt
        self.audioFileId = audioFileId
    }
}

/// `POST /v1/questions` request body.
public struct QuestionCreate: Codable, Sendable, Equatable {
    public let prompt: String
    public let audioFileId: String
    public let status: QuestionStatus?

    public init(prompt: String, audioFileId: String, status: QuestionStatus? = nil) {
        self.prompt = prompt
        self.audioFileId = audioFileId
        self.status = status
    }
}
