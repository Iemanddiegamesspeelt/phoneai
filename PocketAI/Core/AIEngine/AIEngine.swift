import Foundation

// MARK: - AIEngine

/// The central orchestrator for all AI inference in Pocket AI Studio.
///
/// The AIEngine is the ONLY entry point the UI layer uses for inference.
/// It owns all sub-engines, the hardware profile, memory manager, thermal monitor,
/// and storage manager. It coordinates model loading, compatibility checks,
/// memory pre-flight, backend selection, and inference routing.
///
/// The UI never directly manages model internals.
public actor AIEngine {

    // MARK: - Dependencies

    public let hardwareDetector: HardwareDetector
    public let memoryManager: MemoryManager
    public let thermalMonitor: ThermalMonitor
    public let storageManager: StorageManager

    /// The detected hardware profile. Available after `initialize()`.
    public private(set) var hardwareProfile: HardwareCapabilityProfile?

    // MARK: - Engines

    private var textEngine: (any TextInferenceEngine)?
    private var imageEngine: (any ImageInferenceEngine)?
    private var visionEngine: (any VisionInferenceEngine)?
    private var speechEngine: (any SpeechInferenceEngine)?
    private var ttsEngine: (any TTSInferenceEngine)?
    private var audioEngine: (any AudioInferenceEngine)?
    private var videoEngine: (any VideoInferenceEngine)?

    // MARK: - State

    private var isInitialized = false
    private var activeInferenceModelId: String?
    private var eventContinuation: AsyncStream<EngineEvent>.Continuation?

    /// Stream of engine events for UI observation.
    public private(set) var events: AsyncStream<EngineEvent>!

    // MARK: - Init

    public init() {
        self.hardwareDetector = HardwareDetector()
        self.thermalMonitor = ThermalMonitor()
        self.storageManager = StorageManager()

        // Temporary profile for memory manager init — will be replaced in initialize()
        let tempProfile = HardwareCapabilityProfile(
            deviceModel: "Initializing",
            deviceName: "Initializing",
            iosVersion: "",
            totalRAMBytes: Int64(ProcessInfo.processInfo.physicalMemory),
            processorCount: ProcessInfo.processInfo.processorCount,
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount,
            processorFamily: .unknown,
            gpuName: nil,
            gpuMaxThreadsPerGroup: nil,
            metalSupported: false,
            metalGPUFamily: nil,
            neuralEngineAvailable: false,
            availableStorageBytes: 0,
            thermalState: .nominal,
            isLowPowerMode: false,
            isSimulator: false,
            capturedAt: Date()
        )
        self.memoryManager = MemoryManager(hardwareProfile: tempProfile)

        var continuation: AsyncStream<EngineEvent>.Continuation!
        self.events = AsyncStream { cont in
            continuation = cont
        }
        self.eventContinuation = continuation
    }

    // MARK: - Initialization

    /// Initialize the engine: detect hardware, start monitoring, register engines.
    /// Call this once at app startup.
    public func initialize() async {
        guard !isInitialized else { return }

        // 1. Detect hardware
        let profile = await hardwareDetector.detectCapabilities()
        hardwareProfile = profile

        eventContinuation?.yield(.log(
            "Hardware detected: \(profile.deviceModel), \(profile.totalRAMFormatted) RAM",
            level: .info
        ))

        // 2. Log capabilities
        eventContinuation?.yield(.log(profile.summary, level: .info))

        // 3. Start thermal monitoring
        Task {
            for await event in await thermalMonitor.events {
                eventContinuation?.yield(.thermalStateChanged(event.currentState))
                if let message = event.recommendation.message {
                    eventContinuation?.yield(.log(message, level: .warn))
                }
            }
        }

        // 4. Start memory pressure monitoring
        Task {
            for await event in await memoryManager.events {
                eventContinuation?.yield(event)
            }
        }

        isInitialized = true
        eventContinuation?.yield(.log("AIEngine initialized", level: .info))
    }

    // MARK: - Engine Registration

    /// Register a text inference engine.
    public func registerTextEngine(_ engine: any TextInferenceEngine) {
        self.textEngine = engine
    }

    /// Register an image inference engine.
    public func registerImageEngine(_ engine: any ImageInferenceEngine) {
        self.imageEngine = engine
    }

    /// Register a vision inference engine.
    public func registerVisionEngine(_ engine: any VisionInferenceEngine) {
        self.visionEngine = engine
    }

    /// Register a speech inference engine.
    public func registerSpeechEngine(_ engine: any SpeechInferenceEngine) {
        self.speechEngine = engine
    }

    /// Register a TTS inference engine.
    public func registerTTSEngine(_ engine: any TTSInferenceEngine) {
        self.ttsEngine = engine
    }

    /// Register an audio inference engine.
    public func registerAudioEngine(_ engine: any AudioInferenceEngine) {
        self.audioEngine = engine
    }

    /// Register a video inference engine.
    public func registerVideoEngine(_ engine: any VideoInferenceEngine) {
        self.videoEngine = engine
    }

    // MARK: - Compatibility

    /// Check whether a model is compatible with this device.
    public func checkCompatibility(model: ModelCatalogEntry) -> CompatibilityResult {
        guard let profile = hardwareProfile else {
            return .incompatible(reasons: ["Hardware not yet detected. Please wait for initialization."])
        }
        return CompatibilityChecker.check(model: model, hardware: profile)
    }

    /// Get a full compatibility summary for display.
    public func compatibilitySummary(model: ModelCatalogEntry) -> CompatibilitySummary? {
        guard let profile = hardwareProfile else { return nil }
        return CompatibilityChecker.compatibilitySummary(model: model, hardware: profile)
    }

    // MARK: - Backend Selection

    /// Select the optimal backend for a model.
    public func selectBackend(for model: ModelCatalogEntry) -> BackendSelection? {
        guard let profile = hardwareProfile else { return nil }
        return BackendSelector.selectBackend(for: model, hardware: profile)
    }

    // MARK: - Memory

    /// Get current memory snapshot.
    public func memorySnapshot() async -> MemoryManager.MemorySnapshot {
        await memoryManager.snapshot()
    }

    /// Check if a model can be loaded given current memory state.
    public func canLoadModel(_ model: ModelCatalogEntry) async -> CompatibilityResult {
        let estimate = MemoryEstimator.estimate(
            for: model.engineKind,
            fileSizeBytes: model.fileSizeBytes,
            quantization: model.quantization
        )
        return await memoryManager.canLoadModel(requiredBytes: estimate.requiredBytes)
    }

    // MARK: - Model Loading

    /// Load a model for inference.
    /// This performs the full pipeline: compatibility check → memory pre-flight →
    /// backend selection → engine load.
    public func loadModel(_ model: ModelCatalogEntry) async throws {
        guard let profile = hardwareProfile else {
            throw InferenceError(.modelLoadFailed, message: "Hardware not yet detected.")
        }

        // 1. Compatibility check
        let compatibility = checkCompatibility(model: model)
        guard compatibility.canRun else {
            if case .incompatible(let reasons) = compatibility {
                throw InferenceError(.modelTooLarge, message: reasons.joined(separator: " "))
            }
            throw InferenceError(.modelTooLarge)
        }

        // 2. Memory pre-flight
        let memoryCheck = await canLoadModel(model)
        guard memoryCheck.canRun else {
            if case .incompatible(let reasons) = memoryCheck {
                throw InferenceError(.modelTooLarge, message: reasons.joined(separator: " "))
            }
            throw InferenceError(.memoryAllocationFailed)
        }

        // 3. Check model is installed
        let modelPath = await storageManager.modelPath(for: model.id)
        guard await storageManager.isModelInstalled(model.id) else {
            throw InferenceError(.modelNotLoaded, message: "Model not installed. Download it first.")
        }

        // 4. Emit loading event
        eventContinuation?.yield(.modelLoading(modelId: model.id, progress: 0))

        // 5. Select backend
        let backend = BackendSelector.selectBackend(for: model, hardware: profile)
        eventContinuation?.yield(.log(
            "Selected backend: \(backend.backend.displayName) (\(backend.reason))",
            level: .info
        ))

        // 6. Load into appropriate engine
        do {
            switch model.engineKind {
            case .text:
                guard let engine = textEngine else {
                    throw InferenceError(.backendUnavailable, message: "Text engine not registered.")
                }
                try await engine.loadModel(from: modelPath, manifest: model)

            case .image:
                guard let engine = imageEngine else {
                    throw InferenceError(.backendUnavailable, message: "Image engine not registered.")
                }
                try await engine.loadModel(from: modelPath, manifest: model)

            case .vision:
                guard let engine = visionEngine else {
                    throw InferenceError(.backendUnavailable, message: "Vision engine not registered.")
                }
                try await engine.loadModel(from: modelPath, manifest: model)

            case .speech:
                guard let engine = speechEngine else {
                    throw InferenceError(.backendUnavailable, message: "Speech engine not registered.")
                }
                try await engine.loadModel(from: modelPath, manifest: model)

            case .tts:
                guard let engine = ttsEngine else {
                    throw InferenceError(.backendUnavailable, message: "TTS engine not registered.")
                }
                try await engine.loadModel(from: modelPath, manifest: model)

            case .audio:
                guard let engine = audioEngine else {
                    throw InferenceError(.backendUnavailable, message: "Audio engine not registered.")
                }
                try await engine.loadModel(from: modelPath, manifest: model)

            case .video:
                guard let engine = videoEngine else {
                    throw InferenceError(.backendUnavailable, message: "Video engine not registered.")
                }
                try await engine.loadModel(from: modelPath, manifest: model)
            }

            // 7. Register in memory manager
            let estimate = MemoryEstimator.estimate(
                for: model.engineKind,
                fileSizeBytes: model.fileSizeBytes,
                quantization: model.quantization
            )
            await memoryManager.registerModel(
                id: model.id,
                engineKind: model.engineKind,
                memoryBytes: estimate.requiredBytes
            )

            activeInferenceModelId = model.id
            eventContinuation?.yield(.modelLoaded(modelId: model.id, memoryBytes: estimate.requiredBytes))

        } catch {
            eventContinuation?.yield(.modelLoadFailed(
                modelId: model.id,
                error: (error as? InferenceError) ?? InferenceError(.modelLoadFailed, message: error.localizedDescription)
            ))
            throw error
        }
    }

    /// Unload a model from the specified engine.
    public func unloadModel(_ modelId: String, engineKind: ModelEngineKind) async throws {
        switch engineKind {
        case .text:    try await textEngine?.unloadModel()
        case .image:   try await imageEngine?.unloadModel()
        case .vision:  try await visionEngine?.unloadModel()
        case .speech:  try await speechEngine?.unloadModel()
        case .tts:     try await ttsEngine?.unloadModel()
        case .audio:   try await audioEngine?.unloadModel()
        case .video:   try await videoEngine?.unloadModel()
        }

        await memoryManager.unregisterModel(id: modelId)
        if activeInferenceModelId == modelId {
            activeInferenceModelId = nil
        }
        eventContinuation?.yield(.modelUnloaded(modelId: modelId))
    }

    /// Check whether the engine of a specific kind has a model loaded.
    public func isReady(engineKind: ModelEngineKind) async -> Bool {
        switch engineKind {
        case .text:    return await textEngine?.isModelLoaded() ?? false
        case .image:   return await imageEngine?.isModelLoaded() ?? false
        case .vision:  return await visionEngine?.isModelLoaded() ?? false
        case .speech:  return await speechEngine?.isModelLoaded() ?? false
        case .tts:     return await ttsEngine?.isModelLoaded() ?? false
        case .audio:   return await audioEngine?.isModelLoaded() ?? false
        case .video:   return await videoEngine?.isModelLoaded() ?? false
        }
    }

    /// Check the loaded model ID for a specific engine kind.
    public func loadedModelId(engineKind: ModelEngineKind) async -> String? {
        switch engineKind {
        case .text:    return await textEngine?.loadedModelId()
        case .image:   return await imageEngine?.loadedModelId()
        case .vision:  return await visionEngine?.loadedModelId()
        case .speech:  return await speechEngine?.loadedModelId()
        case .tts:     return await ttsEngine?.loadedModelId()
        case .audio:   return await audioEngine?.loadedModelId()
        case .video:   return await videoEngine?.loadedModelId()
        }
    }

    // MARK: - Text Inference

    /// Generate text using the loaded text model.
    public func generateText(
        prompt: String,
        systemPrompt: String? = nil,
        history: [ChatMessage] = [],
        parameters: TextGenerationParameters = .default
    ) async -> AsyncThrowingStream<TextGenerationEvent, Error> {
        guard let engine = textEngine else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: InferenceError(.backendUnavailable, message: "No text engine registered."))
            }
        }

        return await engine.generate(
            prompt: prompt,
            systemPrompt: systemPrompt,
            history: history,
            parameters: parameters
        )
    }

    // MARK: - Image Inference

    /// Generate images using the loaded image model.
    public func generateImage(
        prompt: String,
        negativePrompt: String? = nil,
        parameters: ImageGenerationParameters
    ) async -> AsyncThrowingStream<ImageGenerationEvent, Error> {
        guard let engine = imageEngine else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: InferenceError(.backendUnavailable, message: "No image engine registered."))
            }
        }
        return await engine.generate(prompt: prompt, negativePrompt: negativePrompt, parameters: parameters)
    }

    // MARK: - Vision Inference

    /// Analyze an image with a question query.
    public func analyzeVision(
        imageData: Data,
        query: String,
        parameters: TextGenerationParameters = .default
    ) async -> AsyncThrowingStream<TextGenerationEvent, Error> {
        guard let engine = visionEngine else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: InferenceError(.backendUnavailable, message: "No vision engine registered."))
            }
        }
        return await engine.analyze(imageData: imageData, query: query, parameters: parameters)
    }

    /// Classify an image with categories.
    public func classifyVision(imageData: Data) async throws -> [ClassificationResult] {
        guard let engine = visionEngine else {
            throw InferenceError(.backendUnavailable, message: "No vision engine registered.")
        }
        return try await engine.classify(imageData: imageData)
    }

    // MARK: - Speech Inference

    /// Transcribe speech audio file to text.
    public func transcribeSpeech(
        audioURL: URL,
        language: String? = nil,
        parameters: SpeechParameters = .init()
    ) async throws -> TranscriptionResult {
        guard let engine = speechEngine else {
            throw InferenceError(.backendUnavailable, message: "No speech engine registered.")
        }
        return try await engine.transcribe(audioURL: audioURL, language: language, parameters: parameters)
    }

    /// Transcribe streaming audio data.
    public func transcribeSpeechStream(
        audioStream: AsyncStream<Data>,
        language: String? = nil
    ) async -> AsyncThrowingStream<TranscriptionSegment, Error> {
        guard let engine = speechEngine else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: InferenceError(.backendUnavailable, message: "No speech engine registered."))
            }
        }
        return await engine.transcribeStream(audioStream: audioStream, language: language)
    }

    // MARK: - TTS Inference

    /// Synthesize speech audio from text.
    public func synthesizeSpeech(
        text: String,
        voiceId: String? = nil,
        parameters: TTSParameters = .init()
    ) async throws -> TTSResult {
        guard let engine = ttsEngine else {
            throw InferenceError(.backendUnavailable, message: "No TTS engine registered.")
        }
        return try await engine.synthesize(text: text, voiceId: voiceId, parameters: parameters)
    }

    /// Retrieve available TTS voices.
    public func availableTTSVoices() async -> [VoiceInfo] {
        guard let engine = ttsEngine else { return [] }
        return await engine.availableVoices()
    }

    // MARK: - Audio Inference

    /// Classify sounds in an audio clip.
    public func classifyAudio(audioURL: URL) async throws -> [ClassificationResult] {
        guard let engine = audioEngine else {
            throw InferenceError(.backendUnavailable, message: "No audio engine registered.")
        }
        return try await engine.classify(audioURL: audioURL)
    }

    // MARK: - Cancel

    /// Cancel any in-progress inference on the specified engine.
    public func cancelInference(engineKind: ModelEngineKind) async {
        switch engineKind {
        case .text:    await textEngine?.cancel()
        case .image:   await imageEngine?.cancel()
        case .vision:  await visionEngine?.cancel()
        case .speech:  await speechEngine?.cancel()
        case .tts:     await ttsEngine?.cancel()
        case .audio:   await audioEngine?.cancel()
        case .video:   await videoEngine?.cancel()
        }

        if let modelId = activeInferenceModelId {
            eventContinuation?.yield(.inferenceCancelled(modelId: modelId))
        }
    }

    /// Get the current thermal state.
    public func currentThermalState() async -> ProcessInfo.ThermalState {
        await thermalMonitor.currentState
    }
}
