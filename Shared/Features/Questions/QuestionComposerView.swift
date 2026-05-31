//
//  QuestionComposerView.swift
//  TelephoneBoothOperatorMobile
//
//  Sheet for creating a new booth question. The operator records a prompt
//  or imports an audio file; it is transcoded to FLAC, uploaded to the
//  operator's SAS slot, and the question is created (optionally published
//  immediately).
//

#if !os(watchOS) && !os(tvOS)

import SwiftUI
import UniformTypeIdentifiers

struct QuestionComposerView: View {
    enum AudioStage: Equatable {
        case empty
        case recording
        case processing
        case ready(QuestionAudioFile)
        case failed(String)
    }

    private let client: OperatorClient
    private let onCreated: (Question) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var prompt: String = ""
    @State private var publishImmediately = true
    @State private var stage: AudioStage = .empty
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var isImporting = false
    @State private var recorder = QuestionAudioRecorder()

    init(client: OperatorClient, onCreated: @escaping (Question) -> Void) {
        self.client = client
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                promptSection
                audioSection
                publishSection
                if let submitError {
                    Section {
                        BannerView(message: submitError, kind: .error)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Question")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Create") { Task { await submit() } }
                            .disabled(!canSubmit)
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    // MARK: - Sections

    private var promptSection: some View {
        Section("Prompt") {
            TextField("What should the booth ask?", text: $prompt, axis: .vertical)
                .lineLimit(2...5)
                .textInputAutocapitalizationCompat()
        }
    }

    @ViewBuilder
    private var audioSection: some View {
        Section("Audio") {
            switch stage {
            case .empty, .failed:
                if case .failed(let message) = stage {
                    Text(message)
                        .font(Theme.Fonts.bodySmall)
                        .foregroundStyle(Theme.Colors.error)
                }
                recordButton
                Button {
                    isImporting = true
                } label: {
                    Label("Import Audio File", systemImage: "square.and.arrow.down")
                }
            case .recording:
                HStack {
                    Image(systemName: "waveform")
                        .foregroundStyle(Theme.Colors.error)
                        .symbolEffectPulse()
                    Text(recordingTime)
                        .font(Theme.Fonts.bodyMedium.monospacedDigit())
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Button("Stop") { Task { await stopRecording() } }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.Colors.error)
                }
            case .processing:
                HStack {
                    ProgressView()
                    Text("Preparing audio…")
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            case .ready(let file):
                readyAudio(file)
            }
        }
    }

    @ViewBuilder
    private func readyAudio(_ file: QuestionAudioFile) -> some View {
        if let duration = DurationFormatter.shortString(milliseconds: file.durationMs) {
            Label("Ready · \(duration)", systemImage: "checkmark.circle.fill")
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.success)
        } else {
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.success)
        }
        AudioPlayerView(
            audio: AudioRef(url: file.url, sha256: file.sha256, durationMs: file.durationMs)
        )
        Button(role: .destructive) {
            discardAudio(file)
        } label: {
            Label("Discard & Re-record", systemImage: "arrow.counterclockwise")
        }
    }

    private var recordButton: some View {
        Button {
            Task { await startRecording() }
        } label: {
            Label("Record", systemImage: "mic.fill")
        }
    }

    private var publishSection: some View {
        Section {
            Toggle("Publish immediately", isOn: $publishImmediately)
        } footer: {
            Text(publishImmediately
                 ? "The question becomes active and can be offered to callers right away."
                 : "The question is saved as a draft until you activate it.")
        }
    }

    // MARK: - Derived

    private var canSubmit: Bool {
        guard case .ready = stage else { return false }
        return !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var recordingTime: String {
        let total = Int(recorder.elapsed)
        return String(format: "%01d:%02d", total / 60, total % 60)
    }

    // MARK: - Audio actions

    private func startRecording() async {
        submitError = nil
        stage = .recording
        let started = await recorder.start()
        if !started {
            if case .failed(let message) = recorder.state {
                stage = .failed(message)
            } else {
                stage = .failed("Couldn't start recording.")
            }
        }
    }

    private func stopRecording() async {
        guard let url = recorder.stop() else {
            stage = .failed("Recording was empty.")
            return
        }
        await transcode(source: url, removeSource: true)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await transcode(source: url, removeSource: false) }
        case .failure(let error):
            stage = .failed(error.localizedDescription)
        }
    }

    private func transcode(source: URL, removeSource: Bool) async {
        stage = .processing
        // Recorded captures live in a temp file we own, so remove them once
        // we're done transcoding whether or not encoding succeeded.
        defer { if removeSource { try? FileManager.default.removeItem(at: source) } }
        do {
            let file = try await QuestionAudioEncoder.encodeToFLAC(source: source)
            stage = .ready(file)
        } catch {
            stage = .failed((error as? LocalizedError)?.errorDescription ?? "Couldn't prepare the audio.")
        }
    }

    private func discardAudio(_ file: QuestionAudioFile) {
        try? FileManager.default.removeItem(at: file.url)
        recorder.reset()
        stage = .empty
    }

    // MARK: - Submit

    private func submit() async {
        guard case .ready(let file) = stage else { return }
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        isSubmitting = true
        submitError = nil
        do {
            let slot = try await client.requestUploadSlot(
                kind: "question-audio",
                sha256: file.sha256,
                sizeBytes: file.sizeBytes
            )
            guard let audioFileId = slot.audioFileId else {
                throw QuestionComposerError.missingAudioFileId
            }
            try await client.uploadAudioBlob(to: slot.uploadUrl, data: file.data)
            let created = try await client.createQuestion(
                prompt: trimmedPrompt,
                audioFileId: audioFileId,
                status: publishImmediately ? .active : .draft
            )
            try? FileManager.default.removeItem(at: file.url)
            onCreated(created)
            dismiss()
        } catch {
            submitError = (error as? LocalizedError)?.errorDescription ?? "Couldn't create the question."
            isSubmitting = false
        }
    }
}

private enum QuestionComposerError: LocalizedError {
    case missingAudioFileId

    var errorDescription: String? {
        switch self {
        case .missingAudioFileId:
            return "The server didn't return an audio reference. Please try again."
        }
    }
}

private extension View {
    @ViewBuilder
    func textInputAutocapitalizationCompat() -> some View {
        #if os(iOS) || os(visionOS)
        self.textInputAutocapitalization(.sentences)
        #else
        self
        #endif
    }

    @ViewBuilder
    func symbolEffectPulse() -> some View {
        if #available(iOS 17.0, macOS 14.0, visionOS 1.0, *) {
            self.symbolEffect(.pulse, options: .repeating)
        } else {
            self
        }
    }
}

#endif
