import Foundation

// MARK: - BackendSelector

/// Determines the optimal execution backend for a model based on device capabilities
/// and current system state (thermal, memory pressure).
public struct BackendSelector: Sendable {

    /// Select the best backend for a given model and hardware profile.
    public static func selectBackend(
        for model: ModelCatalogEntry,
        hardware: HardwareCapabilityProfile,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    ) -> BackendSelection {

        // Determine available backends
        var candidates: [BackendCandidate] = []

        // MLX backend (preferred for MLX/safetensors format)
        if model.format == .mlx || model.format == .safetensors {
            candidates.append(BackendCandidate(
                kind: .mlx,
                priority: 100,
                estimatedSpeedup: 3.0,
                reason: "MLX with unified memory and Metal acceleration"
            ))
        }

        // Core ML backend (preferred for .mlmodelc, good for ANE)
        if (model.format == .coreml || model.format == .mlmodelc) && hardware.neuralEngineAvailable {
            candidates.append(BackendCandidate(
                kind: .coreml,
                priority: 90,
                estimatedSpeedup: 2.5,
                reason: "Core ML with Neural Engine acceleration"
            ))
        }

        // Metal GPU backend
        if hardware.metalSupported {
            candidates.append(BackendCandidate(
                kind: .metal,
                priority: 70,
                estimatedSpeedup: 2.0,
                reason: "Metal GPU compute"
            ))
        }

        // CPU fallback (always available)
        candidates.append(BackendCandidate(
            kind: .cpu,
            priority: 10,
            estimatedSpeedup: 1.0,
            reason: "CPU fallback"
        ))

        // Apply thermal adjustments
        switch thermalState {
        case .serious:
            // Prefer lower-power backends
            for i in candidates.indices {
                if candidates[i].kind == .gpu || candidates[i].kind == .metal {
                    candidates[i].priority -= 30
                }
            }
        case .critical:
            // Force CPU-only to cool down
            candidates = candidates.filter { $0.kind == .cpu }
        default:
            break
        }

        // Sort by priority (highest first)
        candidates.sort { $0.priority > $1.priority }

        let selected = candidates.first ?? BackendCandidate(
            kind: .cpu,
            priority: 10,
            estimatedSpeedup: 1.0,
            reason: "CPU fallback (default)"
        )

        // Determine thread count
        let threadCount = recommendedThreadCount(
            hardware: hardware,
            thermalState: thermalState
        )

        return BackendSelection(
            backend: selected.kind,
            reason: selected.reason,
            threadCount: threadCount,
            useNeuralEngine: hardware.neuralEngineAvailable && selected.kind == .coreml,
            useMetal: hardware.metalSupported && (selected.kind == .metal || selected.kind == .mlx),
            estimatedSpeedup: selected.estimatedSpeedup,
            allCandidates: candidates
        )
    }

    /// Recommend thread count based on hardware and thermal state.
    public static func recommendedThreadCount(
        hardware: HardwareCapabilityProfile,
        thermalState: ProcessInfo.ThermalState = .nominal
    ) -> Int {
        let maxThreads = hardware.activeProcessorCount

        switch thermalState {
        case .nominal:
            // Use performance cores (typically half the total)
            return max(1, maxThreads / 2 + 1)
        case .fair:
            return max(1, maxThreads / 2)
        case .serious:
            // Reduce to efficiency cores
            return max(1, maxThreads / 3)
        case .critical:
            return 1
        @unknown default:
            return max(1, maxThreads / 2)
        }
    }
}

// MARK: - BackendSelection

/// The result of backend selection — tells the engine how to configure inference.
public struct BackendSelection: Sendable {
    public let backend: InferenceBackendKind
    public let reason: String
    public let threadCount: Int
    public let useNeuralEngine: Bool
    public let useMetal: Bool
    public let estimatedSpeedup: Double
    public let allCandidates: [BackendCandidate]
}

// MARK: - BackendCandidate

/// A candidate backend with priority scoring.
public struct BackendCandidate: Sendable {
    public let kind: InferenceBackendKind
    public var priority: Int
    public let estimatedSpeedup: Double
    public let reason: String
}
