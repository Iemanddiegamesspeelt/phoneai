import Foundation

// MARK: - FoundationCommon.swift
// Centralized common types and constants used by the entire codebase.
// Single source of truth — no other file should re-declare these types.

// MARK: - Reusable value types used across features

/// A lightweight identifier — typically a UUID or model slug — shared across the app.
public typealias ModelIdentifier = String

/// A thread-name-safe identifier for async tasks.
public typealias TaskIdentifier = UUID

/// A bundle identifier used for code-level resource grouping.
public typealias AppBundleIdentifier = String

/// Session identifier for chat or inference sessions.
public typealias SessionID = String

// MARK: - Common function types

/// Async no-argument closure returning void.
public typealias AsyncVoidClosure = () async -> Void

/// Sync no-argument closure returning void.
public typealias SyncVoidClosure = () -> Void

/// Closure carrying a Bool indicating a result state.
public typealias BoolCompletion = (Bool) -> Void

// MARK: - AnyCodable

/// A type-erased `Codable` wrapper for heterogeneous data in manifests and results.
public struct AnyCodable: Codable, Sendable, Equatable, Hashable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable: unsupported type"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: value))
    }
}

// MARK: - ModelQuantization

/// Quantization level for a model. Determines memory footprint and quality tradeoff.
public enum ModelQuantization: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case float32 = "f32"
    case float16 = "f16"
    case bfloat16 = "bf16"
    case int8 = "q8_0"
    case int4 = "q4_0"
    case int4KM = "q4_k_m"
    case int4KS = "q4_k_s"
    case int3 = "q3_k_m"
    case int2 = "q2_k"

    /// Approximate memory multiplier relative to float32 parameter count.
    public var memoryMultiplier: Double {
        switch self {
        case .float32:  return 4.0
        case .float16:  return 2.0
        case .bfloat16: return 2.0
        case .int8:     return 1.0
        case .int4, .int4KM, .int4KS: return 0.5
        case .int3:     return 0.375
        case .int2:     return 0.25
        }
    }

    /// Human-readable label for display.
    public var displayName: String {
        switch self {
        case .float32:  return "FP32 (Full)"
        case .float16:  return "FP16 (Half)"
        case .bfloat16: return "BF16"
        case .int8:     return "INT8"
        case .int4:     return "Q4_0"
        case .int4KM:   return "Q4_K_M"
        case .int4KS:   return "Q4_K_S"
        case .int3:     return "Q3_K_M"
        case .int2:     return "Q2_K"
        }
    }
}

// MARK: - ModelEngineKind

/// The type of AI engine that processes a model.
public enum ModelEngineKind: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case text    = "text"
    case image   = "image"
    case vision  = "vision"
    case speech  = "speech"
    case tts     = "tts"
    case audio   = "audio"
    case video   = "video"

    public var displayName: String {
        switch self {
        case .text:   return "Text"
        case .image:  return "Image"
        case .vision: return "Vision"
        case .speech: return "Speech"
        case .tts:    return "TTS"
        case .audio:  return "Audio"
        case .video:  return "Video"
        }
    }

    public var iconName: String {
        switch self {
        case .text:   return "text.bubble"
        case .image:  return "photo.artframe"
        case .vision: return "eye"
        case .speech: return "waveform"
        case .tts:    return "speaker.wave.3"
        case .audio:  return "headphones"
        case .video:  return "film"
        }
    }
}

// MARK: - ModelManifestFormat

/// The file format of a model package.
public enum ModelManifestFormat: String, Codable, Sendable, Equatable, Hashable {
    case gguf         = "gguf"
    case mlmodelc     = "mlmodelc"
    case safetensors  = "safetensors"
    case mlx          = "mlx"
    case onnx         = "onnx"
    case coreml       = "coreml"
}

// MARK: - ModelStatus

/// Lifecycle status of a model on the device.
public enum ModelStatus: Codable, Sendable, Equatable {
    case notInstalled
    case downloading(progress: Double)
    case verifying
    case installing
    case ready
    case loading
    case loaded
    case running
    case unloading
    case failed(String)
    case incompatible(String)
}

// MARK: - Empty result marker

public struct EmptyResult: Codable, Equatable, Sendable, Hashable {
    public init() {}
    public static let shared = EmptyResult()
}
