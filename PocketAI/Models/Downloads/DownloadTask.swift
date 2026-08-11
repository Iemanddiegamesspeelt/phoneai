import Foundation

// MARK: - DownloadTask

/// Represents a single model download with its lifecycle state.
public struct DownloadTask: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let modelId: String
    public let modelName: String
    public let remoteURL: URL
    public var state: DownloadState
    public var bytesWritten: Int64
    public var totalBytes: Int64
    public var speed: Double  // bytes per second
    public var startedAt: Date?
    public var completedAt: Date?
    public var error: String?

    public init(
        id: UUID = UUID(),
        modelId: String,
        modelName: String,
        remoteURL: URL
    ) {
        self.id = id
        self.modelId = modelId
        self.modelName = modelName
        self.remoteURL = remoteURL
        self.state = .queued
        self.bytesWritten = 0
        self.totalBytes = 0
        self.speed = 0
        self.startedAt = nil
        self.completedAt = nil
        self.error = nil
    }

    /// Fractional progress (0.0 to 1.0).
    public var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesWritten) / Double(totalBytes)
    }

    /// Formatted progress string (e.g., "1.56 GB / 2.00 GB").
    public var progressFormatted: String {
        "\(formatBytes(bytesWritten)) / \(formatBytes(totalBytes))"
    }

    /// Formatted speed string.
    public var speedFormatted: String {
        if speed > 1_048_576 {
            return String(format: "%.1f MB/s", speed / 1_048_576)
        } else if speed > 1024 {
            return String(format: "%.0f KB/s", speed / 1024)
        }
        return String(format: "%.0f B/s", speed)
    }

    /// Estimated time remaining.
    public var eta: TimeInterval? {
        guard speed > 0, totalBytes > bytesWritten else { return nil }
        return Double(totalBytes - bytesWritten) / speed
    }

    /// Formatted ETA string.
    public var etaFormatted: String {
        guard let eta = eta else { return "—" }
        if eta < 60 {
            return String(format: "%.0f sec", eta)
        } else if eta < 3600 {
            return String(format: "%.0f min", eta / 60)
        }
        return String(format: "%.1f hr", eta / 3600)
    }

    /// Formatted percentage.
    public var percentFormatted: String {
        "\(Int(progress * 100))%"
    }
}

// MARK: - DownloadState

/// State machine for a download task.
public enum DownloadState: Sendable, Equatable {
    case queued
    case downloading
    case paused
    case verifying
    case completed(localURL: URL)
    case failed(message: String)
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        default: return false
        }
    }

    public var displayName: String {
        switch self {
        case .queued:      return "Queued"
        case .downloading: return "Downloading"
        case .paused:      return "Paused"
        case .verifying:   return "Verifying"
        case .completed:   return "Complete"
        case .failed:      return "Failed"
        case .cancelled:   return "Cancelled"
        }
    }
}
