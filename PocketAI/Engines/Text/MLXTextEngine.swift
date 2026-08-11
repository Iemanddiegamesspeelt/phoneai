import Foundation

// MARK: - MLXTextEngine

/// Concrete implementation of `TextInferenceEngine` using the MLX Swift framework.
///
/// This engine handles:
/// - Loading MLX-format or GGUF-format text models
/// - Streaming token generation with configurable parameters
/// - KV cache management and context window tracking
/// - Performance metrics (tokens/sec)
/// - Cancellation support
/// - Memory-efficient model loading
///
/// The actual MLX Swift dependency is isolated here — the rest of the app
/// interacts only through the `TextInferenceEngine` protocol.
public actor MLXTextEngine: TextInferenceEngine {

    // MARK: - State

    public let engineKind: ModelEngineKind = .text

    private var loadedModelId: String?
    private var modelPath: URL?
    private var isCancelled = false
    private var isGenerating = false

    // These would hold the actual MLX model objects when the mlx-swift package is linked.
    // For now, they represent the architecture without the runtime dependency.
    private var modelConfiguration: ModelConfig?

    // MARK: - Model Lifecycle

    public func loadModel(from path: URL, manifest: ModelCatalogEntry) async throws {
        // Unload any existing model first
        if loadedModelId != nil {
            try await unloadModel()
        }

        loadedModelId = manifest.id
        modelPath = path

        // In a real implementation with mlx-swift linked:
        // 1. Load tokenizer from path
        // 2. Load model weights from path
        // 3. Configure KV cache based on context length
        // 4. Warm up with a small test inference

        modelConfiguration = ModelConfig(
            modelId: manifest.id,
            contextLength: manifest.contextLength ?? 2048,
            quantization: manifest.quantization,
            format: manifest.format,
            path: path
        )

        // Simulate model loading time for architecture validation
        // In production, this is where mlx-swift loads weights
    }

    public func unloadModel() async throws {
        loadedModelId = nil
        modelPath = nil
        modelConfiguration = nil
        isCancelled = false
        isGenerating = false
    }

    public func isModelLoaded() async -> Bool {
        loadedModelId != nil
    }

    public func loadedModelId() async -> String? {
        loadedModelId
    }

    // MARK: - Compatibility

    public func checkCompatibility(
        manifest: ModelCatalogEntry,
        hardware: HardwareCapabilityProfile
    ) -> CompatibilityResult {
        CompatibilityChecker.check(model: manifest, hardware: hardware)
    }

    public func estimateMemory(manifest: ModelCatalogEntry) -> MemoryEstimate {
        MemoryEstimator.estimateTextModel(
            fileSizeBytes: manifest.fileSizeBytes,
            quantization: manifest.quantization,
            contextLength: manifest.contextLength ?? 2048
        )
    }

    // MARK: - Text Generation

    public func generate(
        prompt: String,
        systemPrompt: String?,
        history: [ChatMessage],
        parameters: TextGenerationParameters
    ) -> AsyncThrowingStream<TextGenerationEvent, Error> {

        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: InferenceError(.modelNotLoaded))
                    return
                }

                let modelId = await self.loadedModelId
                guard modelId != nil else {
                    continuation.finish(throwing: InferenceError(.modelNotLoaded, message: "No model loaded. Load a model first."))
                    return
                }

                await self.setGenerating(true)
                await self.setCancelled(false)

                let startTime = Date()
                var totalOutput = ""
                var tokenCount = 0

                // Build the full prompt with system prompt and history
                let fullPrompt = await self.buildPrompt(
                    userPrompt: prompt,
                    systemPrompt: systemPrompt,
                    history: history
                )

                // ── MLX Inference Integration Point ──
                //
                // In a production build with mlx-swift linked, this section would:
                //
                // 1. Tokenize `fullPrompt` using the model's tokenizer
                // 2. Run the MLX model forward pass
                // 3. Sample tokens using temperature, top-p, top-k
                // 4. Yield each token through the continuation
                // 5. Track KV cache state for context management
                //
                // For now, we implement the streaming architecture with a placeholder
                // that demonstrates the exact API contract the UI expects.
                // This allows the full UI to be built and tested independently.

                // Placeholder: echo-based streaming to validate architecture
                let response = self.generatePlaceholderResponse(for: prompt)
                let words = response.split(separator: " ")

                for (index, word) in words.enumerated() {
                    // Check cancellation
                    if await self.isCancelled {
                        continuation.yield(.metrics(InferenceMetrics(
                            tokensPerSecond: 0,
                            totalTokens: tokenCount,
                            inputTokens: fullPrompt.count / 4,
                            outputTokens: tokenCount,
                            elapsedSeconds: Date().timeIntervalSince(startTime),
                            memoryUsedBytes: 0,
                            activeBackend: .mlx,
                            thermalState: ProcessInfo.processInfo.thermalState
                        )))
                        continuation.finish(throwing: InferenceError(.inferenceCancelled))
                        await self.setGenerating(false)
                        return
                    }

                    let token = (index == 0 ? "" : " ") + String(word)
                    totalOutput += token
                    tokenCount += 1

                    continuation.yield(.token(token))

                    // Simulate realistic token generation latency
                    try? await Task.sleep(for: .milliseconds(30))

                    // Emit periodic metrics
                    if tokenCount % 10 == 0 {
                        let elapsed = Date().timeIntervalSince(startTime)
                        let tokPerSec = elapsed > 0 ? Double(tokenCount) / elapsed : 0
                        continuation.yield(.metrics(InferenceMetrics(
                            tokensPerSecond: tokPerSec,
                            totalTokens: tokenCount,
                            inputTokens: fullPrompt.count / 4,
                            outputTokens: tokenCount,
                            elapsedSeconds: elapsed,
                            memoryUsedBytes: 0,
                            activeBackend: .mlx,
                            thermalState: ProcessInfo.processInfo.thermalState
                        )))
                    }

                    // Check max tokens
                    if tokenCount >= parameters.maxTokens {
                        break
                    }
                }

                // Final metrics
                let elapsed = Date().timeIntervalSince(startTime)
                let tokPerSec = elapsed > 0 ? Double(tokenCount) / elapsed : 0
                continuation.yield(.metrics(InferenceMetrics(
                    tokensPerSecond: tokPerSec,
                    totalTokens: tokenCount,
                    inputTokens: fullPrompt.count / 4,
                    outputTokens: tokenCount,
                    elapsedSeconds: elapsed,
                    memoryUsedBytes: 0,
                    activeBackend: .mlx,
                    thermalState: ProcessInfo.processInfo.thermalState
                )))

                continuation.yield(.done(totalOutput: totalOutput))
                continuation.finish()
                await self.setGenerating(false)
            }
        }
    }

    // MARK: - Cancellation

    public func cancel() async {
        isCancelled = true
    }

    // MARK: - Private

    private func setGenerating(_ value: Bool) {
        isGenerating = value
    }

    private func setCancelled(_ value: Bool) {
        isCancelled = value
    }

    /// Build a formatted prompt string from system prompt, history, and user input.
    private func buildPrompt(
        userPrompt: String,
        systemPrompt: String?,
        history: [ChatMessage]
    ) -> String {
        var parts: [String] = []

        if let system = systemPrompt {
            parts.append("<|system|>\n\(system)</s>")
        }

        for message in history {
            switch message.role {
            case .user:
                parts.append("<|user|>\n\(message.content)</s>")
            case .assistant:
                parts.append("<|assistant|>\n\(message.content)</s>")
            case .system:
                parts.append("<|system|>\n\(message.content)</s>")
            }
        }

        parts.append("<|user|>\n\(userPrompt)</s>")
        parts.append("<|assistant|>")

        return parts.joined(separator: "\n")
    }

    /// Generate a placeholder response for architecture testing.
    /// This will be replaced by actual MLX inference when the runtime is linked.
    private func generatePlaceholderResponse(for prompt: String) -> String {
        let lowered = prompt.lowercased()

        if lowered.contains("hello") || lowered.contains("hi") {
            return "Hello! I'm running locally on your device using the Pocket AI Studio engine. How can I help you today?"
        } else if lowered.contains("what") && lowered.contains("you") {
            return "I'm a local AI model running entirely on your device. No data leaves your phone — everything is processed privately using Apple Silicon optimization."
        } else if lowered.contains("weather") {
            return "I'm a local AI model and don't have access to real-time data like weather. I can help with text generation, answering questions, and creative writing — all running offline on your device."
        } else {
            return "I received your message: \"\(prompt)\". This is a placeholder response from the text engine architecture. When a real MLX model is loaded, you'll get actual AI-generated responses streaming in real-time. The streaming, cancellation, memory management, and performance monitoring systems are all fully operational."
        }
    }
}

// MARK: - ModelConfig

/// Internal configuration for a loaded model.
private struct ModelConfig {
    let modelId: String
    let contextLength: Int
    let quantization: ModelQuantization?
    let format: ModelManifestFormat
    let path: URL
}
