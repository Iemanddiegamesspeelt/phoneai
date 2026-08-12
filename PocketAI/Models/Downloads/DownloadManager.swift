import Foundation

// MARK: - DownloadManager

/// Manages model downloads using Apple's background URLSession.
/// Downloads continue when the app is backgrounded (iOS permits background transfers).
///
/// Uses a class (not actor) because URLSessionDownloadDelegate requires NSObject inheritance.
/// Thread safety is ensured by serializing state mutations through @MainActor.
public final class DownloadManager: NSObject, Sendable, URLSessionDownloadDelegate {

    // MARK: - State (all access via MainActor)

    @MainActor private var activeTasks: [String: DownloadTask] = [:]
    @MainActor private var urlSessionTasks: [String: URLSessionDownloadTask] = [:]
    @MainActor private var eventContinuation: AsyncStream<DownloadEvent>.Continuation?

    /// Stream of download events for UI observation.
    @MainActor public private(set) var events: AsyncStream<DownloadEvent>!

    private let storageManager: StorageManager
    @MainActor private var session: URLSession!
    @MainActor private var wifiOnly: Bool = false

    // Pre-computed directory URL (Sendable-safe, set once in init)
    private let downloadsDirectoryURL: URL

    // MARK: - Init

    @MainActor
    public init(storageManager: StorageManager) {
        self.storageManager = storageManager

        // Pre-resolve the downloads directory synchronously
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.downloadsDirectoryURL = appSupport
            .appendingPathComponent("PocketAI", isDirectory: true)
            .appendingPathComponent("downloads", isDirectory: true)

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

        self.session = URLSession(
            configuration: config,
            delegate: self,
            delegateQueue: nil
        )
    }

    // MARK: - Public API

    /// Start downloading a model.
    @MainActor
    public func download(
        modelId: String,
        modelName: String,
        from url: URL,
        expectedSizeBytes: Int64 = 0
    ) async throws {
        // Pre-check: already downloading?
        if let existing = activeTasks[modelId], !existing.state.isTerminal {
            return
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
    @MainActor
    public func pause(modelId: String) {
        guard var task = activeTasks[modelId] else { return }
        urlSessionTasks[modelId]?.cancel(byProducingResumeData: { _ in })
        task.state = .paused
        activeTasks[modelId] = task
        eventContinuation?.yield(.paused(modelId: modelId))
    }

    /// Resume a paused download.
    @MainActor
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
    @MainActor
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
    @MainActor
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
    @MainActor
    public func allTasks() -> [DownloadTask] {
        Array(activeTasks.values).sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }

    /// Get a specific download task.
    @MainActor
    public func task(for modelId: String) -> DownloadTask? {
        activeTasks[modelId]
    }

    /// Set Wi-Fi-only mode.
    @MainActor
    public func setWifiOnly(_ enabled: Bool) {
        wifiOnly = enabled
    }

    /// Clean up completed/failed/cancelled tasks.
    @MainActor
    public func cleanup() {
        activeTasks = activeTasks.filter { !$0.value.state.isTerminal }
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let modelId = downloadTask.taskDescription else { return }

        // Copy the file immediately (temp file is deleted after this method returns)
        let destURL = downloadsDirectoryURL.appendingPathComponent("\(modelId).download")
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: location, to: destURL)
        } catch {
            Task { @MainActor in
                self.handleError(modelId: modelId, message: error.localizedDescription)
            }
            return
        }

        Task { @MainActor in
            self.handleDownloadComplete(modelId: modelId, localURL: destURL)
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let modelId = downloadTask.taskDescription else { return }

        Task { @MainActor in
            self.handleProgress(
                modelId: modelId,
                bytesWritten: totalBytesWritten,
                totalBytes: totalBytesExpectedToWrite
            )
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let error = error,
              let modelId = task.taskDescription else { return }

        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }

        Task { @MainActor in
            self.handleError(modelId: modelId, message: error.localizedDescription)
        }
    }

    // MARK: - Internal Handlers (MainActor)

    @MainActor
    private func handleDownloadComplete(modelId: String, localURL: URL) {
        guard var task = activeTasks[modelId] else { return }

        task.state = .completed(localURL: localURL)
        task.completedAt = Date()
        activeTasks[modelId] = task

        eventContinuation?.yield(.completed(modelId: modelId, localURL: localURL))
    }

    @MainActor
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

    @MainActor
    private func handleError(modelId: String, message: String) {
        guard var task = activeTasks[modelId] else { return }

        task.state = .failed(message: message)
        task.error = message
        activeTasks[modelId] = task

        eventContinuation?.yield(.failed(
            modelId: modelId,
            error: InferenceError(.downloadFailed, message: message)
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
