import Foundation

// MARK: - InferenceEngine Protocol

/// The base protocol that all AI engines must conform to.
/// Each engine (Text, Image, Vision, Speech, TTS, Audio, Video) implements this
/// plus a modality-specific extension protocol.
public protocol InferenceEngine: Actor, Sendable {
    /// The kind of tasks this engine handles.
    var engineKind: ModelEngineKind { get }

    /// Load a model into memory, preparing it for inference.
    func loadModel(from path: URL, manifest: ModelCatalogEntry) async throws

    /// Unload the currently loaded model, freeing memory.
    func unloadModel() async throws

    /// Whether a model is currently loaded and ready.
    func isModelLoaded() async -> Bool

    /// The identifier of the currently loaded model, if any.
    func loadedModelId() async -> String?

    /// Check whether a model is compatible with the current device.
    func checkCompatibility(
        manifest: ModelCatalogEntry,
        hardware: HardwareCapabilityProfile
    ) -> CompatibilityResult

    /// Estimate memory requirements for a model.
    func estimateMemory(manifest: ModelCatalogEntry) -> MemoryEstimate

    /// Cancel any in-progress inference.
    func cancel() async
}

// MARK: - TextInferenceEngine

/// Protocol for engines that generate text (LLMs).
public protocol TextInferenceEngine: InferenceEngine {
    /// Generate text from a prompt, streaming tokens as they're produced.
    func generate(
        prompt: String,
        systemPrompt: String?,
        history: [ChatMessage],
        parameters: TextGenerationParameters
    ) -> AsyncThrowingStream<TextGenerationEvent, Error>
}

// MARK: - ImageInferenceEngine

/// Protocol for engines that generate images.
public protocol ImageInferenceEngine: InferenceEngine {
    /// Generate one or more images from a text prompt.
    func generate(
        prompt: String,
        negativePrompt: String?,
        parameters: ImageGenerationParameters
    ) -> AsyncThrowingStream<ImageGenerationEvent, Error>
}

// MARK: - VisionInferenceEngine

/// Protocol for engines that analyze images.
public protocol VisionInferenceEngine: InferenceEngine {
    /// Analyze an image with a text query (visual question answering).
    func analyze(
        imageData: Data,
        query: String,
        parameters: TextGenerationParameters
    ) -> AsyncThrowingStream<TextGenerationEvent, Error>

    /// Classify an image.
    func classify(imageData: Data) async throws -> [ClassificationResult]
}

// MARK: - SpeechInferenceEngine

/// Protocol for engines that transcribe audio to text.
public protocol SpeechInferenceEngine: InferenceEngine {
    /// Transcribe audio data to text.
    func transcribe(
        audioURL: URL,
        language: String?,
        parameters: SpeechParameters
    ) async throws -> TranscriptionResult

    /// Transcribe from streaming audio data.
    func transcribeStream(
        audioStream: AsyncStream<Data>,
        language: String?
    ) -> AsyncThrowingStream<TranscriptionSegment, Error>
}

// MARK: - TTSInferenceEngine

/// Protocol for engines that convert text to speech.
public protocol TTSInferenceEngine: InferenceEngine {
    /// Synthesize speech from text.
    func synthesize(
        text: String,
        voiceId: String?,
        parameters: TTSParameters
    ) async throws -> TTSResult

    /// List available voices.
    func availableVoices() async -> [VoiceInfo]
}

// MARK: - AudioInferenceEngine

/// Protocol for engines that analyze audio.
public protocol AudioInferenceEngine: InferenceEngine {
    /// Classify audio content.
    func classify(audioURL: URL) async throws -> [ClassificationResult]
}

// MARK: - VideoInferenceEngine

/// Protocol for engines that generate or process video.
public protocol VideoInferenceEngine: InferenceEngine {
    /// Generate a video.
    func generateVideo(prompt: String, parameters: AnyCodable) async throws -> URL
}

// MARK: - Supporting Types

/// A chat message in a conversation.
public struct ChatMessage: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let role: Role
    public var content: String
    public let timestamp: Date
    public var metrics: ChatMessageMetrics?

    public enum Role: String, Sendable, Codable, Equatable {
        case system    = "system"
        case user      = "user"
        case assistant = "assistant"
    }

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        metrics: ChatMessageMetrics? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.metrics = metrics
    }
}

/// Metrics attached to a generated message.
public struct ChatMessageMetrics: Sendable, Codable, Equatable {
    public let tokensPerSecond: Double
    public let totalTokens: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let generationTimeSeconds: Double
    public let backend: InferenceBackendKind

    public init(
        tokensPerSecond: Double = 0,
        totalTokens: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        generationTimeSeconds: Double = 0,
        backend: InferenceBackendKind = .cpu
    ) {
        self.tokensPerSecond = tokensPerSecond
        self.totalTokens = totalTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.generationTimeSeconds = generationTimeSeconds
        self.backend = backend
    }
}

/// Parameters specific to text generation.
public struct TextGenerationParameters: Sendable, Codable, Equatable {
    public var temperature: Double
    public var topP: Double
    public var topK: Int
    public var maxTokens: Int
    public var repetitionPenalty: Double
    public var contextLength: Int
    public var stopSequences: [String]

    public init(
        temperature: Double = 0.7,
        topP: Double = 0.9,
        topK: Int = 40,
        maxTokens: Int = 512,
        repetitionPenalty: Double = 1.1,
        contextLength: Int = 2048,
        stopSequences: [String] = []
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.maxTokens = maxTokens
        self.repetitionPenalty = repetitionPenalty
        self.contextLength = contextLength
        self.stopSequences = stopSequences
    }

    public static let `default` = TextGenerationParameters()
}

/// Events emitted during text generation.
public enum TextGenerationEvent: Sendable {
    case token(String)
    case metrics(InferenceMetrics)
    case done(totalOutput: String)
    case error(InferenceError)
}

/// Parameters specific to image generation.
public struct ImageGenerationParameters: Sendable {
    public var seed: Int?
    public var steps: Int
    public var guidanceScale: Double
    public var width: Int
    public var height: Int
    public var numberOfImages: Int

    public init(
        seed: Int? = nil,
        steps: Int = 20,
        guidanceScale: Double = 7.5,
        width: Int = 512,
        height: Int = 512,
        numberOfImages: Int = 1
    ) {
        self.seed = seed
        self.steps = steps
        self.guidanceScale = guidanceScale
        self.width = width
        self.height = height
        self.numberOfImages = numberOfImages
    }
}

/// Events emitted during image generation.
public enum ImageGenerationEvent: Sendable {
    case stepCompleted(step: Int, totalSteps: Int)
    case imageReady(imageData: Data, index: Int)
    case done
    case error(InferenceError)
}

/// Parameters for speech recognition.
public struct SpeechParameters: Sendable {
    public var language: String?
    public var timestamps: Bool
    public var translateToEnglish: Bool

    public init(language: String? = nil, timestamps: Bool = true, translateToEnglish: Bool = false) {
        self.language = language
        self.timestamps = timestamps
        self.translateToEnglish = translateToEnglish
    }
}

/// Result of a transcription.
public struct TranscriptionResult: Sendable {
    public let text: String
    public let segments: [TranscriptionSegment]
    public let language: String?
    public let duration: TimeInterval

    public init(text: String, segments: [TranscriptionSegment] = [], language: String? = nil, duration: TimeInterval = 0) {
        self.text = text
        self.segments = segments
        self.language = language
        self.duration = duration
    }
}

/// A segment of a transcription with timing.
public struct TranscriptionSegment: Sendable {
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval

    public init(text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// Parameters for text-to-speech.
public struct TTSParameters: Sendable {
    public var speed: Double
    public var pitch: Double

    public init(speed: Double = 1.0, pitch: Double = 1.0) {
        self.speed = speed
        self.pitch = pitch
    }
}

/// Result of TTS synthesis.
public struct TTSResult: Sendable {
    public let audioData: Data
    public let duration: TimeInterval
    public let sampleRate: Int

    public init(audioData: Data, duration: TimeInterval, sampleRate: Int = 22050) {
        self.audioData = audioData
        self.duration = duration
        self.sampleRate = sampleRate
    }
}

/// Information about an available TTS voice.
public struct VoiceInfo: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let language: String
    public let isDownloaded: Bool

    public init(id: String, name: String, language: String, isDownloaded: Bool = true) {
        self.id = id
        self.name = name
        self.language = language
        self.isDownloaded = isDownloaded
    }
}

/// A classification result (used by vision and audio engines).
public struct ClassificationResult: Sendable {
    public let label: String
    public let confidence: Double

    public init(label: String, confidence: Double) {
        self.label = label
        self.confidence = confidence
    }
}

// MARK: - Model Catalog Entry

/// A single model entry in the catalog.
/// Contains all metadata needed for downloading, compatibility checking, and display.
public struct ModelCatalogEntry: Sendable, Codable, Equatable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let developer: String
    public let engineKind: ModelEngineKind
    public let taskDescription: String
    public let fileSizeBytes: Int64
    public let downloadSizeBytes: Int64
    public let format: ModelManifestFormat
    public let quantization: ModelQuantization?
    public let minimumRAMBytes: Int64
    public let recommendedRAMBytes: Int64
    public let contextLength: Int?
    public let license: String
    public let downloadURL: String?
    public let homepage: String?
    public let description: String
    public let tags: [String]

    public init(
        id: String,
        name: String,
        developer: String = "",
        engineKind: ModelEngineKind = .text,
        taskDescription: String = "",
        fileSizeBytes: Int64 = 0,
        downloadSizeBytes: Int64 = 0,
        format: ModelManifestFormat = .gguf,
        quantization: ModelQuantization? = nil,
        minimumRAMBytes: Int64 = 0,
        recommendedRAMBytes: Int64 = 0,
        contextLength: Int? = nil,
        license: String = "",
        downloadURL: String? = nil,
        homepage: String? = nil,
        description: String = "",
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.developer = developer
        self.engineKind = engineKind
        self.taskDescription = taskDescription
        self.fileSizeBytes = fileSizeBytes
        self.downloadSizeBytes = downloadSizeBytes
        self.format = format
        self.quantization = quantization
        self.minimumRAMBytes = minimumRAMBytes
        self.recommendedRAMBytes = recommendedRAMBytes
        self.contextLength = contextLength
        self.license = license
        self.downloadURL = downloadURL
        self.homepage = homepage
        self.description = description
        self.tags = tags
    }

    /// Human-readable file size.
    public var fileSizeFormatted: String { formatBytes(fileSizeBytes) }

    /// Human-readable download size.
    public var downloadSizeFormatted: String { formatBytes(downloadSizeBytes) }

    /// Human-readable minimum RAM.
    public var minimumRAMFormatted: String { formatBytes(minimumRAMBytes) }
}
