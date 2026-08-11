import Foundation

// MARK: - InferenceError
// The unified error domain for the AI engine layer.

/// Domain prefix for all native inference engine errors.
public let PocketAIErrorDomain = "com.pocketai.PocketAICore"

/// A structured error emitted by the AIEngine and its subsystems.
///
/// Conformance to `LocalizedError` provides user-facing messages via
/// `NSError.localizedDescription`. Framework consumers should use the
/// high-level enum cases; internal handling can drill into
/// `underlyingMessage` for diagnostics.
public struct InferenceError: LocalizedError, Equatable, Sendable {

    public enum Code: Int, Codable, Sendable, CaseIterable {
        // ---------- Hardware / compatibility ----------
        case unsupportedHardware          = 100
        case unsupportedModelFormat       = 101
        case modelTooLarge                = 102
        case deviceThermallyThrottled     = 103
        case neuralEngineUnavailable      = 104

        // ---------- Loading / lifecycle ----------
        case modelLoadFailed              = 200
        case modelUnloadFailed            = 201
        case modelInitializationTimeout   = 202
        case modelNotLoaded               = 203
        case modelLoaderNil               = 204
        case modelCorrupted               = 205

        // ---------- Inference execution ----------
        case inferenceFailed              = 300
        case inferenceCancelled           = 301
        case contextWindowExceeded        = 302
        case tokenizationFailed           = 303
        case samplingFailed               = 304

        // ---------- Backend / runtime ----------
        case backendSelectionFailed       = 400
        case backendExecutionFailed       = 401
        case backendCompilationFailed     = 402
        case backendUnavailable           = 403
        case backendTimeout               = 404

        // ---------- Memory / storage ----------
        case memoryPressureHigh           = 500
        case memoryAllocationFailed       = 501
        case storageInsufficient          = 502
        case storageWriteFailed           = 503
        case storageReadFailed            = 504

        // ---------- Download / installation ----------
        case downloadFailed               = 600
        case downloadChecksumMismatch     = 601
        case downloadCorrupted            = 602
        case downloadPaused               = 603
        case downloadCancelled            = 604
        case downloadStorageInsufficient  = 605
        case installationFailed           = 606
        case installationIntegrityFailed  = 607
        case installationIncompatible     = 608

        // ---------- Catalog / metadata ----------
        case catalogManifestInvalid       = 700
        case catalogManifestFetchFailed   = 701
        case modelMetadataMissing         = 702
        case modelCompatibilityCheckFailed = 703

        // ---------- Unknown ----------
        case unknown                      = 999
    }

    public let code: Code
    public let underlyingMessage: String?
    public let suggestion: String?

    public init(
        _ code: Code,
        message: String? = nil,
        suggestion: String? = nil
    ) {
        self.code = code
        self.underlyingMessage = message
        self.suggestion = suggestion
    }

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch code {
        case .modelTooLarge:
            return "Model Too Large"
        case .deviceThermallyThrottled:
            return "Device Thermally Constrained"
        case .neuralEngineUnavailable:
            return "Neural Engine Unavailable"
        case .modelLoadFailed:
            return "Model Load Failed"
        case .modelNotLoaded:
            return "No Model Loaded"
        case .modelCorrupted:
            return "Model Corrupted"
        case .inferenceCancelled:
            return "Inference Cancelled"
        case .inferenceFailed:
            return "Inference Failed"
        case .contextWindowExceeded:
            return "Context Window Exceeded"
        case .memoryPressureHigh:
            return "Memory Pressure High"
        case .memoryAllocationFailed:
            return "Memory Allocation Failed"
        case .storageInsufficient:
            return "Insufficient Storage"
        case .downloadFailed:
            return "Download Failed"
        case .downloadChecksumMismatch:
            return "Checksum Mismatch"
        case .installationFailed:
            return "Installation Failed"
        case .unsupportedModelFormat:
            return "Unsupported Model Format"
        case .unsupportedHardware:
            return "Unsupported Hardware"
        default:
            return "PocketAI Error (\(code))"
        }
    }

    public var failureReason: String? {
        underlyingMessage ?? defaultFailureReason
    }

    private var defaultFailureReason: String {
        switch code {
        case .modelTooLarge:
            return "This model requires more memory than available on this device."
        case .deviceThermallyThrottled:
            return "Device is thermally constrained. Inference suspended."
        case .neuralEngineUnavailable:
            return "Neural Engine is not available on this device."
        case .modelLoadFailed:
            return "Failed to load the model into memory."
        case .inferenceCancelled:
            return "Inference was cancelled by the user."
        case .contextWindowExceeded:
            return "The input exceeds the model's context window."
        case .downloadChecksumMismatch:
            return "Downloaded file did not match expected checksum."
        case .storageInsufficient:
            return "Not enough storage available on this device."
        case .memoryPressureHigh:
            return "The system is under memory pressure. Some models have been unloaded."
        default:
            return "An unexpected error occurred."
        }
    }

    public var recoverySuggestion: String? {
        suggestion ?? defaultRecoverySuggestion
    }

    private var defaultRecoverySuggestion: String? {
        switch code {
        case .modelTooLarge:
            return "Try a smaller model, a lower quantization, or close other apps to free memory."
        case .deviceThermallyThrottled:
            return "Let the device cool down before trying again."
        case .memoryPressureHigh:
            return "Close other apps or try a smaller model."
        case .storageInsufficient:
            return "Delete unused models or free storage space."
        case .downloadChecksumMismatch:
            return "Try downloading the model again."
        case .unsupportedModelFormat:
            return "This model format is not supported. Use GGUF, MLX, or Core ML formats."
        default:
            return nil
        }
    }

    public var isRecoverable: Bool {
        switch code {
        case .modelTooLarge, .deviceThermallyThrottled,
             .memoryPressureHigh, .storageInsufficient,
             .inferenceCancelled, .downloadPaused:
            return true
        default:
            return false
        }
    }
}

// MARK: - InferenceOutcome

/// Result type used by public-facing APIs.
public enum InferenceOutcome<T: Sendable>: Sendable {
    case success(T)
    case failure(InferenceError)

    public var value: T? {
        if case .success(let value) = self { return value }
        return nil
    }

    public var error: InferenceError? {
        if case .failure(let error) = self { return error }
        return nil
    }

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
