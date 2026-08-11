import Foundation

// MARK: - CatalogService

/// The app's model catalog — loads entries from a bundled JSON manifest
/// with support for remote updates. Acts as the single source of truth
/// for what models are available.
public actor CatalogService: ModelCatalogProvider {

    private var entries: [ModelCatalogEntry] = []
    private let bundledCatalogURL: URL?
    private let remoteUpdateURL: URL?
    private let cacheDirectory: URL
    private var lastLoadDate: Date?

    // MARK: - Init

    public init(
        bundledCatalogURL: URL? = Bundle.main.url(forResource: "catalog", withExtension: "json"),
        remoteUpdateURL: URL? = nil
    ) {
        self.bundledCatalogURL = bundledCatalogURL
        self.remoteUpdateURL = remoteUpdateURL

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.pocketai.catalog", isDirectory: true)
        self.cacheDirectory = cacheDir
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - ModelCatalogProvider

    public func fetchEntries() async throws -> [ModelCatalogEntry] {
        if entries.isEmpty {
            try await loadCatalog()
        }
        return entries
    }

    public func entry(withId id: String) async -> ModelCatalogEntry? {
        entries.first { $0.id == id }
    }

    public func entries(for engineKind: ModelEngineKind) async -> [ModelCatalogEntry] {
        entries.filter { $0.engineKind == engineKind }
    }

    public func refresh() async throws {
        try await loadCatalog()
    }

    // MARK: - Filtered Accessors

    /// Get entries grouped by engine kind.
    public func groupedByEngine() -> [ModelEngineKind: [ModelCatalogEntry]] {
        Dictionary(grouping: entries, by: \.engineKind)
    }

    /// Get all text models.
    public var textModels: [ModelCatalogEntry] {
        entries.filter { $0.engineKind == .text }
    }

    /// Get all image models.
    public var imageModels: [ModelCatalogEntry] {
        entries.filter { $0.engineKind == .image }
    }

    /// Get all vision models.
    public var visionModels: [ModelCatalogEntry] {
        entries.filter { $0.engineKind == .vision }
    }

    /// Get all speech models.
    public var speechModels: [ModelCatalogEntry] {
        entries.filter { $0.engineKind == .speech }
    }

    /// Get all TTS models.
    public var ttsModels: [ModelCatalogEntry] {
        entries.filter { $0.engineKind == .tts }
    }

    // MARK: - Loading

    private func loadCatalog() async throws {
        // Try remote first, then cache, then bundled
        if let remote = remoteUpdateURL {
            do {
                let data = try await fetchRemote(url: remote)
                let decoded = try decodeCatalog(data)
                try cacheData(data)
                entries = decoded
                lastLoadDate = Date()
                return
            } catch {
                // Fall through to cache/bundled
            }
        }

        // Try cached version
        if let cached = try? loadCached() {
            entries = cached
            lastLoadDate = Date()
            return
        }

        // Bundled fallback
        guard let bundled = bundledCatalogURL else {
            entries = Self.builtInCatalog()
            lastLoadDate = Date()
            return
        }

        let data = try Data(contentsOf: bundled)
        entries = try decodeCatalog(data)
        lastLoadDate = Date()
    }

    private func fetchRemote(url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func cacheData(_ data: Data) throws {
        let url = cacheDirectory.appendingPathComponent("catalog.json")
        try data.write(to: url, options: .atomic)
    }

    private func loadCached() throws -> [ModelCatalogEntry]? {
        let url = cacheDirectory.appendingPathComponent("catalog.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decodeCatalog(data)
    }

    private func decodeCatalog(_ data: Data) throws -> [ModelCatalogEntry] {
        struct CatalogWrapper: Codable {
            let version: Int
            let entries: [ModelCatalogEntry]
        }
        let wrapper = try JSONDecoder().decode(CatalogWrapper.self, from: data)
        return wrapper.entries
    }

    // MARK: - Built-in Catalog

    /// Hardcoded fallback catalog when no JSON is available.
    /// This ensures the app always has models to show.
    public static func builtInCatalog() -> [ModelCatalogEntry] {
        var catalog: [ModelCatalogEntry] = []

        // ── TEXT MODELS ──
        catalog.append(contentsOf: [
            ModelCatalogEntry(
                id: "smollm2-135m-instruct-q4",
                name: "SmolLM2 135M Instruct",
                developer: "HuggingFace",
                engineKind: .text,
                taskDescription: "Fast text generation, simple Q&A",
                fileSizeBytes: 100_000_000,
                downloadSizeBytes: 85_000_000,
                format: .mlx,
                quantization: .int4KM,
                minimumRAMBytes: 1_000_000_000,
                recommendedRAMBytes: 2_000_000_000,
                contextLength: 2048,
                license: "Apache 2.0",
                downloadURL: "https://huggingface.co/mlx-community/SmolLM2-135M-Instruct-4bit",
                description: "Ultra-lightweight model that runs on any device. Great for quick tasks.",
                tags: ["tiny", "fast", "starter"]
            ),
            ModelCatalogEntry(
                id: "smollm2-360m-instruct-q4",
                name: "SmolLM2 360M Instruct",
                developer: "HuggingFace",
                engineKind: .text,
                taskDescription: "Text generation, Q&A, summarization",
                fileSizeBytes: 220_000_000,
                downloadSizeBytes: 200_000_000,
                format: .mlx,
                quantization: .int4KM,
                minimumRAMBytes: 2_000_000_000,
                recommendedRAMBytes: 3_000_000_000,
                contextLength: 2048,
                license: "Apache 2.0",
                downloadURL: "https://huggingface.co/mlx-community/SmolLM2-360M-Instruct-4bit",
                description: "Balanced small model with better coherence than the 135M variant.",
                tags: ["small", "balanced"]
            ),
            ModelCatalogEntry(
                id: "qwen25-05b-instruct-q4",
                name: "Qwen2.5 0.5B Instruct",
                developer: "Alibaba",
                engineKind: .text,
                taskDescription: "Chat, Q&A, reasoning, code",
                fileSizeBytes: 400_000_000,
                downloadSizeBytes: 350_000_000,
                format: .mlx,
                quantization: .int4KM,
                minimumRAMBytes: 2_000_000_000,
                recommendedRAMBytes: 3_000_000_000,
                contextLength: 4096,
                license: "Apache 2.0",
                downloadURL: "https://huggingface.co/mlx-community/Qwen2.5-0.5B-Instruct-4bit",
                description: "Excellent small model by Alibaba. Strong multilingual and coding ability.",
                tags: ["popular", "multilingual", "code"]
            ),
            ModelCatalogEntry(
                id: "qwen25-15b-instruct-q4",
                name: "Qwen2.5 1.5B Instruct",
                developer: "Alibaba",
                engineKind: .text,
                taskDescription: "Advanced chat, reasoning, code, math",
                fileSizeBytes: 1_000_000_000,
                downloadSizeBytes: 900_000_000,
                format: .mlx,
                quantization: .int4KM,
                minimumRAMBytes: 3_000_000_000,
                recommendedRAMBytes: 4_000_000_000,
                contextLength: 8192,
                license: "Apache 2.0",
                downloadURL: "https://huggingface.co/mlx-community/Qwen2.5-1.5B-Instruct-4bit",
                description: "High-quality 1.5B model with excellent reasoning and multilingual support.",
                tags: ["popular", "recommended", "multilingual"]
            ),
            ModelCatalogEntry(
                id: "smollm2-17b-instruct-q4",
                name: "SmolLM2 1.7B Instruct",
                developer: "HuggingFace",
                engineKind: .text,
                taskDescription: "General text generation, long-form writing",
                fileSizeBytes: 1_100_000_000,
                downloadSizeBytes: 1_000_000_000,
                format: .mlx,
                quantization: .int4KM,
                minimumRAMBytes: 3_000_000_000,
                recommendedRAMBytes: 4_000_000_000,
                contextLength: 4096,
                license: "Apache 2.0",
                downloadURL: "https://huggingface.co/mlx-community/SmolLM2-1.7B-Instruct-4bit",
                description: "Compact yet capable model for general text generation tasks.",
                tags: ["balanced", "writing"]
            ),
            ModelCatalogEntry(
                id: "tinyllama-11b-q4",
                name: "TinyLlama 1.1B",
                developer: "TinyLlama Project",
                engineKind: .text,
                taskDescription: "Chat, text completion",
                fileSizeBytes: 700_000_000,
                downloadSizeBytes: 640_000_000,
                format: .gguf,
                quantization: .int4KM,
                minimumRAMBytes: 2_000_000_000,
                recommendedRAMBytes: 3_000_000_000,
                contextLength: 2048,
                license: "Apache 2.0",
                downloadURL: "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF",
                description: "Classic tiny Llama model. Fast and lightweight.",
                tags: ["classic", "fast"]
            ),
            ModelCatalogEntry(
                id: "llama32-1b-instruct-q4",
                name: "Llama 3.2 1B Instruct",
                developer: "Meta",
                engineKind: .text,
                taskDescription: "Chat, reasoning, tool use",
                fileSizeBytes: 750_000_000,
                downloadSizeBytes: 700_000_000,
                format: .mlx,
                quantization: .int4KM,
                minimumRAMBytes: 3_000_000_000,
                recommendedRAMBytes: 4_000_000_000,
                contextLength: 8192,
                license: "Llama 3.2 Community",
                downloadURL: "https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit",
                description: "Meta's compact Llama 3.2 with strong instruction following.",
                tags: ["popular", "meta"]
            ),
            ModelCatalogEntry(
                id: "llama32-3b-instruct-q4",
                name: "Llama 3.2 3B Instruct",
                developer: "Meta",
                engineKind: .text,
                taskDescription: "Advanced chat, reasoning, analysis",
                fileSizeBytes: 2_000_000_000,
                downloadSizeBytes: 1_800_000_000,
                format: .mlx,
                quantization: .int4KM,
                minimumRAMBytes: 4_000_000_000,
                recommendedRAMBytes: 6_000_000_000,
                contextLength: 8192,
                license: "Llama 3.2 Community",
                downloadURL: "https://huggingface.co/mlx-community/Llama-3.2-3B-Instruct-4bit",
                description: "Meta's most capable mobile-friendly Llama. Excellent quality.",
                tags: ["high-quality", "meta", "creator"]
            ),
            ModelCatalogEntry(
                id: "phi35-mini-instruct-q4",
                name: "Phi-3.5 Mini Instruct",
                developer: "Microsoft",
                engineKind: .text,
                taskDescription: "Chat, reasoning, code, math",
                fileSizeBytes: 2_200_000_000,
                downloadSizeBytes: 2_000_000_000,
                format: .mlx,
                quantization: .int4KM,
                minimumRAMBytes: 4_000_000_000,
                recommendedRAMBytes: 6_000_000_000,
                contextLength: 4096,
                license: "MIT",
                downloadURL: "https://huggingface.co/mlx-community/Phi-3.5-mini-instruct-4bit",
                description: "Microsoft's powerful mini model. Excellent at reasoning and code.",
                tags: ["powerful", "microsoft", "code", "creator"]
            ),
            ModelCatalogEntry(
                id: "gemma-2b-instruct-q4",
                name: "Gemma 2B Instruct",
                developer: "Google",
                engineKind: .text,
                taskDescription: "Chat, creative writing, Q&A",
                fileSizeBytes: 1_500_000_000,
                downloadSizeBytes: 1_400_000_000,
                format: .mlx,
                quantization: .int4KM,
                minimumRAMBytes: 3_000_000_000,
                recommendedRAMBytes: 4_000_000_000,
                contextLength: 8192,
                license: "Gemma Terms of Use",
                downloadURL: "https://huggingface.co/mlx-community/gemma-2-2b-it-4bit",
                description: "Google's Gemma model optimized for instruction following.",
                tags: ["google", "balanced"]
            ),
        ])

        // ── SPEECH MODELS ──
        catalog.append(contentsOf: [
            ModelCatalogEntry(
                id: "whisper-tiny",
                name: "Whisper Tiny",
                developer: "OpenAI",
                engineKind: .speech,
                taskDescription: "Speech-to-text transcription",
                fileSizeBytes: 75_000_000,
                downloadSizeBytes: 75_000_000,
                format: .coreml,
                minimumRAMBytes: 1_000_000_000,
                recommendedRAMBytes: 2_000_000_000,
                license: "MIT",
                downloadURL: "https://huggingface.co/argmaxinc/whisperkit-coreml",
                description: "Ultra-fast speech recognition. Lower accuracy but runs on any device.",
                tags: ["tiny", "fast", "starter", "multilingual"]
            ),
            ModelCatalogEntry(
                id: "whisper-base",
                name: "Whisper Base",
                developer: "OpenAI",
                engineKind: .speech,
                taskDescription: "Speech-to-text transcription",
                fileSizeBytes: 145_000_000,
                downloadSizeBytes: 145_000_000,
                format: .coreml,
                minimumRAMBytes: 2_000_000_000,
                recommendedRAMBytes: 3_000_000_000,
                license: "MIT",
                downloadURL: "https://huggingface.co/argmaxinc/whisperkit-coreml",
                description: "Good balance of speed and accuracy for speech recognition.",
                tags: ["balanced", "multilingual"]
            ),
            ModelCatalogEntry(
                id: "whisper-small",
                name: "Whisper Small",
                developer: "OpenAI",
                engineKind: .speech,
                taskDescription: "High-quality speech-to-text",
                fileSizeBytes: 480_000_000,
                downloadSizeBytes: 480_000_000,
                format: .coreml,
                minimumRAMBytes: 3_000_000_000,
                recommendedRAMBytes: 4_000_000_000,
                license: "MIT",
                downloadURL: "https://huggingface.co/argmaxinc/whisperkit-coreml",
                description: "High accuracy speech recognition with multilingual support.",
                tags: ["high-quality", "multilingual", "creator"]
            ),
        ])

        // ── IMAGE MODELS ──
        catalog.append(contentsOf: [
            ModelCatalogEntry(
                id: "sd-15-coreml",
                name: "Stable Diffusion 1.5",
                developer: "Stability AI",
                engineKind: .image,
                taskDescription: "Text-to-image generation",
                fileSizeBytes: 2_000_000_000,
                downloadSizeBytes: 1_900_000_000,
                format: .coreml,
                minimumRAMBytes: 4_000_000_000,
                recommendedRAMBytes: 6_000_000_000,
                license: "CreativeML Open RAIL-M",
                downloadURL: "https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized",
                description: "Classic text-to-image model optimized for Apple Neural Engine.",
                tags: ["popular", "image-gen", "creator"]
            ),
            ModelCatalogEntry(
                id: "sd-turbo-coreml",
                name: "SD Turbo",
                developer: "Stability AI",
                engineKind: .image,
                taskDescription: "Fast text-to-image (1–4 steps)",
                fileSizeBytes: 2_200_000_000,
                downloadSizeBytes: 2_100_000_000,
                format: .coreml,
                minimumRAMBytes: 4_000_000_000,
                recommendedRAMBytes: 6_000_000_000,
                license: "Stability AI Community",
                downloadURL: "https://huggingface.co/apple/coreml-stable-diffusion-xl-turbo",
                description: "Ultra-fast image generation in just 1–4 steps.",
                tags: ["fast", "image-gen"]
            ),
        ])

        // ── VISION MODELS ──
        catalog.append(contentsOf: [
            ModelCatalogEntry(
                id: "mobileclip-s0",
                name: "MobileCLIP S0",
                developer: "Apple",
                engineKind: .vision,
                taskDescription: "Image classification, search",
                fileSizeBytes: 50_000_000,
                downloadSizeBytes: 50_000_000,
                format: .coreml,
                minimumRAMBytes: 1_000_000_000,
                recommendedRAMBytes: 2_000_000_000,
                license: "Apple Sample Code License",
                description: "Ultra-lightweight image understanding. Classify and search images.",
                tags: ["tiny", "fast", "starter", "classification"]
            ),
            ModelCatalogEntry(
                id: "mobilenet-v3",
                name: "MobileNet V3",
                developer: "Google",
                engineKind: .vision,
                taskDescription: "Image classification (1000 categories)",
                fileSizeBytes: 22_000_000,
                downloadSizeBytes: 22_000_000,
                format: .coreml,
                minimumRAMBytes: 1_000_000_000,
                recommendedRAMBytes: 1_000_000_000,
                license: "Apache 2.0",
                description: "Fast image classification across 1000 categories.",
                tags: ["tiny", "classification", "starter"]
            ),
        ])

        // ── TTS MODELS ──
        catalog.append(contentsOf: [
            ModelCatalogEntry(
                id: "apple-tts",
                name: "Apple Speech Synthesis",
                developer: "Apple",
                engineKind: .tts,
                taskDescription: "Text-to-speech (built-in voices)",
                fileSizeBytes: 0,
                downloadSizeBytes: 0,
                format: .coreml,
                minimumRAMBytes: 0,
                recommendedRAMBytes: 0,
                license: "System",
                description: "Apple's built-in speech synthesis. No download required.",
                tags: ["built-in", "free", "starter"]
            ),
        ])

        return catalog
    }
}
