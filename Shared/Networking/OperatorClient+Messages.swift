//
//  OperatorClient+Messages.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

extension OperatorClient {
    public func fetchMessages(
        status: MessageStatus? = nil,
        since: Date? = nil,
        limit: Int = 50
    ) async throws -> MessageList {
        if await usesDemoData {
            let messages = DemoData.messages.map { demoMessageOverrides[$0.id] ?? $0 }.filter { message in
                status == nil || message.status == status
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

    public func fetchMessage(id: String) async throws -> Message {
        if await usesDemoData { return demoMessageOverrides[id] ?? DemoData.message(id: id) }
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
        processDownstream: Bool = true,
        expectedLatestTranscriptionId: String?
    ) async throws -> Transcription {
        let body = MessageTranscriptionRequest(
            text: text,
            language: language,
            model: model,
            processDownstream: processDownstream,
            expectedLatestTranscriptionId: expectedLatestTranscriptionId
        )
        return try await submitTranscription(messageId: messageId, body: body)
    }

    public func submitTranscription(
        messageId: String,
        body: MessageTranscriptionRequest
    ) async throws -> Transcription {
        if await usesDemoData {
            let message = demoMessageOverrides[messageId] ?? DemoData.message(id: messageId)
            guard message.latestTranscription?.id == body.expectedLatestTranscriptionId else {
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
        translatedText: String,
        translatedLanguage: String? = "en",
        transcriptionId: String? = nil,
        expectedTranscriptionId: String? = nil,
        model: String? = nil
    ) async throws -> Transcription {
        let body = MessageTranslationRequest(
            transcriptionId: transcriptionId,
            expectedTranscriptionId: expectedTranscriptionId,
            translatedText: translatedText,
            translatedLanguage: translatedLanguage,
            model: model
        )
        return try await submitTranslation(messageId: messageId, body: body)
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
