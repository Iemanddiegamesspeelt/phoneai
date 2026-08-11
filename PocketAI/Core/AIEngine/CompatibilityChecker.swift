import Foundation

// MARK: - CompatibilityChecker

/// Checks whether a model can safely run on the current device.
/// Used by the AIEngine before loading any model to prevent crashes.
public struct CompatibilityChecker: Sendable {

    /// Run a full compatibility check for a model against the device's hardware.
    public static func check(
        model: ModelCatalogEntry,
        hardware: HardwareCapabilityProfile
    ) -> CompatibilityResult {
        var warnings: [String] = []
        var reasons: [String] = []

        // 1. Check memory
        let memoryEstimate = MemoryEstimator.estimate(
            for: model.engineKind,
            fileSizeBytes: model.fileSizeBytes,
            quantization: model.quantization,
            contextLength: model.contextLength ?? 2048
        )

        let safeMemory = hardware.safeModelMemoryBytes
        if memoryEstimate.requiredBytes > safeMemory {
            reasons.append(
                "This model requires approximately \(formatBytes(memoryEstimate.requiredBytes)). " +
                "Available safe memory: \(formatBytes(safeMemory))."
            )
        } else if memoryEstimate.recommendedBytes > safeMemory {
            warnings.append(
                "This model may run slowly. Recommended: \(formatBytes(memoryEstimate.recommendedBytes)), " +
                "available: \(formatBytes(safeMemory))."
            )
        }

        // 2. Check minimum RAM requirement from catalog
        if model.minimumRAMBytes > 0 && hardware.totalRAMBytes < model.minimumRAMBytes {
            reasons.append(
                "This model requires at least \(formatBytes(model.minimumRAMBytes)) RAM. " +
                "This device has \(hardware.totalRAMFormatted)."
            )
        }

        // 3. Check storage
        let requiredStorage = model.downloadSizeBytes > 0 ? model.downloadSizeBytes : model.fileSizeBytes
        if hardware.availableStorageBytes < requiredStorage + 500_000_000 {
            reasons.append(
                "Not enough storage. This model requires \(formatBytes(requiredStorage)) " +
                "plus buffer space. Available: \(formatBytes(hardware.availableStorageBytes))."
            )
        }

        // 4. Check format compatibility
        switch model.format {
        case .mlx, .safetensors:
            // MLX is available on all Apple Silicon (A-series iOS devices)
            break
        case .gguf:
            // GGUF works via llama.cpp on all devices
            break
        case .mlmodelc, .coreml:
            // Core ML available on iOS 11+, so always fine for our 17+ target
            break
        case .onnx:
            warnings.append("ONNX runtime support is experimental on iOS.")
        }

        // 5. Check Neural Engine for models that benefit from it
        if model.engineKind == .image && !hardware.neuralEngineAvailable {
            warnings.append(
                "Image generation works best with a Neural Engine. " +
                "This device will use GPU/CPU fallback, which may be slower."
            )
        }

        // 6. Check Metal for GPU-accelerated models
        if !hardware.metalSupported {
            warnings.append(
                "Metal is not available on this device. Models will run on CPU only."
            )
        }

        // 7. Thermal state check
        if hardware.thermalState == .critical {
            warnings.append(
                "Device is currently in critical thermal state. " +
                "Wait for it to cool down before loading models."
            )
        }

        // 8. Low power mode warning
        if hardware.isLowPowerMode {
            warnings.append(
                "Low Power Mode is enabled. Inference may be throttled."
            )
        }

        // Return result
        if !reasons.isEmpty {
            return .incompatible(reasons: reasons)
        } else if !warnings.isEmpty {
            return .marginal(warnings: warnings)
        } else {
            return .compatible
        }
    }

    /// Generate a user-friendly compatibility summary.
    public static func compatibilitySummary(
        model: ModelCatalogEntry,
        hardware: HardwareCapabilityProfile
    ) -> CompatibilitySummary {
        let result = check(model: model, hardware: hardware)
        let estimate = MemoryEstimator.estimate(
            for: model.engineKind,
            fileSizeBytes: model.fileSizeBytes,
            quantization: model.quantization
        )

        return CompatibilitySummary(
            result: result,
            requiredMemory: formatBytes(estimate.requiredBytes),
            recommendedMemory: formatBytes(estimate.recommendedBytes),
            availableMemory: formatBytes(hardware.safeModelMemoryBytes),
            deviceModel: hardware.deviceModel,
            totalRAM: hardware.totalRAMFormatted,
            suggestedAlternatives: result.canRun ? [] : suggestAlternatives(for: model)
        )
    }

    /// Suggest smaller alternative models when the requested one is incompatible.
    private static func suggestAlternatives(for model: ModelCatalogEntry) -> [String] {
        var suggestions: [String] = []
        suggestions.append("Try a smaller model in the same family.")
        if model.quantization == nil || model.quantization == .float16 {
            suggestions.append("Try a quantized version (Q4_K_M or Q4_0) for lower memory usage.")
        }
        if model.engineKind == .image {
            suggestions.append("Try a lower resolution (e.g., 256×256 instead of 512×512).")
        }
        return suggestions
    }
}

// MARK: - CompatibilitySummary

/// User-friendly summary of a compatibility check.
public struct CompatibilitySummary: Sendable {
    public let result: CompatibilityResult
    public let requiredMemory: String
    public let recommendedMemory: String
    public let availableMemory: String
    public let deviceModel: String
    public let totalRAM: String
    public let suggestedAlternatives: [String]
}
