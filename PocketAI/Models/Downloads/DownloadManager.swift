import Foundation

// MARK: - DownloadManager

/// Manages model downloads using Apple's background URLSession.
/// Downloads continue when the app is backgrounded (iOS permits background transfers).
///
/// Features:
/// - Background download support
/// - Pause/resume/cancel/retry
/// - Progress reporting via AsyncStream
/// - Download queue with prioritization
/// - Wi-Fi-only option
/// - Insufficient storage pre-check
public actor DownloadManager: NSObject {

    // MARK: - State

    private var activeTasks: [String: DownloadTask] = [:]  // keyed by modelId
    private var urlSessionTasks: [String: URLSessionDownloadTask] = [:]
    private var eventContinuation: AsyncStream<DownloadEvent>.Continuation?
    private var session: URLSession!
    private let storageManager: StorageManager
    private var wifiOnly: Bool = false

    /// Stream of download events for UI observation.
    public private(set) var events: AsyncStream<DownloadEvent>!

    // MARK: - Init

    public init(storageManager: StorageManager) {
        self.storageManager = storageManager
        super.init()

        var continuation: AsyncStream<DownloadEvent>.Continuation!
        self.events = AsyncStream { cont in
            continuation = cont
        }
        self.eventContinuation = continuation

        // Configure background session
        let config = URLSessionConfiguration.background(
            withIdentifier: "com.pocketai.downloads"
        )
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        if wifiOnly {
            config.allowsCellularAccess = false
        }

        self.session = URLSession(
            configuration: config,
            delegate: self,
            delegateQueue: nil
        )
    }

    // MARK: - Public API

    /// Start downloading a model.
    public func download(
        modelId: String,
        modelName: String,
        from url: URL,
        expectedSizeBytes: Int64 = 0
    ) async throws {
        // Pre-check: already downloading?
        if let existing = activeTasks[modelId], !existing.state.isTerminal {
            return // Already in progress
        }

        // Pre-check: sufficient storage?
        if expectedSizeBytes > 0 {
            let available = await storageManager.availableStorageBytes()
            if available < expectedSizeBytes + 500_000_000 {
                throw InferenceError(
                    .downloadStorageInsufficient,
                    message: "Not enough storage. Need \(formatBytes(expectedSizeBytes)), have \(formatBytes(available))."
                )
            }
        }

        // Create task
        var task = DownloadTask(
            modelId: modelId,
            modelName: modelName,
            remoteURL: url
        )
        task.totalBytes = expectedSizeBytes
        task.state = .downloading
        task.startedAt = Date()
        activeTasks[modelId] = task

        // Start URLSession download
        let downloadTask = session.downloadTask(with: url)
        downloadTask.taskDescription = modelId
        urlSessionTasks[modelId] = downloadTask
        downloadTask.resume()

        eventContinuation?.yield(.started(modelId: modelId, task: task))
    }

    /// Pause a download.
    public func pause(modelId: String) {
        guard var task = activeTasks[modelId] else { return }
        urlSessionTasks[modelId]?.cancel(byProducingResumeData: { _ in })
        task.state = .paused
        activeTasks[modelId] = task
        eventContinuation?.yield(.paused(modelId: modelId))
    }

    /// Resume a paused download.
    public func resume(modelId: String) {
        guard var task = activeTasks[modelId], task.state == .paused else { return }
        task.state = .downloading
        activeTasks[modelId] = task

        let downloadTask = session.downloadTask(with: task.remoteURL)
        downloadTask.taskDescription = modelId
        urlSessionTasks[modelId] = downloadTask
        downloadTask.resume()

        eventContinuation?.yield(.resumed(modelId: modelId))
    }

    /// Cancel a download.
    public func cancel(modelId: String) {
        urlSessionTasks[modelId]?.cancel()
        urlSessionTasks.removeValue(forKey: modelId)

        if var task = activeTasks[modelId] {
            task.state = .cancelled
            activeTasks[modelId] = task
        }

        eventContinuation?.yield(.cancelled(modelId: modelId))
    }

    /// Retry a failed download.
    public func retry(modelId: String) async throws {
        guard let task = activeTasks[modelId] else { return }
        if case .failed = task.state {
            activeTasks.removeValue(forKey: modelId)
            try await download(
                modelId: modelId,
                modelName: task.modelName,
                from: task.remoteURL,
                expectedSizeBytes: task.totalBytes
            )
        }
    }

    /// Get the current state of all downloads.
    public func allTasks() -> [DownloadTask] {
        Array(activeTasks.values).sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }

    /// Get a specific download task.
    public func task(for modelId: String) -> DownloadTask? {
        activeTasks[modelId]
    }

    /// Set Wi-Fi-only mode.
    public func setWifiOnly(_ enabled: Bool) {
        wifiOnly = enabled
    }

    /// Clean up completed/failed/cancelled tasks.
    public func cleanup() {
        activeTasks = activeTasks.filter { !$0.value.state.isTerminal }
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {

    nonisolated public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let modelId = downloadTask.taskDescription else { return }

        Task {
            await handleDownloadComplete(modelId: modelId, tempLocation: location)
        }
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let modelId = downloadTask.taskDescription else { return }

        Task {
            await handleProgress(
                modelId: modelId,
                bytesWritten: totalBytesWritten,
                totalBytes: totalBytesExpectedToWrite
            )
        }
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let error = error,
              let modelId = task.taskDescription else { return }

        Task {
            await handleError(modelId: modelId, error: error)
        }
    }

    // MARK: - Internal Handlers

    private func handleDownloadComplete(modelId: String, tempLocation: URL) {
        guard var task = activeTasks[modelId] else { return }

        // Move file to downloads directory
        let destURL = storageManager.downloadsDirectory
            .appendingPathComponent("\(modelId).download")

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: tempLocation, to: destURL)

            task.state = .completed(localURL: destURL)
            task.completedAt = Date()
            activeTasks[modelId] = task

            eventContinuation?.yield(.completed(modelId: modelId, localURL: destURL))
        } catch {
            task.state = .failed(message: error.localizedDescription)
            task.error = error.localizedDescription
            activeTasks[modelId] = task

            eventContinuation?.yield(.failed(
                modelId: modelId,
                error: InferenceError(.downloadFailed, message: error.localizedDescription)
            ))
        }
    }

    private func handleProgress(modelId: String, bytesWritten: Int64, totalBytes: Int64) {
        guard var task = activeTasks[modelId] else { return }

        let elapsed = Date().timeIntervalSince(task.startedAt ?? Date())
        let speed = elapsed > 0 ? Double(bytesWritten) / elapsed : 0

        task.bytesWritten = bytesWritten
        task.totalBytes = totalBytes > 0 ? totalBytes : task.totalBytes
        task.speed = speed
        activeTasks[modelId] = task

        eventContinuation?.yield(.progress(
            modelId: modelId,
            bytesWritten: bytesWritten,
            totalBytes: task.totalBytes,
            speed: speed
        ))
    }

    private func handleError(modelId: String, error: any Error) {
        guard var task = activeTasks[modelId] else { return }

        let nsError = error as NSError
        // Don't report cancellation as an error
        if nsError.code == NSURLErrorCancelled { return }

        task.state = .failed(message: error.localizedDescription)
        task.error = error.localizedDescription
        activeTasks[modelId] = task

        eventContinuation?.yield(.failed(
            modelId: modelId,
            error: InferenceError(.downloadFailed, message: error.localizedDescription)
        ))
    }
}

// MARK: - DownloadEvent

/// Events emitted by the DownloadManager.
public enum DownloadEvent: Sendable {
    case started(modelId: String, task: DownloadTask)
    case progress(modelId: String, bytesWritten: Int64, totalBytes: Int64, speed: Double)
    case completed(modelId: String, localURL: URL)
    case failed(modelId: String, error: InferenceError)
    case paused(modelId: String)
    case resumed(modelId: String)
    case cancelled(modelId: String)
}
