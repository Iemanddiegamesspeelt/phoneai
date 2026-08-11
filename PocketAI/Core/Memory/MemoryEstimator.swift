import Foundation

// MARK: - MemoryEstimator

/// Estimates memory requirements for models before loading.
/// Used by the CompatibilityChecker and AIEngine to determine if a model can run.
public struct MemoryEstimator: Sendable {

    /// Estimate memory for a text/LLM model.
    ///
    /// - Parameters:
    ///   - parameterCount: Number of parameters (e.g., 500_000_000 for 0.5B).
    ///   - quantization: The quantization level.
    ///   - contextLength: The context window size in tokens.
    /// - Returns: A `MemoryEstimate` with required, recommended, and peak values.
    public static func estimateTextModel(
        parameterCount: Int64? = nil,
        fileSizeBytes: Int64,
        quantization: ModelQuantization?,
        contextLength: Int = 2048
    ) -> MemoryEstimate {
        // Base memory: approximately the file size (weights loaded into memory)
        let baseBytes = fileSizeBytes

        // KV cache estimation:
        // KV cache ≈ 2 × num_layers × num_heads × head_dim × context_length × bytes_per_element
        // Simplified: ~2 bytes per token per million parameters for quantized models
        let kvCacheBytes: Int64
        if let params = parameterCount {
            let bytesPerToken = max(2, Int64(Double(params) / 500_000_000 * 2))
            kvCacheBytes = bytesPerToken * Int64(contextLength)
        } else {
            // Rough estimate: KV cache is ~10-15% of model size for typical context lengths
            kvCacheBytes = Int64(Double(baseBytes) * 0.12)
        }

        // Workspace buffers (activations, sampling, etc.): ~5-10% of model size
        let workspaceBytes = Int64(Double(baseBytes) * 0.08)

        let required = baseBytes + kvCacheBytes
        let recommended = baseBytes + kvCacheBytes + workspaceBytes + 100_000_000 // +100MB headroom
        let peak = recommended + Int64(Double(workspaceBytes) * 1.5) // Peak during generation

        return MemoryEstimate(
            requiredBytes: required,
            recommendedBytes: recommended,
            peakBytes: peak
        )
    }

    /// Estimate memory for an image generation model.
    public static func estimateImageModel(
        fileSizeBytes: Int64,
        width: Int = 512,
        height: Int = 512
    ) -> MemoryEstimate {
        let baseBytes = fileSizeBytes

        // Image buffers: width × height × 4 channels × 4 bytes × number of denoising stages
        let imageBufferBytes = Int64(width * height * 4 * 4 * 3) // 3 intermediate buffers
        let workspaceBytes = Int64(Double(baseBytes) * 0.2) // UNet workspace

        let required = baseBytes + imageBufferBytes
        let recommended = baseBytes + imageBufferBytes + workspaceBytes + 200_000_000
        let peak = recommended + Int64(Double(workspaceBytes) * 2) // UNet is memory-hungry

        return MemoryEstimate(
            requiredBytes: required,
            recommendedBytes: recommended,
            peakBytes: peak
        )
    }

    /// Estimate memory for a speech/audio model (e.g., Whisper).
    public static func estimateSpeechModel(
        fileSizeBytes: Int64,
        audioDurationSeconds: Double = 30
    ) -> MemoryEstimate {
        let baseBytes = fileSizeBytes

        // Audio buffer: 16kHz × 2 bytes × duration
        let audioBufferBytes = Int64(16000 * 2 * audioDurationSeconds)
        // Encoder/decoder workspace
        let workspaceBytes = Int64(Double(baseBytes) * 0.15)

        let required = baseBytes + audioBufferBytes
        let recommended = baseBytes + audioBufferBytes + workspaceBytes + 50_000_000
        let peak = recommended + workspaceBytes

        return MemoryEstimate(
            requiredBytes: required,
            recommendedBytes: recommended,
            peakBytes: peak
        )
    }

    /// Generic estimate when we don't know the model type well.
    public static func estimateGeneric(fileSizeBytes: Int64) -> MemoryEstimate {
        let base = fileSizeBytes
        let overhead = Int64(Double(base) * 0.2) + 100_000_000

        return MemoryEstimate(
            requiredBytes: base,
            recommendedBytes: base + overhead,
            peakBytes: base + Int64(Double(overhead) * 1.5)
        )
    }

    /// Choose the best estimate method based on engine kind.
    public static func estimate(
        for engineKind: ModelEngineKind,
        fileSizeBytes: Int64,
        quantization: ModelQuantization? = nil,
        contextLength: Int = 2048,
        imageWidth: Int = 512,
        imageHeight: Int = 512
    ) -> MemoryEstimate {
        switch engineKind {
        case .text:
            return estimateTextModel(
                fileSizeBytes: fileSizeBytes,
                quantization: quantization,
                contextLength: contextLength
            )
        case .image:
            return estimateImageModel(
                fileSizeBytes: fileSizeBytes,
                width: imageWidth,
                height: imageHeight
            )
        case .speech:
            return estimateSpeechModel(fileSizeBytes: fileSizeBytes)
        case .vision:
            return estimateTextModel(
                fileSizeBytes: fileSizeBytes,
                quantization: quantization,
                contextLength: contextLength
            )
        default:
            return estimateGeneric(fileSizeBytes: fileSizeBytes)
        }
    }
}
