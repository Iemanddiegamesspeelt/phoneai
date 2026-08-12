import Foundation
import Combine
import SwiftUI
import AVFoundation

@MainActor
public final class HomeViewModel: ObservableObject {

    // MARK: - Core Services
    public let aiEngine: AIEngine
    public let catalogService: CatalogService
    public let downloadManager: DownloadManager

    // MARK: - Published State
    @Published public var models: [ModelCatalogEntry] = []
    @Published public var hardwareProfile: HardwareCapabilityProfile? = nil
    @Published public var modelCompatibilities: [String: CompatibilityResult] = [:]
    @Published public var downloadTasks: [String: DownloadTask] = [:]

    public var loadedModels: [ModelCatalogEntry] {
        models.filter { loadedModelIds.contains($0.id) }
    }
    @Published public var installedModelIds: Set<String> = []
    @Published public var loadedModelIds: Set<String> = []
    @Published public var activeModelId: String?
    
    @Published public var isLoadingModel = false
    @Published public var loadingModelId: String?
    @Published public var loadingProgress: Double = 0.0

    @Published public var memorySnapshot: MemoryManager.MemorySnapshot?
    @Published public var thermalState: ProcessInfo.ThermalState = .nominal
    @Published public var availableStorageBytes: Int64 = 0
    @Published public var totalInstalledBytes: Int64 = 0

    // MARK: - Features: Chat
    @Published public var chatHistory: [ChatMessage] = []
    @Published public var chatInput: String = ""
    @Published public var isGeneratingText = false
    @Published public var activeInferenceMetrics: InferenceMetrics?
    @Published public var textParameters = TextGenerationParameters.default
    @Published public var systemPrompt = "You are a helpful assistant running 100% locally on my iPhone."

    // MARK: - Features: Image Gen
    @Published public var generatedImages: [Data] = []
    @Published public var imagePrompt = ""
    @Published public var isGeneratingImage = false
    @Published public var imageSteps = 20
    @Published public var imageWidth = 512
    @Published public var imageHeight = 512
    @Published public var imageProgress = 0.0

    // MARK: - Features: Vision
    @Published public var visionImage: Data?
    @Published public var visionQuery = "Describe this image"
    @Published public var visionResponse = ""
    @Published public var visionClassificationResults: [ClassificationResult] = []
    @Published public var isAnalyzingVision = false

    // MARK: - Features: Speech
    @Published public var recordedAudioURL: URL?
    @Published public var transcriptionText = ""
    @Published public var isRecording = false
    @Published public var isTranscribing = false
    private var audioRecorder: AVAudioRecorder?

    // MARK: - Features: TTS
    @Published public var ttsText = "Local AI is private and runs completely offline."
    @Published public var availableVoices: [VoiceInfo] = []
    @Published public var selectedVoiceId: String?
    @Published public var ttsSpeed = 1.0
    @Published public var ttsPitch = 1.0
    @Published public var isSpeaking = false

    // MARK: - Features: Audio
    @Published public var audioAnalysisResults: [ClassificationResult] = []
    @Published public var isAnalyzingAudio = false

    // MARK: - Error Handling
    @Published public var currentError: InferenceError?
    @Published public var showErrorAlert = false

    // MARK: - Settings
    @Published public var wifiOnlyDownloads = false {
        didSet {
            Task { downloadManager.setWifiOnly(wifiOnlyDownloads) }
        }
    }

    private var eventObservationsTask: Task<Void, Never>?
    private var downloadObservationsTask: Task<Void, Never>?

    // MARK: - Init
    public init() {
        let engine = AIEngine()
        self.aiEngine = engine
        self.catalogService = CatalogService()
        self.downloadManager = DownloadManager(storageManager: engine.storageManager)
    }

    // MARK: - Lifecycle Start
    public func start() async {
        // Initialize AIEngine
        await aiEngine.initialize()
        
        // Register modality sub-engines
        await aiEngine.registerTextEngine(MLXTextEngine())
        await aiEngine.registerImageEngine(LocalImageEngine())
        await aiEngine.registerVisionEngine(LocalVisionEngine())
        await aiEngine.registerSpeechEngine(LocalSpeechEngine())
        await aiEngine.registerTTSEngine(LocalTTSEngine())
        await aiEngine.registerAudioEngine(LocalAudioEngine())
        await aiEngine.registerVideoEngine(LocalVideoEngine())

        // Fetch catalog
        do {
            self.models = try await catalogService.fetchEntries()
        } catch {
            self.models = CatalogService.builtInCatalog()
        }

        // Load voices
        self.availableVoices = await aiEngine.availableTTSVoices()
        if let defaultVoice = availableVoices.first(where: { $0.language.contains("en") }) {
            self.selectedVoiceId = defaultVoice.id
        } else {
            self.selectedVoiceId = availableVoices.first?.id
        }

        // Fetch storage & loaded models
        await refreshSystemStats()

        // Start event streams observation
        observeEngineEvents()
        observeDownloadEvents()
    }

    deinit {
        eventObservationsTask?.cancel()
        downloadObservationsTask?.cancel()
    }

    // MARK: - Observation Tasks
    private func observeEngineEvents() {
        eventObservationsTask = Task {
            for await event in await aiEngine.events {
                await handleEngineEvent(event)
            }
        }
    }

    private func observeDownloadEvents() {
        downloadObservationsTask = Task {
            for await event in downloadManager.events {
                await handleDownloadEvent(event)
            }
        }
    }

    // MARK: - Event Handlers
    private func handleEngineEvent(_ event: EngineEvent) async {
        switch event {
        case .modelLoading(let modelId, let progress):
            isLoadingModel = true
            loadingModelId = modelId
            loadingProgress = progress

        case .modelLoaded(let modelId, _):
            isLoadingModel = false
            loadingModelId = nil
            loadingProgress = 0.0
            loadedModelIds.insert(modelId)
            activeModelId = modelId
            await refreshSystemStats()

        case .modelUnloaded(let modelId):
            loadedModelIds.remove(modelId)
            if activeModelId == modelId {
                activeModelId = nil
            }
            await refreshSystemStats()

        case .modelLoadFailed(let modelId, let error):
            isLoadingModel = false
            loadingModelId = nil
            loadingProgress = 0.0
            triggerError(error)

        case .thermalStateChanged(let state):
            thermalState = state

        case .memoryWarning(let level, _):
            // Auto refresh state
            await refreshSystemStats()

        case .memoryModelEvicted(let modelId, _):
            loadedModelIds.remove(modelId)
            if activeModelId == modelId {
                activeModelId = nil
            }
            await refreshSystemStats()

        case .inferenceMetrics(_, let metrics):
            activeInferenceMetrics = metrics

        case .inferenceCancelled(_):
            isGeneratingText = false
            isGeneratingImage = false
            isAnalyzingVision = false

        default:
            break
        }
    }

    private func handleDownloadEvent(_ event: DownloadEvent) async {
        switch event {
        case .started(let modelId, let task):
            downloadTasks[modelId] = task
        case .progress(let modelId, _, _, _):
            if let task = downloadManager.task(for: modelId) {
                downloadTasks[modelId] = task
            }
        case .completed(let modelId, let localURL):
            downloadTasks.removeValue(forKey: modelId)
            do {
                _ = try await aiEngine.storageManager.installModel(from: localURL, modelId: modelId)
                await refreshSystemStats()
            } catch {
                triggerError(InferenceError(.installationFailed, message: error.localizedDescription))
            }
        case .failed(let modelId, let error):
            downloadTasks.removeValue(forKey: modelId)
            triggerError(error)
        case .paused(let modelId):
            if let task = downloadManager.task(for: modelId) {
                downloadTasks[modelId] = task
            }
        case .resumed(let modelId):
            if let task = downloadManager.task(for: modelId) {
                downloadTasks[modelId] = task
            }
        case .cancelled(let modelId):
            downloadTasks.removeValue(forKey: modelId)
        }
    }

    // MARK: - Actions
    public func startDownload(for model: ModelCatalogEntry) {
        guard let downloadStr = model.downloadURL, let downloadURL = URL(string: downloadStr) else {
            triggerError(InferenceError(.catalogManifestInvalid, message: "Invalid download link."))
            return
        }
        
        Task {
            do {
                try await downloadManager.download(
                    modelId: model.id,
                    modelName: model.name,
                    from: downloadURL,
                    expectedSizeBytes: model.downloadSizeBytes
                )
            } catch {
                if let infError = error as? InferenceError {
                    triggerError(infError)
                } else {
                    triggerError(InferenceError(.downloadFailed, message: error.localizedDescription))
                }
            }
        }
    }

    public func pauseDownload(modelId: String) {
        Task { downloadManager.pause(modelId: modelId) }
    }

    public func resumeDownload(modelId: String) {
        Task { downloadManager.resume(modelId: modelId) }
    }

    public func cancelDownload(modelId: String) {
        Task { downloadManager.cancel(modelId: modelId) }
    }

    public func deleteModel(modelId: String) {
        Task {
            do {
                // If model is loaded, unload it first
                if loadedModelIds.contains(modelId) {
                    if let entry = models.first(where: { $0.id == modelId }) {
                        try await aiEngine.unloadModel(modelId, engineKind: entry.engineKind)
                    }
                }
                try await aiEngine.storageManager.deleteModel(modelId)
                await refreshSystemStats()
            } catch {
                triggerError(InferenceError(.storageWriteFailed, message: error.localizedDescription))
            }
        }
    }

    public func loadModel(_ model: ModelCatalogEntry) {
        isLoadingModel = true
        loadingModelId = model.id
        loadingProgress = 0.0

        Task {
            do {
                // Check if another model needs to be unloaded to fit memory limits
                let memoryCheck = await aiEngine.canLoadModel(model)
                if case .marginal(let warnings) = memoryCheck {
                    // Evict LRU models
                    let estimate = MemoryEstimator.estimate(for: model.engineKind, fileSizeBytes: model.fileSizeBytes, quantization: model.quantization)
                    let activeIds = Set([model.id])
                    let evictedIds = await aiEngine.memoryManager.evictModelsToFree(targetBytes: estimate.requiredBytes, excluding: activeIds)
                    for id in evictedIds {
                        if let entry = models.first(where: { $0.id == id }) {
                            try? await aiEngine.unloadModel(id, engineKind: entry.engineKind)
                        }
                    }
                }

                try await aiEngine.loadModel(model)
            } catch {
                isLoadingModel = false
                loadingModelId = nil
                if let infErr = error as? InferenceError {
                    triggerError(infErr)
                } else {
                    triggerError(InferenceError(.modelLoadFailed, message: error.localizedDescription))
                }
            }
        }
    }

    public func unloadModel(_ modelId: String) {
        guard let entry = models.first(where: { $0.id == modelId }) else { return }
        Task {
            do {
                try await aiEngine.unloadModel(modelId, engineKind: entry.engineKind)
            } catch {
                triggerError(InferenceError(.modelUnloadFailed, message: error.localizedDescription))
            }
        }
    }

    // MARK: - Chat Assistant
    public func sendChatMessage() {
        let text = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let modelId = activeModelId else { return }

        chatInput = ""
        let userMessage = ChatMessage(role: .user, content: text)
        chatHistory.append(userMessage)

        let assistantMessageId = UUID()
        let assistantMessagePlaceholder = ChatMessage(id: assistantMessageId, role: .assistant, content: "")
        chatHistory.append(assistantMessagePlaceholder)

        isGeneratingText = true

        Task {
            do {
                let stream = await aiEngine.generateText(
                    prompt: text,
                    systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt,
                    history: chatHistory.dropLast(),
                    parameters: textParameters
                )

                for try await event in stream {
                    switch event {
                    case .token(let token):
                        if let index = chatHistory.firstIndex(where: { $0.id == assistantMessageId }) {
                            chatHistory[index].content += token
                        }
                    case .metrics(let metrics):
                        activeInferenceMetrics = metrics
                    case .done(let totalOutput):
                        if let index = chatHistory.firstIndex(where: { $0.id == assistantMessageId }) {
                            chatHistory[index].content = totalOutput
                            
                            // Attach metrics
                            if let metrics = activeInferenceMetrics {
                                chatHistory[index].metrics = ChatMessageMetrics(
                                    tokensPerSecond: metrics.tokensPerSecond,
                                    totalTokens: metrics.totalTokens,
                                    inputTokens: metrics.inputTokens,
                                    outputTokens: metrics.outputTokens,
                                    generationTimeSeconds: metrics.elapsedSeconds,
                                    backend: metrics.activeBackend
                                )
                            }
                        }
                    case .error(let error):
                        throw error
                    }
                }
            } catch {
                if let idx = chatHistory.firstIndex(where: { $0.id == assistantMessageId }) {
                    chatHistory[idx].content = "Error: \(error.localizedDescription)"
                }
                if let infError = error as? InferenceError {
                    triggerError(infError)
                }
            }
            isGeneratingText = false
        }
    }

    public func clearChat() {
        chatHistory.removeAll()
        activeInferenceMetrics = nil
    }

    // MARK: - Image Gen
    public func runImageGeneration() {
        let prompt = imagePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        isGeneratingImage = true
        imageProgress = 0.0

        let params = ImageGenerationParameters(
            steps: imageSteps,
            width: imageWidth,
            height: imageHeight
        )

        Task {
            do {
                let stream = await aiEngine.generateImage(prompt: prompt, parameters: params)
                for try await event in stream {
                    switch event {
                    case .stepCompleted(let step, let total):
                        imageProgress = Double(step) / Double(total)
                    case .imageReady(let imageData, _):
                        generatedImages.insert(imageData, at: 0)
                    case .done:
                        break
                    case .error(let error):
                        throw error
                    }
                }
            } catch {
                if let infError = error as? InferenceError {
                    triggerError(infError)
                }
            }
            isGeneratingImage = false
            imageProgress = 0.0
        }
    }

    // MARK: - Vision
    public func runVisionAnalysis() {
        guard let data = visionImage else { return }
        let query = visionQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isAnalyzingVision = true
        visionResponse = ""
        visionClassificationResults.removeAll()

        Task {
            do {
                // Try classification first in background
                if let classes = try? await aiEngine.classifyVision(imageData: data) {
                    visionClassificationResults = classes
                }

                // Run visual Q&A stream
                let stream = await aiEngine.analyzeVision(imageData: data, query: query)
                for try await event in stream {
                    switch event {
                    case .token(let token):
                        visionResponse += token
                    case .metrics(let metrics):
                        activeInferenceMetrics = metrics
                    case .error(let error):
                        throw error
                    default:
                        break
                    }
                }
            } catch {
                if let infError = error as? InferenceError {
                    triggerError(infError)
                }
            }
            isAnalyzingVision = false
        }
    }

    // MARK: - Speech
    public func startAudioRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)

            let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let audioURL = docDir.appendingPathComponent("recording.wav")

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16000.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.record()
            
            recordedAudioURL = audioURL
            isRecording = true
            transcriptionText = "Recording audio..."
        } catch {
            triggerError(InferenceError(.installationFailed, message: "Microphone permission or config failed."))
        }
    }

    public func stopAudioRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        transcriptionText = "Recording saved. Ready to transcribe."
    }

    public func runTranscription() {
        guard let url = recordedAudioURL else { return }
        isTranscribing = true

        Task {
            do {
                let result = try await aiEngine.transcribeSpeech(audioURL: url)
                transcriptionText = result.text
            } catch {
                if let infError = error as? InferenceError {
                    triggerError(infError)
                }
            }
            isTranscribing = false
        }
    }

    // MARK: - TTS
    public func speakText() {
        let text = ttsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isSpeaking = true
        let voiceId = selectedVoiceId
        let params = TTSParameters(speed: ttsSpeed, pitch: ttsPitch)

        Task {
            do {
                _ = try await aiEngine.synthesizeSpeech(text: text, voiceId: voiceId, parameters: params)
            } catch {
                if let infError = error as? InferenceError {
                    triggerError(infError)
                }
            }
            isSpeaking = false
        }
    }

    public func stopSpeaking() {
        Task {
            await aiEngine.cancelInference(engineKind: .tts)
            isSpeaking = false
        }
    }

    // MARK: - Audio Analysis
    public func analyzeRecordedAudio() {
        guard let url = recordedAudioURL else { return }
        isAnalyzingAudio = true
        audioAnalysisResults.removeAll()

        Task {
            do {
                let results = try await aiEngine.classifyAudio(audioURL: url)
                audioAnalysisResults = results
            } catch {
                if let infError = error as? InferenceError {
                    triggerError(infError)
                }
            }
            isAnalyzingAudio = false
        }
    }

    // MARK: - Stats Utilities
    public func refreshSystemStats() async {
        let installedIds = await aiEngine.storageManager.installedModelIds()
        self.installedModelIds = Set(installedIds)

        // Read hardware profile
        self.hardwareProfile = await aiEngine.hardwareProfile

        // Read loaded models
        var loaded: Set<String> = []
        var compatibilities: [String: CompatibilityResult] = [:]
        for model in models {
            let ready = await aiEngine.isReady(engineKind: model.engineKind)
            if ready, let loadedId = await aiEngine.loadedModelId(engineKind: model.engineKind) {
                // If model conforms to loadedId, track it
                if model.id == loadedId {
                    loaded.insert(model.id)
                }
            }
            
            // Check compatibility
            compatibilities[model.id] = await aiEngine.checkCompatibility(model: model)
        }
        self.loadedModelIds = loaded
        self.activeModelId = loaded.first
        self.modelCompatibilities = compatibilities

        // Read memory snapshot
        self.memorySnapshot = await aiEngine.memorySnapshot()
        self.availableStorageBytes = await aiEngine.storageManager.availableStorageBytes()
        self.totalInstalledBytes = await aiEngine.storageManager.totalInstalledBytes()
    }

    public func triggerError(_ error: InferenceError) {
        currentError = error
        showErrorAlert = true
    }
}
