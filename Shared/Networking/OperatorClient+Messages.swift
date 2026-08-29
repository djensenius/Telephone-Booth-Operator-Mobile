//
//  OperatorClient+Messages.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

private struct DemoQuestionMessageCursor {
    let createdAt: TimeInterval
    let id: String
}

private func encodeDemoQuestionMessageCursor(_ message: Message) -> String {
    Data("\(message.createdAt.timeIntervalSince1970)\t\(message.id)".utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func decodeDemoQuestionMessageCursor(_ raw: String) -> DemoQuestionMessageCursor? {
    var base64 = raw
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let padding = (4 - base64.count % 4) % 4
    base64.append(String(repeating: "=", count: padding))
    guard let data = Data(base64Encoded: base64),
          let decoded = String(data: data, encoding: .utf8),
          let separator = decoded.firstIndex(of: "\t"),
          let createdAt = TimeInterval(decoded[..<separator]) else {
        return nil
    }
    let id = String(decoded[decoded.index(after: separator)...])
    guard !id.isEmpty else { return nil }
    return DemoQuestionMessageCursor(createdAt: createdAt, id: id)
}

private func isMessage(_ message: Message, olderThan cursor: DemoQuestionMessageCursor) -> Bool {
    let createdAt = message.createdAt.timeIntervalSince1970
    return createdAt < cursor.createdAt || (createdAt == cursor.createdAt && message.id < cursor.id)
}

private func newestMessageFirst(_ lhs: Message, _ rhs: Message) -> Bool {
    if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
    return lhs.id > rhs.id
}

extension OperatorClient {
    public func fetchMessages(
        status: MessageStatus? = nil,
        since: Date? = nil,
        limit: Int = 50
    ) async throws -> MessageList {
        if await usesDemoData {
            let messages = DemoData.messages.map { demoMessageOverrides[$0.id] ?? $0 }.filter { message in
                !demoDeletedMessageIDs.contains(message.id) && (status == nil || message.status == status)
            }
            return MessageList(items: Array(messages.prefix(limit)))
        }
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let status { query.append(URLQueryItem(name: "status", value: status.rawValue)) }
        if let since {
            query.append(URLQueryItem(name: "since", value: OperatorJSON.iso8601String(from: since)))
        }
        return try await get("/v1/messages", query: query)
    }

    public func fetchQuestionMessages(
        questionId: String,
        cursor: String? = nil,
        limit: Int = 50
    ) async throws -> MessagePage {
        if await usesDemoData {
            guard (1...200).contains(limit) else {
                throw OperatorError.httpError(status: 400, body: "invalid_limit")
            }
            var messages = DemoData.messages
                .map { demoMessageOverrides[$0.id] ?? $0 }
                .filter {
                    !demoDeletedMessageIDs.contains($0.id) && $0.questionId == questionId
                }
                .sorted(by: newestMessageFirst)
            if let cursor {
                guard let decoded = decodeDemoQuestionMessageCursor(cursor) else {
                    throw OperatorError.httpError(status: 400, body: "invalid_cursor")
                }
                messages = messages.filter { isMessage($0, olderThan: decoded) }
            }
            let pageItems = Array(messages.prefix(limit))
            let nextCursor = messages.count > limit
                ? pageItems.last.map(encodeDemoQuestionMessageCursor)
                : nil
            return MessagePage(items: pageItems, nextCursor: nextCursor)
        }
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await get("/v1/questions/\(questionId)/messages", query: query)
    }

    public func fetchMessage(id: String) async throws -> Message {
        if await usesDemoData {
            guard !demoDeletedMessageIDs.contains(id) else {
                throw OperatorError.httpError(status: 404, body: "not_found")
            }
            return demoMessageOverrides[id] ?? DemoData.message(id: id)
        }
        return try await get("/v1/messages/\(id)")
    }

    public func fetchTranscriptions(messageId: String) async throws -> TranscriptionList {
        if await usesDemoData {
            return TranscriptionList(items: DemoData.transcriptions(messageId: messageId))
        }
        return try await get("/v1/messages/\(messageId)/transcriptions")
    }

    public func submitTranscription(
        messageId: String,
        text: String,
        language: String?,
        model: String?,
        processDownstream: Bool = false,
        expectedLatestTranscription: Transcription?
    ) async throws -> Transcription {
        let body = MessageTranscriptionRequest(
            text: text,
            language: language,
            model: model,
            processDownstream: processDownstream,
            expectedLatestTranscriptionId: expectedLatestTranscription?.id,
            expectedLatestTranscriptionSha256: ReviewTextSnapshot.transcriptionSHA256(
                status: expectedLatestTranscription?.status,
                text: expectedLatestTranscription?.text
            )
        )
        return try await submitTranscription(messageId: messageId, body: body)
    }

    public func submitTranscription(
        messageId: String,
        body: MessageTranscriptionRequest
    ) async throws -> Transcription {
        if await usesDemoData {
            let message = demoMessageOverrides[messageId] ?? DemoData.message(id: messageId)
            let latest = message.latestTranscription
            guard latest?.id == body.expectedLatestTranscriptionId,
                  ReviewTextSnapshot.transcriptionSHA256(
                    status: latest?.status,
                    text: latest?.text
                  ) == body.expectedLatestTranscriptionSha256 else {
                throw OperatorError.httpError(status: 409, body: "stale_transcription")
            }
            let updated = Transcription(
                id: "\(messageId)-on-device-\(UUID().uuidString)",
                messageId: messageId,
                provider: .onDevice,
                model: body.model,
                status: .succeeded,
                text: body.text,
                language: body.language,
                durationMs: message.audio.durationMs,
                latencyMs: nil,
                error: nil,
                requestedById: DemoData.operatorProfile.id,
                createdAt: Date(),
                completedAt: Date()
            )
            demoMessageOverrides[messageId] = message.replacingLatestTranscription(updated)
            return updated
        }
        return try await postJSON("/v1/messages/\(messageId)/transcription", body: body)
    }

    public func submitTranslation(
        messageId: String,
        body: MessageTranslationRequest
    ) async throws -> Transcription {
        if await usesDemoData {
            return try applyDemoTranslation(messageId: messageId, body: body)
        }
        return try await postJSON("/v1/messages/\(messageId)/translation", body: body)
    }

    public func submitModeration(
        messageId: String,
        body: MessageModerationRequest
    ) async throws -> Moderation {
        if await usesDemoData {
            let message = demoMessageOverrides[messageId] ?? DemoData.message(id: messageId)
            let updated = Moderation(
                id: "\(messageId)-moderation-\(UUID().uuidString)",
                messageId: messageId,
                transcriptionId: body.transcriptionId,
                provider: .onDevice,
                model: body.model,
                status: .succeeded,
                flagged: body.flagged,
                recommendation: ModerationRecommendation(rawValue: body.recommendation),
                maxScore: body.maxScore,
                categories: nil,
                reasonSummary: body.reasonSummary,
                latencyMs: nil,
                error: nil,
                createdAt: Date(),
                completedAt: Date()
            )
            demoMessageOverrides[messageId] = message.replacingLatestModeration(updated)
            return updated
        }
        return try await postJSON("/v1/messages/\(messageId)/moderation", body: body)
    }

    public func decideMessage(
        id: String,
        decision: MessageDecision,
        notes: String? = nil
    ) async throws -> Message {
        let body = MessageDecisionRequest(decision: decision, notes: notes)
        if await usesDemoData {
            let updated = (demoMessageOverrides[id] ?? DemoData.message(id: id))
                .applyingDecision(decision, notes: body.notes)
            demoMessageOverrides[id] = updated
            return updated
        }
        return try await postJSON("/v1/messages/\(id)/decision", body: body)
    }

    /// `DELETE /v1/messages/{id}` — permanently removes a recording. This is
    /// intentionally distinct from a human reject decision, which preserves
    /// the recording and its audit history.
    public func deleteMessage(id: String) async throws {
        if await usesDemoData {
            demoDeletedMessageIDs.insert(id)
            demoMessageOverrides[id] = nil
            return
        }
        try await delete("/v1/messages/\(id)")
    }

    public func fetchMessageProcessingSummary() async throws -> MessageProcessingSummary {
        if await usesDemoData {
            return MessageProcessingSummary(
                queued: 0,
                leased: 0,
                terminal: 0,
                needs: .init(transcription: 0, translation: 0, moderation: 0, review: 0),
                generatedAt: Date()
            )
        }
        return try await get("/v1/message-processing/summary")
    }

    public func claimMessageProcessing(
        _ request: MessageProcessingClaimRequest = .init()
    ) async throws -> MessageProcessingClaim? {
        if await usesDemoData { return nil }
        let response: MessageProcessingClaimResponse = try await postJSON(
            "/v1/message-processing/claim",
            body: request
        )
        return response.claim
    }

    public func heartbeatMessageProcessing(
        messageId: String,
        request: MessageProcessingHeartbeatRequest
    ) async throws -> MessageProcessingHeartbeatResponse {
        try await postJSON("/v1/message-processing/\(messageId)/heartbeat", body: request)
    }

    public func releaseMessageProcessing(
        messageId: String,
        leaseToken: String
    ) async throws {
        if await usesDemoData { return }
        try await postNoContent(
            "/v1/message-processing/\(messageId)/release",
            body: MessageProcessingLeaseTokenRequest(leaseToken: leaseToken)
        )
    }

    public func failMessageProcessing(
        messageId: String,
        request: MessageProcessingFailRequest
    ) async throws -> MessageProcessingFailResponse {
        try await postJSON("/v1/message-processing/\(messageId)/fail", body: request)
    }

    public func completeMessageProcessing(
        messageId: String,
        request: MessageProcessingCompleteRequest
    ) async throws -> MessageProcessingCompleteResponse {
        try await postJSON("/v1/message-processing/\(messageId)/complete", body: request)
    }

    private func applyDemoTranslation(
        messageId: String,
        body: MessageTranslationRequest
    ) throws -> Transcription {
        let message = demoMessageOverrides[messageId] ?? DemoData.message(id: messageId)
        guard let transcription = message.latestTranscription else {
            throw OperatorError.httpError(status: 409, body: "no_succeeded_transcription")
        }
        let expectedId = body.transcriptionId ?? body.expectedTranscriptionId
        guard expectedId == nil || expectedId == transcription.id else {
            throw OperatorError.httpError(status: 409, body: "stale_transcription")
        }
        guard ReviewTextSnapshot.sha256(transcription.translationSnapshotText)
            == body.expectedTranslationSha256 else {
            throw OperatorError.httpError(status: 409, body: "stale_translation")
        }
        let updated = Transcription(
            id: transcription.id,
            messageId: transcription.messageId,
            provider: transcription.provider,
            model: transcription.model,
            status: transcription.status,
            text: transcription.text,
            language: transcription.language,
            durationMs: transcription.durationMs,
            latencyMs: transcription.latencyMs,
            error: transcription.error,
            requestedById: transcription.requestedById,
            createdAt: transcription.createdAt,
            completedAt: transcription.completedAt,
            translationStatus: .succeeded,
            translatedText: body.translatedText,
            translatedLanguage: body.translatedLanguage,
            translationProvider: body.transcriptionId == nil ? nil : .onDevice,
            translationModel: body.transcriptionId == nil ? nil : body.model,
            translationError: nil,
            translationLatencyMs: nil,
            translationCompletedAt: Date()
        )
        demoMessageOverrides[messageId] = message.replacingLatestTranscription(updated)
        return updated
    }
}
