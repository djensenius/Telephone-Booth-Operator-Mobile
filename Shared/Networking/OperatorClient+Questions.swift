//
//  OperatorClient+Questions.swift
//  TelephoneBoothOperatorMobile
//
//  Questions lifecycle (list / create / activate / deactivate / retire)
//  plus the two-step audio upload used to attach a FLAC clip to a new
//  question. Split out of `OperatorClient` to keep that file focused.
//

import Foundation
import os

private let uploadsLogger = Logger(
    subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
    category: "OperatorClient.Uploads"
)

extension OperatorClient {
    /// `GET /v1/questions` — paged questions, newest first. By default the
    /// operator returns drafts + active (hiding archived); pass `status`
    /// to filter to a single lifecycle state.
    public func fetchQuestions(
        cursor: String? = nil,
        limit: Int = 50,
        status: QuestionStatus? = nil
    ) async throws -> QuestionList {
        if await usesDemoData {
            let filtered = status == nil
                ? DemoData.questions
                : DemoData.questions.filter { $0.status == status }
            return QuestionList(items: Array(filtered.prefix(limit)), nextCursor: nil)
        }
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let status { items.append(URLQueryItem(name: "status", value: status.rawValue)) }
        return try await get("/v1/questions", query: items)
    }

    /// `POST /v1/questions` — create a question referencing a previously
    /// uploaded audio file. New questions default to `draft` server-side.
    public func createQuestion(
        prompt: String,
        audioFileId: String,
        status: QuestionStatus? = nil
    ) async throws -> Question {
        if await usesDemoData { throw OperatorError.unauthenticated }
        return try await postJSON(
            "/v1/questions",
            body: QuestionCreate(prompt: prompt, audioFileId: audioFileId, status: status)
        )
    }

    /// `POST /v1/questions/{id}/activate` — publish a question so callers
    /// can be offered it. Also clears any prior retirement.
    public func activateQuestion(id: String) async throws -> Question {
        if await usesDemoData { return try demoQuestion(id: id, status: .active) }
        return try await postEmpty("/v1/questions/\(id)/activate")
    }

    /// `POST /v1/questions/{id}/deactivate` — return a question to `draft`
    /// so it is no longer offered to callers.
    public func deactivateQuestion(id: String) async throws -> Question {
        if await usesDemoData { return try demoQuestion(id: id, status: .draft) }
        return try await postEmpty("/v1/questions/\(id)/deactivate")
    }

    private func demoQuestion(id: String, status: QuestionStatus) throws -> Question {
        guard let existing = DemoData.questions.first(where: { $0.id == id }) else {
            throw OperatorError.unauthenticated
        }
        return Question(
            id: existing.id,
            prompt: existing.prompt,
            status: status,
            audio: existing.audio,
            createdAt: existing.createdAt,
            retiredAt: nil
        )
    }

    /// `DELETE /v1/questions/{id}` — soft-deletes (retires) a question.
    public func deleteQuestion(id: String) async throws {
        if await usesDemoData { return }
        try await delete("/v1/questions/\(id)")
    }

    /// `POST /v1/uploads/sas` — request a short-lived Azure blob SAS slot
    /// for an audio upload. For `question-audio` the response carries the
    /// `audioFileId` to reference when creating the question.
    public func requestUploadSlot(
        kind: String,
        sha256: String,
        sizeBytes: Int
    ) async throws -> UploadSlot {
        if await usesDemoData { throw OperatorError.unauthenticated }
        return try await postJSON(
            "/v1/uploads/sas",
            body: UploadSasRequest(kind: kind, sha256: sha256, sizeBytes: sizeBytes)
        )
    }

    /// Uploads FLAC bytes directly to an Azure blob SAS URL. This bypasses
    /// the operator (and its bearer auth) — the SAS token in the URL is the
    /// only credential — so it issues a raw `PUT` with the block-blob
    /// header Azure requires. The URL's query string is a write credential,
    /// so only host + path are logged.
    public func uploadAudioBlob(to url: URL, data: Data) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
        request.setValue("audio/flac", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let redacted = "\(url.host ?? "")\(url.path)"
        uploadsLogger.debug("→ PUT \(redacted, privacy: .public) \(data.count)B")
        let (body, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OperatorError.transport(URLError(.badServerResponse))
        }
        uploadsLogger.debug("← PUT \(redacted, privacy: .public) \(http.statusCode)")
        guard (200...299).contains(http.statusCode) else {
            throw OperatorError.httpError(
                status: http.statusCode,
                body: String(data: body, encoding: .utf8) ?? ""
            )
        }
    }
}
