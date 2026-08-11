import Foundation

// MARK: - InferenceTypes.swift
// Shared inference types used across Core and Engine layers.
// Keep deps minimal (Foundation-only).

// MARK: - InferenceParameters

/// Unified parameters for all inference types.
/// Each engine reads the subset relevant to its modality.
public struct InferenceParameters: Sendable, Codable, Equatable {

    // MARK: Text generation
    public var temperature: Double
    public var topP: Double
    public var topK: Int
    public var maxTokens: Int?
    public var repetitionPenalty: Double
    public var contextLength: Int
    public var stopSequences: [String]

    // MARK: Image generation
    public var negativePrompt: String?
    public var seed: Int?
    public var steps: Int?
    public var guidanceScale: Double?
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var numberOfImages: Int?

    // MARK: Audio / speech
    public var speed: Double?
    public var pitch: Double?
    public var voiceIdentifier: String?
    public var language: String?

    // MARK: Shared
    public var stream: Bool
    public var priority: InferencePriority

    public init(
        temperature: Double = 0.7,
        topP: Double = 0.9,
        topK: Int = 40,
        maxTokens: Int? = 512,
        repetitionPenalty: Double = 1.1,
        contextLength: Int = 2048,
        stopSequences: [String] = [],
        negativePrompt: String? = nil,
        seed: Int? = nil,
        steps: Int? = nil,
        guidanceScale: Double? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        numberOfImages: Int? = nil,
        speed: Double? = nil,
        pitch: Double? = nil,
        voiceIdentifier: String? = nil,
        language: String? = nil,
        stream: Bool = true,
        priority: InferencePriority = .balanced
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.maxTokens = maxTokens
        self.repetitionPenalty = repetitionPenalty
        self.contextLength = contextLength
        self.stopSequences = stopSequences
        self.negativePrompt = negativePrompt
        self.seed = seed
        self.steps = steps
        self.guidanceScale = guidanceScale
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.numberOfImages = numberOfImages
        self.speed = speed
        self.pitch = pitch
        self.voiceIdentifier = voiceIdentifier
        self.language = language
        self.stream = stream
        self.priority = priority
    }

    public static let `default` = InferenceParameters()

    /// Text-optimized preset with higher temperature for creative output.
    public static let creative = InferenceParameters(temperature: 1.0, topP: 0.95, topK: 50)

    /// Text-optimized preset with lower temperature for precise output.
    public static let precise = InferenceParameters(temperature: 0.3, topP: 0.8, topK: 20)
}

// MARK: - InferencePriority

public enum InferencePriority: String, Sendable, Codable, Equatable {
    case low         = "low"
    case balanced    = "balanced"
    case high        = "high"
    case interactive = "interactive"
    case background  = "background"
}

// MARK: - InferenceRequestState

/// State machine for tracking an inference request through its lifecycle.
public enum InferenceRequestState: Equatable, Sendable {
    case idle
    case validatingRequest
    case checkingCompatibility
    case optimizingModel
    case loadingModel
    case tokenizing
    case inferring(progress: Double)
    case sampling
    case streaming
    case finalizing
    case completed
    case failed(InferenceError)
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        default: return false
        }
    }

    public var isInProgress: Bool {
        switch self {
        case .validatingRequest, .checkingCompatibility, .optimizingModel,
             .loadingModel, .tokenizing, .inferring, .sampling, .streaming, .finalizing:
            return true
        default: return false
        }
    }

    public var displayName: String {
        switch self {
        case .idle:                   return "Idle"
        case .validatingRequest:      return "Validating…"
        case .checkingCompatibility:  return "Checking compatibility…"
        case .optimizingModel:        return "Optimizing…"
        case .loadingModel:           return "Loading model…"
        case .tokenizing:             return "Tokenizing…"
        case .inferring(let p):       return "Generating… \(Int(p * 100))%"
        case .sampling:               return "Sampling…"
        case .streaming:              return "Streaming…"
        case .finalizing:             return "Finalizing…"
        case .completed:              return "Complete"
        case .failed:                 return "Failed"
        case .cancelled:              return "Cancelled"
        }
    }
}

// MARK: - CompatibilityResult

/// Result of checking whether a model can run on the current device.
public enum CompatibilityResult: Sendable, Equatable {
    case compatible
    case marginal(warnings: [String])
    case incompatible(reasons: [String])

    public var canRun: Bool {
        switch self {
        case .compatible, .marginal: return true
        case .incompatible: return false
        }
    }

    public var statusLabel: String {
        switch self {
        case .compatible:   return "Compatible"
        case .marginal:     return "May Work"
        case .incompatible: return "Incompatible"
        }
    }

    public var statusIcon: String {
        switch self {
        case .compatible:   return "checkmark.circle.fill"
        case .marginal:     return "exclamationmark.triangle.fill"
        case .incompatible: return "xmark.circle.fill"
        }
    }
}

// MARK: - MemoryEstimate

/// Pre-flight memory estimation for a model before loading.
public struct MemoryEstimate: Sendable, Equatable {
    /// Minimum memory the model needs to load and run.
    public let requiredBytes: Int64
    /// Recommended memory for comfortable operation (includes KV cache, workspace).
    public let recommendedBytes: Int64
    /// Peak memory during inference (includes activations, sampling buffers).
    public let peakBytes: Int64

    public init(requiredBytes: Int64, recommendedBytes: Int64, peakBytes: Int64) {
        self.requiredBytes = requiredBytes
        self.recommendedBytes = recommendedBytes
        self.peakBytes = peakBytes
    }

    /// Whether this estimate fits within the given available memory.
    public func fitsInMemory(availableBytes: Int64) -> CompatibilityResult {
        if availableBytes >= recommendedBytes {
            return .compatible
        } else if availableBytes >= requiredBytes {
            return .marginal(warnings: [
                "This model may work but could be slow. Available: \(formatBytes(availableBytes)), recommended: \(formatBytes(recommendedBytes))."
            ])
        } else {
            return .incompatible(reasons: [
                "This model requires approximately \(formatBytes(requiredBytes)). Available safe memory: \(formatBytes(availableBytes))."
            ])
        }
    }
}

// MARK: - Byte formatting

/// Format a byte count into a human-readable string (e.g., "1.5 GB").
public func formatBytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_073_741_824
    if gb >= 1.0 {
        return String(format: "%.1f GB", gb)
    }
    let mb = Double(bytes) / 1_048_576
    if mb >= 1.0 {
        return String(format: "%.0f MB", mb)
    }
    let kb = Double(bytes) / 1024
    return String(format: "%.0f KB", kb)
}
