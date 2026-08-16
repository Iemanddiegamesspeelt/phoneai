import Foundation
import CryptoKit

// MARK: - StorageManager

/// Manages model file storage on device: installation paths, integrity verification,
/// storage queries, and cleanup.
public actor StorageManager {

    /// The root directory for all installed models.
    nonisolated public let modelsDirectory: URL

    /// The root directory for in-progress downloads.
    nonisolated public let downloadsDirectory: URL

    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        self.modelsDirectory = appSupport
            .appendingPathComponent("PocketAI", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)

        self.downloadsDirectory = appSupport
            .appendingPathComponent("PocketAI", isDirectory: true)
            .appendingPathComponent("downloads", isDirectory: true)

        // Ensure directories exist
        let fm = FileManager.default
        try? fm.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Storage Queries

    /// Available storage on the device for model downloads.
    public func availableStorageBytes() -> Int64 {
        do {
            let homeURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try homeURL.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            )
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            return 0
        }
    }

    /// Total bytes used by all installed models.
    public func totalInstalledBytes() -> Int64 {
        directorySize(at: modelsDirectory)
    }

    /// Total bytes used by in-progress downloads.
    public func totalDownloadBytes() -> Int64 {
        directorySize(at: downloadsDirectory)
    }

    /// Whether there's enough storage for a download of the given size.
    public func hasStorageFor(bytes: Int64) -> Bool {
        availableStorageBytes() > bytes + 500_000_000 // 500 MB buffer
    }

    // MARK: - Model File Management

    /// Path where a model should be installed.
    public func modelPath(for modelId: String) -> URL {
        modelsDirectory.appendingPathComponent(modelId, isDirectory: true)
    }

    /// Check if a model is installed.
    public func isModelInstalled(_ modelId: String) -> Bool {
        let path = modelPath(for: modelId)
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// List all installed model IDs.
    public func installedModelIds() -> [String] {
        let fm = FileManager.default
        do {
            let contents = try fm.contentsOfDirectory(
                at: modelsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            return contents.compactMap { url in
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
                    ? url.lastPathComponent
                    : nil
            }
        } catch {
            return []
        }
    }

    /// Size of a specific installed model in bytes.
    public func modelSizeBytes(_ modelId: String) -> Int64 {
        directorySize(at: modelPath(for: modelId))
    }

    /// Delete an installed model.
    public func deleteModel(_ modelId: String) throws {
        let path = modelPath(for: modelId)
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        try FileManager.default.removeItem(at: path)
    }

    /// Move a downloaded file to the model installation directory.
    public func installModel(from downloadURL: URL, modelId: String) throws -> URL {
        let destination = modelPath(for: modelId)

        // Remove existing installation if any
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )

        // If it's a single file, move it into the directory
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: downloadURL.path, isDirectory: &isDir)

        if isDir.boolValue {
            // Move contents of directory
            let contents = try FileManager.default.contentsOfDirectory(
                at: downloadURL,
                includingPropertiesForKeys: nil
            )
            for item in contents {
                let dest = destination.appendingPathComponent(item.lastPathComponent)
                try FileManager.default.moveItem(at: item, to: dest)
            }
        } else {
            // Move single file
            let dest = destination.appendingPathComponent(downloadURL.lastPathComponent)
            try FileManager.default.moveItem(at: downloadURL, to: dest)
        }

        return destination
    }

    // MARK: - Integrity Verification

    /// Compute SHA256 hash of a file.
    public func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { handle.closeFile() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 1_048_576) // 1 MB chunks
            if data.isEmpty { return false }
            hasher.update(data: data)
            return true
        }) {}

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Verify a file's checksum.
    public func verifyChecksum(
        fileURL: URL,
        expectedSHA256: String
    ) throws -> Bool {
        let actual = try sha256(of: fileURL)
        return actual.lowercased() == expectedSHA256.lowercased()
    }

    /// Clean up partial/orphaned downloads.
    public func cleanupDownloads() throws {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: downloadsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        // Remove downloads older than 24 hours (likely failed/abandoned)
        let threshold = Date().addingTimeInterval(-86400)
        for url in contents {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values.contentModificationDate, modified < threshold {
                try fm.removeItem(at: url)
            }
        }
    }

    // MARK: - Private Helpers

    /// Calculate the total size of a directory recursively.
    private func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
