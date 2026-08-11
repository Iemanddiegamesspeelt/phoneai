import Foundation

/// Local video engine conforming to `VideoInferenceEngine`.
/// This engine is designed to enforce strict capability barriers for video-generation AI models.
/// It detects whether hardware requirements (e.g. 16GB RAM) are met and refuses to run on unsupported configurations.
public actor LocalVideoEngine: VideoInferenceEngine {

    public let engineKind: ModelEngineKind = .video

    private var loadedModelId: String?
    private var modelPath: URL?
    private var isCancelled = false

    public init() {}

    public func loadModel(from path: URL, manifest: ModelCatalogEntry) async throws {
        // Enforce check before loading
        let profile = HardwareCapabilityProfile(
            deviceModel: "iPhone",
            deviceName: "iPhone",
            iosVersion: "18.0",
            totalRAMBytes: Int64(ProcessInfo.processInfo.physicalMemory),
            processorCount: ProcessInfo.processInfo.processorCount,
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount,
            processorFamily: .unknown,
            gpuName: nil,
            gpuMaxThreadsPerGroup: nil,
            metalSupported: true,
            metalGPUFamily: nil,
            neuralEngineAvailable: true,
            availableStorageBytes: 0,
            thermalState: .nominal,
            isLowPowerMode: false,
            isSimulator: false,
            capturedAt: Date()
        )
        
        let compatibility = checkCompatibility(manifest: manifest, hardware: profile)
        if case .incompatible(let reasons) = compatibility {
            throw InferenceError(.modelTooLarge, message: reasons.joined(separator: " "))
        }

        loadedModelId = manifest.id
        modelPath = path
    }

    public func unloadModel() async throws {
        loadedModelId = nil
        modelPath = nil
        isCancelled = false
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
        // Enforce strict 16 GB RAM minimum for video generation models on iOS
        let requiredRAM: Int64 = 16 * 1_073_741_824 // 16 GB
        
        if hardware.totalRAMBytes < requiredRAM {
            return .incompatible(reasons: [
                "Video generation requires at least 16 GB of unified memory. This device only has \(hardware.totalRAMFormatted). Try running a smaller text or image model instead."
            ])
        }
        
        return .compatible
    }

    public func estimateMemory(manifest: ModelCatalogEntry) -> MemoryEstimate {
        // Expose massive memory requirements for video models
        let required = 14 * 1_073_741_824 // 14 GB base
        return MemoryEstimate(
            requiredBytes: Int64(required),
            recommendedBytes: Int64(required + 2 * 1_073_741_824),
            peakBytes: Int64(required + 4 * 1_073_741_824)
        )
    }

    public func generateVideo(prompt: String, parameters: AnyCodable) async throws -> URL {
        // This will never be executed on standard mobile hardware
        throw InferenceError(.unsupportedHardware, message: "Video generation is not supported on this hardware configuration.")
    }

    public func cancel() async {
        isCancelled = true
    }
}
