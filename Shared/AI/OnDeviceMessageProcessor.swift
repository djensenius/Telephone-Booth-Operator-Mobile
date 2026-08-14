// swiftlint:disable file_length
//
//  OnDeviceMessageProcessor.swift
//  TelephoneBoothOperatorMobile
//

#if !os(watchOS) && !os(tvOS) && canImport(Speech) && canImport(FoundationModels)

import Foundation
import Observation
import os

public protocol MessageReviewPersisting: Sendable {
    func fetchMessage(id: String) async throws -> Message
    func fetchCurrentUserId() async throws -> String
    func submitTranscription(
        messageId: String,
        body: MessageTranscriptionRequest
    ) async throws -> Transcription
    func submitTranslation(
        messageId: String,
        body: MessageTranslationRequest
    ) async throws -> Transcription
    func submitModeration(
        messageId: String,
        body: MessageModerationRequest
    ) async throws -> Moderation
}

extension OperatorClient: MessageReviewPersisting {}

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@Observable
@MainActor
public final class OnDeviceMessageProcessor {
    public enum Stage: Equatable {
        case checkingAvailability
        case idle
        case fetchingAndTranscribing
        case translating
        case moderating
        case savingTranscript
        case savingTranslation
        case savingModeration
        case completed
        case failed(String)

        public var statusText: String? {
            switch self {
            case .checkingAvailability: return "Checking device support…"
            case .idle: return nil
            case .fetchingAndTranscribing: return "Downloading and transcribing audio…"
            case .translating: return "Translating the new transcript to English…"
            case .moderating: return "Generating a moderation suggestion…"
            case .savingTranscript: return "Saving transcript…"
            case .savingTranslation: return "Saving translation…"
            case .savingModeration: return "Saving suggestion…"
            case .completed: return "Transcript, translation, and suggestion saved."
            case .failed(let message): return message
            }
        }
    }

    private enum PersistenceStep: Equatable {
        case transcript
        case translation
        case moderation
    }

    struct SourceSnapshot: Equatable {
        let transcriptionId: String?
        let status: TranscriptionStatus?
        let text: String?
        let sha256: String?

        init(_ message: Message) {
            transcriptionId = message.latestTranscription?.id
            status = message.latestTranscription?.status
            text = Self.trimmed(message.latestTranscription?.text)
            sha256 = ReviewTextSnapshot.transcriptionSHA256(
                status: status,
                text: message.latestTranscription?.text
            )
        }

        private static func trimmed(_ value: String?) -> String? {
            value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private struct PendingResult {
        let messageId: String
        let baseline: SourceSnapshot
        let transcript: String
        let language: String?
        let transcriptionModel: String
        let translation: TranslationResult
        let moderation: ModerationVerdict
        let requestedById: String
        let expectedTranslationSha256: String?
        var step: PersistenceStep
        var transcriptionId: String?
    }

    public internal(set) var stage: Stage = .checkingAvailability
    public internal(set) var isAvailable = false

    public var isRunning: Bool {
        switch stage {
        case .checkingAvailability, .fetchingAndTranscribing, .translating, .moderating,
             .savingTranscript, .savingTranslation, .savingModeration:
            return true
        default:
            return false
        }
    }

    public var canRetryPersistence: Bool {
        if case .failed = stage {
            return pendingResult != nil
        }
        return false
    }

    @ObservationIgnored let audioFetcher: any AudioFetching
    @ObservationIgnored let transcriber: any AudioTranscribing
    @ObservationIgnored let translator: any TextTranslating
    @ObservationIgnored let moderator: any TextModerating
    @ObservationIgnored let availabilityCheck: @Sendable (Locale) async -> Bool
    @ObservationIgnored private let logger = Logger(
        subsystem: "org.davidjensenius.TelephoneBoothOperatorMobile",
        category: "OnDeviceReview"
    )
    @ObservationIgnored private var pendingResult: PendingResult?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var availabilityGeneration = 0

    public init(
        audioFetcher: any AudioFetching = URLSessionAudioFetcher(),
        transcriber: any AudioTranscribing = AppleSpeechTranscriber(),
        translator: any TextTranslating = AppleTranslationService(),
        moderator: any TextModerating = AppleModerationService(),
        availabilityCheck: @escaping @Sendable (Locale) async -> Bool = {
            await OnDeviceCapability.supportsFullPipeline(locale: $0)
        }
    ) {
        self.audioFetcher = audioFetcher
        self.transcriber = transcriber
        self.translator = translator
        self.moderator = moderator
        self.availabilityCheck = availabilityCheck
    }
}

extension OnDeviceMessageProcessor {
    public func refreshAvailability(sourceLanguage: String? = nil) async {
        availabilityGeneration += 1
        let requestGeneration = availabilityGeneration
        if stage == .idle || stage == .checkingAvailability {
            stage = .checkingAvailability
        }
        let normalizedLanguage = PromptSafety.normalizedLanguageTag(sourceLanguage)
        let trimmedLanguage = sourceLanguage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let available: Bool
        if trimmedLanguage?.isEmpty == false, normalizedLanguage == nil {
            available = false
        } else {
            let locale = normalizedLanguage.map(Locale.init(identifier:)) ?? .current
            available = await availabilityCheck(locale)
        }
        guard requestGeneration == availabilityGeneration else { return }
        isAvailable = available
        if stage == .checkingAvailability {
            stage = .idle
        }
    }

    public func process(
        message: Message,
        sourceLanguage: String?,
        client: any MessageReviewPersisting
    ) async {
        guard !isRunning else { return }
        generation += 1
        let currentGeneration = generation
        pendingResult = nil
        do {
            let selection = try Self.sourceLanguageSelection(sourceLanguage)
            stage = .checkingAvailability
            let available = await availabilityCheck(selection.locale)
            guard generation == currentGeneration else { return }
            isAvailable = available
            guard isAvailable else {
                throw OnDeviceServiceError.unavailable(
                    "The selected source language is not supported for on-device transcription."
                )
            }
            let (currentMessage, requestedById) = try await fetchCurrentContext(
                id: message.id,
                client: client,
                generation: currentGeneration
            )
            stage = .fetchingAndTranscribing
            let transcription = try await audioFetcher.withFetchedAudioFile(
                url: currentMessage.audio.url,
                expectedSHA256: currentMessage.audio.sha256,
                maxBytes: 100 * 1024 * 1024
            ) { [transcriber] fileURL in
                try await transcriber.transcribe(
                    audioFileURL: fileURL,
                    language: selection.language
                )
            }
            guard generation == currentGeneration else { return }
            guard case .speech(let transcript) = transcription else {
                fail("On-device transcription found no speech.")
                return
            }
            let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

            stage = .translating
            let translation = try await translator.translate(
                trimmedTranscript,
                sourceLanguage: sourceLanguage
            )
            guard generation == currentGeneration else { return }
            guard !translation.translatedText.isEmpty else {
                fail("On-device translation produced no text.")
                return
            }

            stage = .moderating
            let moderation = try await moderator.moderate(translation.translatedText)
            guard generation == currentGeneration else { return }

            pendingResult = PendingResult(
                messageId: currentMessage.id,
                baseline: SourceSnapshot(currentMessage),
                transcript: trimmedTranscript,
                language: translation.sourceLanguage ?? selection.language,
                transcriptionModel: "apple-speech-analyzer",
                translation: translation,
                moderation: moderation,
                requestedById: requestedById,
                expectedTranslationSha256: nil,
                step: .transcript,
                transcriptionId: nil
            )
            await persist(client: client)
        } catch {
            guard generation == currentGeneration else { return }
            fail(Self.describe(error))
        }
    }

    public func retryPersistence(client: any MessageReviewPersisting) async {
        guard pendingResult != nil, !isRunning else { return }
        await persist(client: client)
    }

    public func reset() {
        generation += 1
        pendingResult = nil
        stage = .idle
    }

    private func persist(client: any MessageReviewPersisting) async {
        guard var pending = pendingResult else { return }
        do {
            if pending.step == .transcript {
                stage = .savingTranscript
                let current = try await client.fetchMessage(id: pending.messageId)
                let currentSnapshot = SourceSnapshot(current)
                if currentSnapshot == pending.baseline {
                    let transcription = try await client.submitTranscription(
                        messageId: pending.messageId,
                        body: MessageTranscriptionRequest(
                            text: pending.transcript,
                            language: pending.language,
                            model: pending.transcriptionModel,
                            processDownstream: false,
                            expectedLatestTranscriptionId: currentSnapshot.transcriptionId,
                            expectedLatestTranscriptionSha256: currentSnapshot.sha256
                        )
                    )
                    pending.transcriptionId = transcription.id
                } else if let transcription = current.latestTranscription,
                          Self.matchesGeneratedTranscript(transcription, pending: pending) {
                    pending.transcriptionId = transcription.id
                } else {
                    pendingResult = nil
                    fail("This message changed during on-device processing. Run it again.")
                    return
                }
                pending.step = .translation
                pendingResult = pending
            }

            if pending.step == .translation {
                guard try await persistTranslation(&pending, client: client) else { return }
            }

            stage = .savingModeration
            let current = try await client.fetchMessage(id: pending.messageId)
            guard current.latestTranscription?.id == pending.transcriptionId,
                  Self.trimmed(current.latestTranscription?.translatedText)
                    == Self.trimmed(pending.translation.translatedText) else {
                pendingResult = nil
                fail("The translation changed before its suggestion could be saved.")
                return
            }
            if current.latestApplicableModeration?.transcriptionId == pending.transcriptionId,
               current.latestApplicableModeration?.requestedById == pending.requestedById,
               Self.matches(pending.moderation, current.latestApplicableModeration) {
                pendingResult = nil
                stage = .completed
                return
            }
            let moderationBody = MessageModerationRequest(
                transcriptionId: pending.transcriptionId,
                inputSha256: ReviewTextSnapshot.sha256(pending.translation.translatedText),
                flagged: pending.moderation.flagged,
                recommendation: pending.moderation.recommendation,
                maxScore: pending.moderation.maxScore,
                model: pending.moderation.model
            )
            _ = try await client.submitModeration(
                messageId: pending.messageId,
                body: moderationBody
            )
            pendingResult = nil
            stage = .completed
        } catch {
            pendingResult = pending
            fail(Self.describe(error))
        }
    }

    private func persistTranslation(
        _ pending: inout PendingResult,
        client: any MessageReviewPersisting
    ) async throws -> Bool {
        stage = .savingTranslation
        let current = try await client.fetchMessage(id: pending.messageId)
        guard current.latestTranscription?.id == pending.transcriptionId,
              Self.trimmed(current.latestTranscription?.text) == Self.trimmed(pending.transcript) else {
            pendingResult = nil
            fail("The transcript changed before its translation could be saved.")
            return false
        }
        if !Self.matchesGeneratedTranslation(current.latestTranscription, pending: pending) {
            guard ReviewTextSnapshot.sha256(
                current.latestTranscription?.translationSnapshotText
            ) == pending.expectedTranslationSha256 else {
                pendingResult = nil
                fail("The translation changed before the generated translation could be saved.")
                return false
            }
            _ = try await client.submitTranslation(
                messageId: pending.messageId,
                body: MessageTranslationRequest(
                    transcriptionId: pending.transcriptionId,
                    expectedTranslationSha256: pending.expectedTranslationSha256,
                    translatedText: pending.translation.translatedText,
                    translatedLanguage: pending.translation.targetLanguage,
                    model: pending.translation.model
                )
            )
        }
        pending.step = .moderation
        pendingResult = pending
        return true
    }

    private func fail(_ message: String) {
        stage = .failed(message)
        logger.error("On-device processing failed without logging message content")
    }

    private static func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sourceLanguageSelection(
        _ sourceLanguage: String?
    ) throws -> (language: String?, locale: Locale) {
        let language = PromptSafety.normalizedLanguageTag(sourceLanguage)
        let trimmed = sourceLanguage?.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed?.isEmpty == false, language == nil {
            throw OnDeviceServiceError.badRequest(
                "Enter a valid BCP-47 source language, such as fr-CA."
            )
        }
        return (language, language.map(Locale.init(identifier:)) ?? .current)
    }

    private func fetchCurrentContext(
        id: String,
        client: any MessageReviewPersisting,
        generation expectedGeneration: Int
    ) async throws -> (Message, String) {
        async let message = client.fetchMessage(id: id)
        async let requestedById = client.fetchCurrentUserId()
        let context = try await (message, requestedById)
        guard generation == expectedGeneration else { throw CancellationError() }
        return context
    }

    private static func matches(
        _ expected: ModerationVerdict,
        _ existing: Moderation?
    ) -> Bool {
        guard let existing else { return false }
        return existing.provider == .onDevice
            && existing.flagged == expected.flagged
            && existing.recommendation == expected.recommendation
            && existing.maxScore == expected.maxScore
            && existing.model == expected.model
    }

    private static func matchesGeneratedTranscript(
        _ existing: Transcription?,
        pending: PendingResult
    ) -> Bool {
        guard let existing else { return false }
        return existing.status == .succeeded
            && existing.provider == .onDevice
            && existing.requestedById == pending.requestedById
            && existing.model == pending.transcriptionModel
            && existing.language == pending.language
            && trimmed(existing.text) == trimmed(pending.transcript)
    }

    private static func matchesGeneratedTranslation(
        _ existing: Transcription?,
        pending: PendingResult
    ) -> Bool {
        existing?.translationStatus == .succeeded
            && trimmed(existing?.translatedText) == trimmed(pending.translation.translatedText)
            && existing?.translationProvider == .onDevice
            && existing?.translationModel == pending.translation.model
            && existing?.translatedLanguage == pending.translation.targetLanguage
    }

    private static func describe(_ error: any Error) -> String {
        if let audioError = error as? AudioFetchError {
            switch audioError {
            case .invalidExpectedHash, .hashMismatch:
                return "The message audio failed its integrity check."
            case .tooLarge:
                return "The message audio is too large to process on this device."
            case .insecureURL:
                return "The message audio URL is not secure."
            case .fetchFailed:
                return "The message audio could not be downloaded."
            }
        }
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return "On-device processing failed. Try again."
    }
}

public protocol MessageProcessingPersisting: Sendable {
    func fetchMessageProcessingSummary() async throws -> MessageProcessingSummary
    func claimMessageProcessing(
        _ request: MessageProcessingClaimRequest
    ) async throws -> MessageProcessingClaim?
    func heartbeatMessageProcessing(
        messageId: String,
        request: MessageProcessingHeartbeatRequest
    ) async throws -> MessageProcessingHeartbeatResponse
    func releaseMessageProcessing(messageId: String, leaseToken: String) async throws
    func failMessageProcessing(
        messageId: String,
        request: MessageProcessingFailRequest
    ) async throws -> MessageProcessingFailResponse
    func completeMessageProcessing(
        messageId: String,
        request: MessageProcessingCompleteRequest
    ) async throws -> MessageProcessingCompleteResponse
}

extension OperatorClient: MessageProcessingPersisting {}

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@Observable
@MainActor
public final class AutomaticMessageProcessingCoordinator {
    private enum ProcessingErrorAction {
        case continueRunning
        case stop
    }

    public enum Status: Equatable {
        case idle
        case processing(String)
        case paused
        case failed(String)

        public var text: String {
            switch self {
            case .idle: return "Waiting for eligible recordings"
            case .processing(let stage): return stage
            case .paused: return "Paused while the app is inactive"
            case .failed(let message): return message
            }
        }
    }

    public private(set) var status: Status = .idle
    public private(set) var summary: MessageProcessingSummary?
    public private(set) var currentMessageID: String?
    public private(set) var currentInstallation: Installation?

    public var isProcessing: Bool {
        if case .processing = status { return true }
        return false
    }

    public var canRetry: Bool {
        if case .failed = status { return true }
        return false
    }

    @ObservationIgnored private let client: any MessageProcessingPersisting
    @ObservationIgnored private let processor: OnDeviceMessageProcessor
    @ObservationIgnored private let socket: StatusSocket?
    @ObservationIgnored private let capabilityCheck: @Sendable (Locale) async -> Bool
    @ObservationIgnored private var workTask: Task<Void, Never>?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var socketTask: Task<Void, Never>?
    @ObservationIgnored private var claim: MessageProcessingClaim?
    @ObservationIgnored private var shouldRun = false
    @ObservationIgnored private var restartAfterLeaseLoss = false

    public init(
        client: any MessageProcessingPersisting = OperatorClient.shared,
        processor: OnDeviceMessageProcessor = OnDeviceMessageProcessor(),
        socket: StatusSocket? = StatusSocket.shared,
        capabilityCheck: @escaping @Sendable (Locale) async -> Bool = {
            await OnDeviceCapability.supportsFullPipeline(locale: $0)
        }
    ) {
        self.client = client
        self.processor = processor
        self.socket = socket
        self.capabilityCheck = capabilityCheck
    }

    public func setActive(_ active: Bool) {
        shouldRun = active
        if active {
            Task { [weak self] in
                guard let self else { return }
                let supported = await self.capabilityCheck(.current)
                guard self.shouldRun else { return }
                guard supported else {
                    self.status = .failed("On-device message processing is unavailable on this device.")
                    return
                }
                if case .paused = self.status { self.status = .idle }
                self.startWorkIfNeeded()
                self.startSocketIfNeeded()
            }
        } else {
            pause()
        }
    }

    public func retry() {
        guard shouldRun else { return }
        status = .idle
        startWorkIfNeeded()
    }

    public func refresh() {
        Task { [weak self] in
            await self?.refreshSummary()
        }
    }

    private func startWorkIfNeeded() {
        guard workTask == nil || workTask?.isCancelled == true else { return }
        workTask = Task { [weak self] in
            await self?.run()
        }
    }

    private func startSocketIfNeeded() {
        guard let socket else { return }
        guard socketTask == nil || socketTask?.isCancelled == true else { return }
        socketTask = Task { [weak self] in
            do {
                for try await envelope in socket.subscribe() {
                    guard !Task.isCancelled else { return }
                    switch envelope {
                    case .message, .work:
                        await self?.refreshSummary()
                    case .installation(let installation):
                        self?.currentInstallation = installation.isActive ? installation : nil
                        await self?.refreshSummary()
                    case .status, .system, .unknown:
                        break
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func pause() {
        workTask?.cancel()
        workTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socketTask?.cancel()
        socketTask = nil
        restartAfterLeaseLoss = false
        let leased = claim
        claim = nil
        currentMessageID = nil
        status = .paused
        if let leased {
            Task { [self] in
                await self.release(leased, reportingFailure: false)
            }
        }
    }

    private func run() async {
        defer {
            workTask = nil
            if restartAfterLeaseLoss, shouldRun {
                restartAfterLeaseLoss = false
                startWorkIfNeeded()
            }
        }
        while shouldRun && !Task.isCancelled {
            await refreshSummary()
            do {
                guard let leased = try await client.claimMessageProcessing(.init()) else {
                    status = .idle
                    try await Task.sleep(for: .seconds(20))
                    continue
                }
                guard shouldRun, !Task.isCancelled else {
                    await release(leased)
                    return
                }
                claim = leased
                currentMessageID = leased.message.id
                status = .processing(leased.needs.first?.displayName ?? "Processing")
                startHeartbeat(for: leased)

                let result = try await processor.process(claim: leased)
                guard shouldRun,
                      !Task.isCancelled,
                      claim?.leaseToken == leased.leaseToken else {
                    return
                }
                status = .processing("Saving results")
                _ = try await client.completeMessageProcessing(
                    messageId: leased.message.id,
                    request: result
                )
                finishLease()
            } catch is CancellationError {
                return
            } catch {
                switch await handleProcessingError(error) {
                case .continueRunning:
                    continue
                case .stop:
                    return
                }
            }
        }
    }

    private func handleProcessingError(_ error: any Error) async -> ProcessingErrorAction {
        guard !Task.isCancelled, shouldRun else { return .stop }
        let leased = claim
        finishLease()
        if isLeaseRefresh(error) {
            if let leased {
                await release(leased, reportingFailure: false)
            }
            status = .idle
            return .continueRunning
        }
        if isUnsupportedCapability(error) {
            shouldRun = false
            status = .paused
            if let leased {
                await release(leased, reportingFailure: false)
            }
            return .stop
        }
        guard let leased else {
            status = .failed(error.localizedDescription)
            return .stop
        }
        do {
            let result = try await client.failMessageProcessing(
                messageId: leased.message.id,
                request: MessageProcessingFailRequest(
                    leaseToken: leased.leaseToken,
                    errorCode: failureCode(for: error),
                    errorMessage: error.localizedDescription
                )
            )
            await refreshSummary()
            status = result.terminal
                ? .failed("Processing stopped after repeated failures.")
                : .failed(error.localizedDescription)
        } catch {
            status = isLeaseRefresh(error) ? .idle : .failed(error.localizedDescription)
        }
        return .stop
    }

    private func startHeartbeat(for leased: MessageProcessingClaim) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(120))
                    guard !Task.isCancelled,
                          self?.claim?.leaseToken == leased.leaseToken else {
                        return
                    }
                    _ = try await self?.client.heartbeatMessageProcessing(
                        messageId: leased.message.id,
                        request: MessageProcessingHeartbeatRequest(leaseToken: leased.leaseToken)
                    )
                } catch is CancellationError {
                    return
                } catch {
                    guard self?.claim?.leaseToken == leased.leaseToken else { return }
                    if self?.isLeaseRefresh(error) == true {
                        self?.claim = nil
                        self?.currentMessageID = nil
                        self?.status = .idle
                        self?.restartAfterLeaseLoss = true
                        self?.workTask?.cancel()
                    }
                    return
                }
            }
        }
    }

    private func finishLease() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        claim = nil
        currentMessageID = nil
    }

    private func release(
        _ leased: MessageProcessingClaim,
        reportingFailure: Bool = true
    ) async {
        do {
            try await client.releaseMessageProcessing(
                messageId: leased.message.id,
                leaseToken: leased.leaseToken
            )
        } catch {
            if reportingFailure, !isLeaseRefresh(error) {
                status = .failed(error.localizedDescription)
            }
        }
        await refreshSummary()
    }

    private func refreshSummary() async {
        do {
            summary = try await client.fetchMessageProcessingSummary()
        } catch {
            if !isProcessing, shouldRun {
                status = .failed(error.localizedDescription)
            }
        }
    }

    private func isLeaseRefresh(_ error: any Error) -> Bool {
        guard case let OperatorError.httpError(status, body) = error, status == 409 else {
            return false
        }
        return [
            "lease_lost",
            "stale_",
            "claim_snapshot_stale",
            "installation_ended",
            "review_requires_no_speech"
        ]
            .contains { body.contains($0) }
    }

    private func isUnsupportedCapability(_ error: any Error) -> Bool {
        guard let serviceError = error as? OnDeviceServiceError else { return false }
        if case .unavailable = serviceError { return true }
        return false
    }

    private func failureCode(for error: any Error) -> String {
        if error is OnDeviceServiceError { return "on_device_unavailable" }
        if error is AudioFetchError { return "audio_fetch_failed" }
        return "on_device_processing_failed"
    }
}

#endif
