import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Metal)
import Metal
#endif

// MARK: - HardwareCapabilityProfile

/// A snapshot of the device's hardware capabilities, captured at startup.
/// Used by the AIEngine and CompatibilityChecker to make runtime decisions.
public struct HardwareCapabilityProfile: Sendable, Equatable {
    public let deviceModel: String
    public let deviceName: String
    public let iosVersion: String
    public let totalRAMBytes: Int64
    public let processorCount: Int
    public let activeProcessorCount: Int
    public let processorFamily: ProcessorFamily
    public let gpuName: String?
    public let gpuMaxThreadsPerGroup: Int?
    public let metalSupported: Bool
    public let metalGPUFamily: String?
    public let neuralEngineAvailable: Bool
    public let availableStorageBytes: Int64
    public let thermalState: ProcessInfo.ThermalState
    public let isLowPowerMode: Bool
    public let isSimulator: Bool
    public let capturedAt: Date

    /// Human-readable total RAM.
    public var totalRAMFormatted: String { formatBytes(totalRAMBytes) }

    /// Approximate GB of RAM.
    public var totalRAMGB: Double { Double(totalRAMBytes) / 1_073_741_824 }

    /// Conservative estimate of memory available for models (total minus ~2 GB system overhead).
    public var safeModelMemoryBytes: Int64 {
        let overhead: Int64 = isSimulator ? 0 : 2_147_483_648 // 2 GB
        return max(0, totalRAMBytes - overhead)
    }

    /// Formatted safe model memory.
    public var safeModelMemoryFormatted: String { formatBytes(safeModelMemoryBytes) }

    /// Available storage formatted.
    public var availableStorageFormatted: String { formatBytes(availableStorageBytes) }

    /// Recommended maximum model size based on device capabilities.
    public var recommendedMaxModelSize: String {
        let safeGB = Double(safeModelMemoryBytes) / 1_073_741_824
        if safeGB >= 8 {
            return "~3–7 GB"
        } else if safeGB >= 4 {
            return "~1–3 GB"
        } else if safeGB >= 2 {
            return "~500 MB–1.5 GB"
        } else {
            return "~100–500 MB"
        }
    }

    /// Summary string suitable for display.
    public var summary: String {
        """
        Device: \(deviceModel)
        RAM: \(totalRAMFormatted)
        GPU: \(gpuName ?? "Unknown")
        Neural Engine: \(neuralEngineAvailable ? "Available" : "Not Available")
        Metal: \(metalSupported ? "Supported" : "Not Supported")
        Storage: \(availableStorageFormatted) available
        Recommended model size: \(recommendedMaxModelSize)
        """
    }
}

// MARK: - ProcessorFamily

/// Identifies the Apple Silicon generation for capability bucketing.
public enum ProcessorFamily: String, Sendable, Equatable, Codable {
    case a11 = "A11"
    case a12 = "A12"
    case a13 = "A13"
    case a14 = "A14"
    case a15 = "A15"
    case a16 = "A16"
    case a17 = "A17"
    case a18 = "A18"
    case m1  = "M1"
    case m2  = "M2"
    case m3  = "M3"
    case m4  = "M4"
    case unknown = "Unknown"

    /// Whether this processor has a Neural Engine.
    public var hasNeuralEngine: Bool {
        switch self {
        case .a11: return true  // First ANE, limited
        case .unknown: return false
        default: return true
        }
    }

    /// Relative performance tier (higher = faster).
    public var performanceTier: Int {
        switch self {
        case .a11: return 1
        case .a12: return 2
        case .a13: return 3
        case .a14: return 4
        case .a15: return 5
        case .a16: return 6
        case .a17: return 7
        case .a18: return 8
        case .m1:  return 7
        case .m2:  return 8
        case .m3:  return 9
        case .m4:  return 10
        case .unknown: return 0
        }
    }
}

// MARK: - HardwareDetector

/// Detects and reports device hardware capabilities using Apple APIs.
/// No hardcoded values — everything is queried at runtime.
public actor HardwareDetector {

    private var cachedProfile: HardwareCapabilityProfile?

    /// Detect device capabilities and return a snapshot profile.
    /// Caches the result so subsequent calls return instantly.
    public func detectCapabilities() async -> HardwareCapabilityProfile {
        if let cached = cachedProfile { return cached }

        let profile = HardwareCapabilityProfile(
            deviceModel: Self.deviceModelIdentifier(),
            deviceName: await Self.deviceName(),
            iosVersion: await Self.iosVersion(),
            totalRAMBytes: Self.totalRAMBytes(),
            processorCount: ProcessInfo.processInfo.processorCount,
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount,
            processorFamily: Self.detectProcessorFamily(),
            gpuName: Self.gpuName(),
            gpuMaxThreadsPerGroup: Self.gpuMaxThreadsPerGroup(),
            metalSupported: Self.isMetalSupported(),
            metalGPUFamily: Self.metalGPUFamilyDescription(),
            neuralEngineAvailable: Self.isNeuralEngineAvailable(),
            availableStorageBytes: Self.availableStorageBytes(),
            thermalState: ProcessInfo.processInfo.thermalState,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            isSimulator: Self.isSimulator(),
            capturedAt: Date()
        )
        cachedProfile = profile
        return profile
    }

    /// Force a fresh detection (e.g., after thermal state change).
    public func invalidateCache() {
        cachedProfile = nil
    }

    // MARK: - Private Detection Methods

    /// Returns the machine identifier (e.g., "iPhone15,2").
    private static func deviceModelIdentifier() -> String {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
        #endif
    }

    /// User-facing device name (e.g., "Tim's iPhone").
    @MainActor
    private static func deviceName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }

    /// iOS version string.
    @MainActor
    private static func iosVersion() -> String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        let info = ProcessInfo.processInfo
        return "\(info.operatingSystemVersion.majorVersion).\(info.operatingSystemVersion.minorVersion).\(info.operatingSystemVersion.patchVersion)"
        #endif
    }

    /// Total physical RAM in bytes.
    private static func totalRAMBytes() -> Int64 {
        Int64(ProcessInfo.processInfo.physicalMemory)
    }

    /// Available storage on the volume containing the Documents directory.
    private static func availableStorageBytes() -> Int64 {
        do {
            let homeURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            return 0
        }
    }

    /// Whether we're running in the Simulator.
    private static func isSimulator() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// Metal GPU name.
    private static func gpuName() -> String? {
        #if canImport(Metal)
        return MTLCreateSystemDefaultDevice()?.name
        #else
        return nil
        #endif
    }

    /// Maximum thread execution width of the GPU.
    private static func gpuMaxThreadsPerGroup() -> Int? {
        #if canImport(Metal)
        return MTLCreateSystemDefaultDevice()?.maxThreadsPerThreadgroup.width
        #else
        return nil
        #endif
    }

    /// Whether Metal is available.
    private static func isMetalSupported() -> Bool {
        #if canImport(Metal)
        return MTLCreateSystemDefaultDevice() != nil
        #else
        return false
        #endif
    }

    /// Description of the highest supported Metal GPU family.
    private static func metalGPUFamilyDescription() -> String? {
        #if canImport(Metal)
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        // Check from newest to oldest
        if device.supportsFamily(.apple9) { return "Apple GPU Family 9" }
        if device.supportsFamily(.apple8) { return "Apple GPU Family 8" }
        if device.supportsFamily(.apple7) { return "Apple GPU Family 7" }
        if device.supportsFamily(.apple6) { return "Apple GPU Family 6" }
        if device.supportsFamily(.apple5) { return "Apple GPU Family 5" }
        if device.supportsFamily(.apple4) { return "Apple GPU Family 4" }
        if device.supportsFamily(.apple3) { return "Apple GPU Family 3" }
        return "Apple GPU (Unknown Family)"
        #else
        return nil
        #endif
    }

    /// Detect Neural Engine availability.
    /// The Neural Engine is available on A11 and later.
    private static func isNeuralEngineAvailable() -> Bool {
        // Core ML automatically routes to ANE when available.
        // We check processor family as a proxy.
        let family = detectProcessorFamily()
        return family.hasNeuralEngine
    }

    /// Detect the processor family from the device model identifier.
    private static func detectProcessorFamily() -> ProcessorFamily {
        let model = deviceModelIdentifier()

        // iPad with M-series
        if model.contains("iPad") {
            if model.hasPrefix("iPad16") || model.hasPrefix("iPad17") { return .m4 }
            if model.hasPrefix("iPad14") || model.hasPrefix("iPad15") { return .m2 }
            if model.hasPrefix("iPad13") { return .m1 }
        }

        // iPhone identifiers
        if model.hasPrefix("iPhone17") { return .a18 }
        if model.hasPrefix("iPhone16") { return .a17 }
        if model.hasPrefix("iPhone15") { return .a16 }
        if model.hasPrefix("iPhone14") { return .a15 }
        if model.hasPrefix("iPhone13") { return .a14 }
        if model.hasPrefix("iPhone12") { return .a13 }
        if model.hasPrefix("iPhone11") { return .a12 }
        if model.hasPrefix("iPhone10") { return .a11 }

        // Simulator fallback — assume modern hardware
        if model.contains("Simulator") || model == "x86_64" || model == "arm64" {
            return .a16
        }

        return .unknown
    }
}
