//
//  InstructionComposerView.swift
//  TelephoneBoothOperatorMobile
//
//  Records or imports an instruction clip, transcodes it to FLAC, uploads
//  it, and creates a new instruction in the global pool.
//

#if !os(watchOS) && !os(tvOS)

import SwiftUI
import UniformTypeIdentifiers

struct InstructionComposerView: View {
    enum AudioStage: Equatable {
        case empty
        case recording
        case processing
        case ready(OperatorAudioFile)
        case failed(String)
    }

    private let client: OperatorClient
    private let onCreated: (Instruction) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var activateImmediately = true
    @State private var stage: AudioStage = .empty
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var isImporting = false
    @State private var recorder = OperatorAudioRecorder()

    init(client: OperatorClient, onCreated: @escaping (Instruction) -> Void) {
        self.client = client
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Description") {
                    TextField("What does this recording explain?", text: $description, axis: .vertical)
                        .lineLimit(2...5)
                        .onChange(of: description) { _, value in
                            if value.count > Instruction.descriptionMaxLength {
                                description = String(value.prefix(Instruction.descriptionMaxLength))
                            }
                        }
                }
                audioSection
                Section {
                    Toggle("Activate immediately", isOn: $activateImmediately)
                } footer: {
                    Text(
                        activateImmediately
                            ? "The booth can choose this clip as soon as it is uploaded."
                            : "The clip stays inactive until you activate it."
                    )
                }
                if let submitError {
                    Section {
                        BannerView(message: submitError, kind: .error)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Instruction")
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
                allowedContentTypes: [.audio, .aiff],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 500)
        #endif
        .interactiveDismissDisabled(isSubmitting)
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
                Button {
                    Task { await startRecording() }
                } label: {
                    Label("Record", systemImage: "mic.fill")
                }
                Button {
                    isImporting = true
                } label: {
                    Label("Import Audio File", systemImage: "square.and.arrow.down")
                }
            case .recording:
                HStack {
                    Image(systemName: "waveform")
                        .foregroundStyle(Theme.Colors.error)
                    Text(recordingTime)
                        .font(Theme.Fonts.bodyMedium.monospacedDigit())
                    Spacer()
                    Button("Stop") { Task { await stopRecording() } }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.Colors.error)
                }
            case .processing:
                HStack {
                    ProgressView()
                    Text("Preparing audio…")
                }
            case .ready(let file):
                readyAudio(file)
            }
        }
    }

    @ViewBuilder
    private func readyAudio(_ file: OperatorAudioFile) -> some View {
        if let duration = DurationFormatter.shortString(milliseconds: file.durationMs) {
            Label("Ready · \(duration)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.Colors.success)
        } else {
            Label("Ready", systemImage: "checkmark.circle.fill")
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

    private var canSubmit: Bool {
        if case .ready = stage { return true }
        return false
    }

    private var recordingTime: String {
        let total = Int(recorder.elapsed)
        return String(format: "%01d:%02d", total / 60, total % 60)
    }

    private func startRecording() async {
        submitError = nil
        stage = .recording
        guard await recorder.start() else {
            if case .failed(let message) = recorder.state {
                stage = .failed(message)
            } else {
                stage = .failed("Couldn't start recording.")
            }
            return
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
        defer { if removeSource { try? FileManager.default.removeItem(at: source) } }
        do {
            stage = .ready(try await OperatorAudioEncoder.encodeToFLAC(source: source))
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    private func discardAudio(_ file: OperatorAudioFile) {
        try? FileManager.default.removeItem(at: file.url)
        recorder.reset()
        stage = .empty
    }

    private func submit() async {
        guard case .ready(let file) = stage else { return }
        isSubmitting = true
        submitError = nil
        do {
            let slot = try await client.requestUploadSlot(
                kind: "instruction-audio",
                sha256: file.sha256,
                sizeBytes: file.sizeBytes
            )
            guard let audioFileId = slot.audioFileId else {
                throw InstructionComposerError.missingAudioFileId
            }
            try await client.uploadAudioBlob(to: slot.uploadUrl, data: file.data)
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            let created = try await client.createInstruction(
                description: trimmed.isEmpty ? nil : trimmed,
                audioFileId: audioFileId,
                status: activateImmediately ? .active : .inactive
            )
            try? FileManager.default.removeItem(at: file.url)
            onCreated(created)
            dismiss()
        } catch {
            submitError = error.localizedDescription
            isSubmitting = false
        }
    }
}

private enum InstructionComposerError: LocalizedError {
    case missingAudioFileId

    var errorDescription: String? {
        "The server didn't return an audio reference. Please try again."
    }
}

#endif
