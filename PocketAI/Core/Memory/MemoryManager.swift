import Foundation
#if canImport(os)
import os
#endif

// MARK: - MemoryManager

/// Tracks loaded models, monitors system memory pressure, and enforces safe memory budgets.
/// Uses LRU eviction to automatically unload inactive models when pressure increases.
public actor MemoryManager {

    // MARK: - Types

    /// A record of a model currently loaded in memory.
    public struct LoadedModel: Sendable, Identifiable {
        public let id: String
        public let engineKind: ModelEngineKind
        public let memoryBytes: Int64
        public let loadedAt: Date
        public var lastAccessedAt: Date

        public init(id: String, engineKind: ModelEngineKind, memoryBytes: Int64) {
            self.id = id
            self.engineKind = engineKind
            self.memoryBytes = memoryBytes
            self.loadedAt = Date()
            self.lastAccessedAt = Date()
        }
    }

    /// Current memory status snapshot.
    public struct MemorySnapshot: Sendable {
        public let totalSystemBytes: Int64
        public let availableBytes: Int64
        public let safeModelBudgetBytes: Int64
        public let usedByModelsBytes: Int64
        public let remainingBudgetBytes: Int64
        public let loadedModels: [LoadedModel]
        public let pressureLevel: MemoryPressureLevel
        public let timestamp: Date

        public var utilizationRatio: Double {
            guard safeModelBudgetBytes > 0 else { return 0 }
            return Double(usedByModelsBytes) / Double(safeModelBudgetBytes)
        }

        public var statusLabel: String {
            switch pressureLevel {
            case .nominal:  return "SAFE"
            case .warning:  return "WARNING"
            case .critical: return "CRITICAL"
            }
        }
    }

    // MARK: - State

    private var loadedModels: [String: LoadedModel] = [:]
    private let totalSystemBytes: Int64
    private let safeModelBudgetBytes: Int64
    private var eventContinuation: AsyncStream<EngineEvent>.Continuation?

    /// Stream of memory-related events (model evictions, warnings).
    public private(set) var events: AsyncStream<EngineEvent>!

    // MARK: - Init

    public init(hardwareProfile: HardwareCapabilityProfile) {
        self.totalSystemBytes = hardwareProfile.totalRAMBytes
        self.safeModelBudgetBytes = hardwareProfile.safeModelMemoryBytes

        var continuation: AsyncStream<EngineEvent>.Continuation!
        self.events = AsyncStream { cont in
            continuation = cont
        }
        self.eventContinuation = continuation
    }

    // MARK: - Pre-flight

    /// Check whether a model of the given size can safely be loaded.
    public func canLoadModel(requiredBytes: Int64) -> CompatibilityResult {
        let remaining = remainingBudgetBytes()
        if requiredBytes <= remaining {
            return .compatible
        }

        // Check if we could free enough by evicting LRU models
        let evictableBytes = loadedModels.values
            .sorted { $0.lastAccessedAt < $1.lastAccessedAt }
            .reduce(Int64(0)) { $0 + $1.memoryBytes }

        if requiredBytes <= remaining + evictableBytes {
            return .marginal(warnings: [
                "Loading this model requires unloading other models to free \(formatBytes(requiredBytes - remaining))."
            ])
        }

        return .incompatible(reasons: [
            "This model requires approximately \(formatBytes(requiredBytes)). Available safe memory: \(formatBytes(safeModelBudgetBytes)). Even after unloading all models, there isn't enough memory."
        ])
    }

    /// Estimate available memory, used by the MemoryEstimator.
    public func currentAvailableBytes() -> Int64 {
        return Self.queryAvailableMemory()
    }

    // MARK: - Model Registration

    /// Register a model as loaded. Call this after a successful model load.
    public func registerModel(id: String, engineKind: ModelEngineKind, memoryBytes: Int64) {
        loadedModels[id] = LoadedModel(
            id: id,
            engineKind: engineKind,
            memoryBytes: memoryBytes
        )
    }

    /// Mark a model as accessed (updates LRU ordering).
    public func touchModel(id: String) {
        loadedModels[id]?.lastAccessedAt = Date()
    }

    /// Unregister a model (after unloading).
    public func unregisterModel(id: String) {
        loadedModels.removeValue(forKey: id)
    }

    /// Get the list of currently loaded models.
    public func getLoadedModels() -> [LoadedModel] {
        Array(loadedModels.values).sorted { $0.lastAccessedAt > $1.lastAccessedAt }
    }

    // MARK: - LRU Eviction

    /// Attempt to free at least `targetBytes` by evicting LRU models.
    /// Returns the IDs of models that should be unloaded.
    public func evictModelsToFree(targetBytes: Int64, excluding: Set<String> = []) -> [String] {
        var freed: Int64 = 0
        var toEvict: [String] = []

        let candidates = loadedModels.values
            .filter { !excluding.contains($0.id) }
            .sorted { $0.lastAccessedAt < $1.lastAccessedAt } // LRU first

        for model in candidates {
            if freed >= targetBytes { break }
            toEvict.append(model.id)
            freed += model.memoryBytes

            eventContinuation?.yield(.memoryModelEvicted(
                modelId: model.id,
                reason: "Memory pressure eviction"
            ))
        }

        return toEvict
    }

    /// Handle system memory pressure warning.
    public func handleMemoryPressure(level: MemoryPressureLevel) {
        eventContinuation?.yield(.memoryWarning(
            level: level,
            availableBytes: Self.queryAvailableMemory()
        ))

        switch level {
        case .warning:
            // Evict models not accessed in the last 5 minutes
            let threshold = Date().addingTimeInterval(-300)
            let stale = loadedModels.values.filter { $0.lastAccessedAt < threshold }
            for model in stale {
                eventContinuation?.yield(.memoryModelEvicted(
                    modelId: model.id,
                    reason: "Memory pressure: stale model"
                ))
            }

        case .critical:
            // Evict everything except the most recently used model
            let sorted = loadedModels.values.sorted { $0.lastAccessedAt > $1.lastAccessedAt }
            for model in sorted.dropFirst() {
                eventContinuation?.yield(.memoryModelEvicted(
                    modelId: model.id,
                    reason: "Critical memory pressure"
                ))
            }

        case .nominal:
            break
        }
    }

    // MARK: - Snapshots

    /// Get a snapshot of current memory state.
    public func snapshot() -> MemorySnapshot {
        let usedByModels = loadedModels.values.reduce(Int64(0)) { $0 + $1.memoryBytes }
        let available = Self.queryAvailableMemory()

        let pressure: MemoryPressureLevel
        let ratio = Double(usedByModels) / max(1, Double(safeModelBudgetBytes))
        if ratio > 0.9 || available < 500_000_000 {
            pressure = .critical
        } else if ratio > 0.7 || available < 1_000_000_000 {
            pressure = .warning
        } else {
            pressure = .nominal
        }

        return MemorySnapshot(
            totalSystemBytes: totalSystemBytes,
            availableBytes: available,
            safeModelBudgetBytes: safeModelBudgetBytes,
            usedByModelsBytes: usedByModels,
            remainingBudgetBytes: max(0, safeModelBudgetBytes - usedByModels),
            loadedModels: Array(loadedModels.values),
            pressureLevel: pressure,
            timestamp: Date()
        )
    }

    // MARK: - Private

    private func remainingBudgetBytes() -> Int64 {
        let used = loadedModels.values.reduce(Int64(0)) { $0 + $1.memoryBytes }
        return max(0, safeModelBudgetBytes - used)
    }

    /// Query available process memory using os_proc_available_memory.
    private static func queryAvailableMemory() -> Int64 {
        // os_proc_available_memory() returns the approximate amount of memory
        // available to the process before jetsam.
        return Int64(os_proc_available_memory())
    }
}
