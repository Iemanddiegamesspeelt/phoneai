import Foundation

// MARK: - EngineEvent

/// Unified event types observed across all engines and the AIEngine coordinator.
/// UI layers observe these via `AsyncStream` to reactively update state.
public enum EngineEvent: Sendable {

    // MARK: - Model Lifecycle
    case modelLoading(modelId: String, progress: Double)
    case modelLoaded(modelId: String, memoryBytes: Int64)
    case modelUnloaded(modelId: String)
    case modelLoadFailed(modelId: String, error: InferenceError)

    // MARK: - Inference
    case inferenceStarted(modelId: String, requestId: UUID)
    case inferenceProgress(modelId: String, progress: Double)
    case inferenceToken(modelId: String, token: String)
    case inferenceMetrics(modelId: String, metrics: InferenceMetrics)
    case inferenceCompleted(modelId: String, requestId: UUID)
    case inferenceFailed(modelId: String, error: InferenceError)
    case inferenceCancelled(modelId: String)

    // MARK: - System
    case thermalStateChanged(ProcessInfo.ThermalState)
    case memoryWarning(level: MemoryPressureLevel, availableBytes: Int64)
    case memoryModelEvicted(modelId: String, reason: String)

    // MARK: - Downloads
    case downloadStarted(modelId: String)
    case downloadProgress(modelId: String, fraction: Double, bytesWritten: Int64, totalBytes: Int64)
    case downloadCompleted(modelId: String)
    case downloadFailed(modelId: String, error: InferenceError)

    // MARK: - Log
    case log(String, level: LogLevel)
    case error(String)
}

// MARK: - LogLevel

public enum LogLevel: String, Sendable, Codable, Comparable {
    case debug = "debug"
    case info  = "info"
    case warn  = "warn"
    case error = "error"

    private var sortOrder: Int {
        switch self {
        case .debug: return 0
        case .info:  return 1
        case .warn:  return 2
        case .error: return 3
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - InferenceMetrics

/// Runtime performance metrics captured during inference.
public struct InferenceMetrics: Sendable, Equatable {
    public let tokensPerSecond: Double
    public let totalTokens: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let elapsedSeconds: Double
    public let memoryUsedBytes: Int64
    public let activeBackend: InferenceBackendKind
    public let thermalState: ProcessInfo.ThermalState

    public init(
        tokensPerSecond: Double = 0,
        totalTokens: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        elapsedSeconds: Double = 0,
        memoryUsedBytes: Int64 = 0,
        activeBackend: InferenceBackendKind = .cpu,
        thermalState: ProcessInfo.ThermalState = .nominal
    ) {
        self.tokensPerSecond = tokensPerSecond
        self.totalTokens = totalTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.elapsedSeconds = elapsedSeconds
        self.memoryUsedBytes = memoryUsedBytes
        self.activeBackend = activeBackend
        self.thermalState = thermalState
    }
}

// MARK: - InferenceBackendKind

/// The hardware backend used for a given inference run.
public enum InferenceBackendKind: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case cpu          = "cpu"
    case gpu          = "gpu"
    case neuralEngine = "neural_engine"
    case metal        = "metal"
    case coreml       = "coreml"
    case mlx          = "mlx"

    public var displayName: String {
        switch self {
        case .cpu:          return "CPU"
        case .gpu:          return "GPU"
        case .neuralEngine: return "Neural Engine"
        case .metal:        return "Metal"
        case .coreml:       return "Core ML"
        case .mlx:          return "MLX"
        }
    }
}

// MARK: - MemoryPressureLevel

/// System memory pressure classification.
public enum MemoryPressureLevel: String, Sendable, Codable, Equatable {
    case nominal  = "nominal"
    case warning  = "warning"
    case critical = "critical"
}
