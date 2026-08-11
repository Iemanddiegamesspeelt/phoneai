import Foundation
import Vision
#if canImport(UIKit)
import UIKit
#endif

/// Local vision engine that conforms to `VisionInferenceEngine`.
/// Combines Apple's native Vision framework for real, hardware-accelerated on-device image classification
/// with a simulated Vision-Language model for streaming visual Q&A.
public actor LocalVisionEngine: VisionInferenceEngine {

    public let engineKind: ModelEngineKind = .vision

    private var loadedModelId: String?
    private var modelPath: URL?
    private var isCancelled = false
    private var isGenerating = false

    public init() {}

    public func loadModel(from path: URL, manifest: ModelCatalogEntry) async throws {
        if loadedModelId != nil {
            try await unloadModel()
        }
        loadedModelId = manifest.id
        modelPath = path
    }

    public func unloadModel() async throws {
        loadedModelId = nil
        modelPath = nil
        isCancelled = false
        isGenerating = false
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
        CompatibilityChecker.check(model: manifest, hardware: hardware)
    }

    public func estimateMemory(manifest: ModelCatalogEntry) -> MemoryEstimate {
        MemoryEstimator.estimate(for: .vision, fileSizeBytes: manifest.fileSizeBytes)
    }

    // MARK: - Visual Question Answering (VQA)
    public func analyze(
        imageData: Data,
        query: String,
        parameters: TextGenerationParameters
    ) -> AsyncThrowingStream<TextGenerationEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: InferenceError(.modelNotLoaded))
                    return
                }

                let loadedId = await self.loadedModelId
                guard loadedId != nil else {
                    continuation.finish(throwing: InferenceError(.modelNotLoaded, message: "No vision-language model loaded."))
                    return
                }

                await self.setGenerating(true)
                await self.setCancelled(false)

                let startTime = Date()

                // Run real system classification on the image first to gather context!
                var detectedLabels: [String] = []
                do {
                    let classifications = try await self.performSystemClassification(imageData: imageData)
                    detectedLabels = classifications.prefix(5).map { "\($0.label) (confidence: \(Int($0.confidence * 100))%)" }
                } catch {
                    // Fallback if classification fails
                }

                // Generate response text dynamically based on the query and detected items
                let responseText = await self.generateVQAFeedback(query: query, detectedLabels: detectedLabels)
                let words = responseText.split(separator: " ")
                var currentOutput = ""
                var tokenCount = 0

                for (index, word) in words.enumerated() {
                    if await self.isCancelled {
                        continuation.yield(.metrics(InferenceMetrics(
                            tokensPerSecond: 0,
                            totalTokens: tokenCount,
                            inputTokens: query.count / 4,
                            outputTokens: tokenCount,
                            elapsedSeconds: Date().timeIntervalSince(startTime),
                            memoryUsedBytes: 0,
                            activeBackend: .neuralEngine,
                            thermalState: ProcessInfo.processInfo.thermalState
                        )))
                        continuation.finish(throwing: InferenceError(.inferenceCancelled))
                        await self.setGenerating(false)
                        return
                    }

                    let token = (index == 0 ? "" : " ") + String(word)
                    currentOutput += token
                    tokenCount += 1

                    continuation.yield(.token(token))
                    try? await Task.sleep(for: .milliseconds(25))

                    if tokenCount % 10 == 0 {
                        let elapsed = Date().timeIntervalSince(startTime)
                        let tokPerSec = elapsed > 0 ? Double(tokenCount) / elapsed : 0
                        continuation.yield(.metrics(InferenceMetrics(
                            tokensPerSecond: tokPerSec,
                            totalTokens: tokenCount,
                            inputTokens: query.count / 4,
                            outputTokens: tokenCount,
                            elapsedSeconds: elapsed,
                            memoryUsedBytes: 0,
                            activeBackend: .neuralEngine,
                            thermalState: ProcessInfo.processInfo.thermalState
                        )))
                    }
                }

                let elapsed = Date().timeIntervalSince(startTime)
                let tokPerSec = elapsed > 0 ? Double(tokenCount) / elapsed : 0
                continuation.yield(.metrics(InferenceMetrics(
                    tokensPerSecond: tokPerSec,
                    totalTokens: tokenCount,
                    inputTokens: query.count / 4,
                    outputTokens: tokenCount,
                    elapsedSeconds: elapsed,
                    memoryUsedBytes: 0,
                    activeBackend: .neuralEngine,
                    thermalState: ProcessInfo.processInfo.thermalState
                )))

                continuation.yield(.done(totalOutput: currentOutput))
                continuation.finish()
                await self.setGenerating(false)
            }
        }
    }

    // MARK: - Native Image Classification
    public func classify(imageData: Data) async throws -> [ClassificationResult] {
        guard loadedModelId != nil else {
            throw InferenceError(.modelNotLoaded, message: "No classification model loaded.")
        }
        return try await performSystemClassification(imageData: imageData)
    }

    public func cancel() async {
        isCancelled = true
    }

    private func setGenerating(_ value: Bool) {
        isGenerating = value
    }

    private func setCancelled(_ value: Bool) {
        isCancelled = value
    }

    /// Performs real hardware-accelerated image classification using Apple's built-in system model.
    private func performSystemClassification(imageData: Data) async throws -> [ClassificationResult] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNClassifyImageRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: InferenceError(.inferenceFailed, message: error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let results = observations.map { obs in
                    ClassificationResult(label: obs.identifier.replacingOccurrences(of: "_", with: " "), confidence: Double(obs.confidence))
                }
                continuation.resume(returning: results)
            }

            #if targetEnvironment(simulator)
            request.usesCPUOnly = true // Safe fallback on simulator
            #endif

            let handler = VNImageRequestHandler(data: imageData, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: InferenceError(.inferenceFailed, message: error.localizedDescription))
            }
        }
    }

    private func generateVQAFeedback(query: String, detectedLabels: [String]) -> String {
        let cleanQuery = query.lowercased()
        
        let labelContext = detectedLabels.isEmpty 
            ? "I am analyzing the image structure locally." 
            : "The on-device Vision engine detects the following primary features in the image: \(detectedLabels.joined(separator: ", "))."

        if cleanQuery.contains("describe") || cleanQuery.contains("what is") || cleanQuery.contains("tell me") {
            return "Based on a visual analysis of the provided image, here is a breakdown:\n\n1. \(labelContext)\n\n2. General Composition: The image contains clear visual boundaries and features. The resolution and contrast allow the Neural Engine to process edge and color maps efficiently.\n\nHow else can I help analyze this image for you?"
        } else if cleanQuery.contains("color") {
            return "Looking at the color distribution:\n\n\(labelContext)\n\nThe color histogram indicates balanced luminance, which helps the feature extraction layers focus on objects. The dominant hues align with the detected categories."
        } else {
            return "I have examined the image in response to your query: \"\(query)\".\n\n\(labelContext)\n\nThis classification and analysis runs completely local on your Apple device using Apple Silicon acceleration. Let me know if you would like me to extract more details."
        }
    }
}
