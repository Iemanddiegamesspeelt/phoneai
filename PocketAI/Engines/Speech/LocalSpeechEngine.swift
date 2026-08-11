import Foundation
import AVFoundation

/// Local speech transcription engine conforming to `SpeechInferenceEngine`.
/// Simulates a local Whisper inference engine with proper timing, metrics, and transcription result formats.
public actor LocalSpeechEngine: SpeechInferenceEngine {

    public let engineKind: ModelEngineKind = .speech

    private var loadedModelId: String?
    private var modelPath: URL?
    private var isCancelled = false
    private var isGenerating = false

    public init() {}

    public func loadModel(from path: URL, manifest: ModelCatalogEntry) async throws {
        if loadedModelId != nil {
            try await unloadModel()
        }
        loadedModelId = manifest.id
        modelPath = path
    }

    public func unloadModel() async throws {
        loadedModelId = nil
        modelPath = nil
        isCancelled = false
        isGenerating = false
    }

    public func isModelLoaded() async -> Bool {
        loadedModelId != nil
    }

    public func loadedModelId() async -> String? {
        loadedModelId
    }

    public func checkCompatibility(
        manifest: ModelCatalogEntry,
        hardware: HardwareCapabilityProfile
    ) -> CompatibilityResult {
        CompatibilityChecker.check(model: manifest, hardware: hardware)
    }

    public func estimateMemory(manifest: ModelCatalogEntry) -> MemoryEstimate {
        MemoryEstimator.estimate(for: .speech, fileSizeBytes: manifest.fileSizeBytes)
    }

    // MARK: - File Transcription
    public func transcribe(
        audioURL: URL,
        language: String?,
        parameters: SpeechParameters
    ) async throws -> TranscriptionResult {
        guard loadedModelId != nil else {
            throw InferenceError(.modelNotLoaded, message: "No speech transcription model loaded.")
        }

        // Precheck: file exists?
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw InferenceError(.storageReadFailed, message: "Audio file not found at \(audioURL.lastPathComponent)")
        }

        isGenerating = true
        isCancelled = false

        // Simulate audio loading and features extraction (MFCC)
        try? await Task.sleep(for: .milliseconds(600))

        if isCancelled {
            isGenerating = false
            throw InferenceError(.inferenceCancelled)
        }

        // Simulate Whisper encoder/decoder passes
        try? await Task.sleep(for: .milliseconds(800))

        if isCancelled {
            isGenerating = false
            throw InferenceError(.inferenceCancelled)
        }

        let segments = [
            TranscriptionSegment(text: "Hello, this is a local audio recording transcription.", startTime: 0.0, endTime: 3.5),
            TranscriptionSegment(text: "It was processed completely offline using the on-device AI model.", startTime: 3.8, endTime: 8.2),
            TranscriptionSegment(text: "Apple Silicon Neural Engine and GPU acceleration were utilized.", startTime: 8.5, endTime: 12.0)
        ]

        let fullText = segments.map { $0.text }.joined(separator: " ")
        isGenerating = false

        return TranscriptionResult(
            text: fullText,
            segments: segments,
            language: language ?? "en",
            duration: 12.0
        )
    }

    // MARK: - Streaming Transcription
    public func transcribeStream(
        audioStream: AsyncStream<Data>,
        language: String?
    ) -> AsyncThrowingStream<TranscriptionSegment, Error> {
        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: InferenceError(.modelNotLoaded))
                    return
                }

                let loadedId = await self.loadedModelId
                guard loadedId != nil else {
                    continuation.finish(throwing: InferenceError(.modelNotLoaded, message: "No speech model loaded."))
                    return
                }

                await self.setGenerating(true)
                await self.setCancelled(false)

                var count = 0
                // Simulate receiving chunks and transcribing them on-the-fly
                for await _ in audioStream {
                    if await self.isCancelled {
                        continuation.finish(throwing: InferenceError(.inferenceCancelled))
                        await self.setGenerating(false)
                        return
                    }

                    count += 1
                    let segmentText = "Streaming segment \(count): speech detected and transcribed."
                    let startTime = Double(count - 1) * 3.0
                    let endTime = Double(count) * 3.0

                    continuation.yield(TranscriptionSegment(text: segmentText, startTime: startTime, endTime: endTime))
                    
                    // Simulate processing time
                    try? await Task.sleep(for: .milliseconds(100))
                }

                continuation.finish()
                await self.setGenerating(false)
            }
        }
    }

    public func cancel() async {
        isCancelled = true
    }

    private func setGenerating(_ value: Bool) {
        isGenerating = value
    }

    private func setCancelled(_ value: Bool) {
        isCancelled = value
    }
}
