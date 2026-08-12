import SwiftUI
import PhotosUI

struct CreateStudioView: View {
    @ObservedObject var vm: HomeViewModel
    @State private var activeTab: StudioTab = .imageGen

    enum StudioTab: String, CaseIterable, Identifiable {
        case imageGen = "Image Gen"
        case vision = "Vision"
        case speech = "Speech"
        case tts = "TTS"

        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .imageGen: return "photo.artframe"
            case .vision:   return "eye"
            case .speech:   return "waveform"
            case .tts:      return "speaker.wave.3"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Horizontal Icon Navigation Selector
            HStack(spacing: 0) {
                ForEach(StudioTab.allCases) { tab in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            activeTab = tab
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20, weight: .medium))
                            Text(tab.rawValue)
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(activeTab == tab ? Color.pocketPrimary : .secondary)
                        .overlay(
                            Rectangle()
                                .fill(activeTab == tab ? Color.pocketPrimary : Color.clear)
                                .frame(height: 3)
                                .padding(.top, 40),
                            alignment: .bottom
                        )
                    }
                }
            }
            .background(Color(.systemBackground))
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)

            // Content Panel
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch activeTab {
                    case .imageGen:
                        imageGenStudio
                    case .vision:
                        visionStudio
                    case .speech:
                        speechStudio
                    case .tts:
                        ttsStudio
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("Creation Studio")
    }

    // MARK: - 1. IMAGE GEN STUDIO
    @ViewBuilder
    private var imageGenStudio: some View {
        let isImageModelLoaded = vm.loadedModelIds.contains { id in
            vm.models.first { $0.id == id }?.engineKind == .image
        }

        if !isImageModelLoaded {
            loadModelWarning(message: "No Image Generation model loaded. Go to the Catalog to load Stable Diffusion.")
        } else {
            VStack(alignment: .leading, spacing: 15) {
                // Inputs Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Prompt")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    
                    TextField("A beautiful cosmic galaxy with glowing stars...", text: $vm.imagePrompt, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    LabeledContent("Denoising Steps", value: "\(vm.imageSteps)")
                    Slider(value: Binding(get: { Double(vm.imageSteps) }, set: { vm.imageSteps = Int($0) }), in: 10...50, step: 5)

                    // Size Selection
                    HStack {
                        Text("Resolution")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Size", selection: $vm.imageWidth) {
                            Text("256x256").tag(256)
                            Text("512x512").tag(512)
                        }
                        .pickerStyle(.menu)
                        .onChange(of: vm.imageWidth) { _, newValue in
                            vm.imageHeight = newValue
                        }
                    }

                    if vm.isGeneratingImage {
                        VStack(spacing: 6) {
                            ProgressView(value: vm.imageProgress)
                                .tint(.pocketPrimary)
                            Text("Denoising... \(Int(vm.imageProgress * 100))%")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.pocketPrimary)
                            
                            Button("Cancel", action: {
                                Task { await vm.aiEngine.cancelInference(engineKind: .image) }
                            })
                            .buttonStyle(.bordered)
                            .tint(.pocketError)
                        }
                        .padding(.top, 10)
                    } else {
                        Button("Generate Local Image") {
                            vm.runImageGeneration()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.pocketPrimary)
                        .frame(maxWidth: .infinity)
                        .disabled(vm.imagePrompt.isEmpty)
                    }
                }
                .padding(16)
                .glassCard(cornerRadius: 16)

                // Generated History Grid
                if !vm.generatedImages.isEmpty {
                    Text("Generated Images")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(vm.generatedImages, id: \.self) { imgData in
                            if let uiImg = UIImage(data: imgData) {
                                VStack(spacing: 8) {
                                    Image(uiImage: uiImg)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 150)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    
                                    HStack {
                                        // Save to Photos
                                        Button(action: {
                                            UIImageWriteToSavedPhotosAlbum(uiImg, nil, nil, nil)
                                            // Mock notification
                                        }) {
                                            Image(systemName: "square.and.arrow.down")
                                        }
                                        
                                        Spacer()

                                        // Native Share link
                                        ShareLink(item: Image(uiImage: uiImg), preview: SharePreview("Generated Image", image: Image(uiImage: uiImg))) {
                                            Image(systemName: "square.and.arrow.up")
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.bottom, 6)
                                }
                                .glassCard(cornerRadius: 12)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 2. VISION STUDIO
    @ViewBuilder
    private var visionStudio: some View {
        let isVisionModelLoaded = vm.loadedModelIds.contains { id in
            vm.models.first { $0.id == id }?.engineKind == .vision
        }

        if !isVisionModelLoaded {
            loadModelWarning(message: "No Vision model loaded. Go to the Catalog and load MobileCLIP or MobileNet.")
        } else {
            VStack(alignment: .leading, spacing: 15) {
                // Image selector canvas
                VStack(spacing: 12) {
                    if let imgData = vm.visionImage, let uiImg = UIImage(data: imgData) {
                        Image(uiImage: uiImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Photo selector
                    PhotosPicker(selection: Binding(get: { nil }, set: { item in
                        guard let item else { return }
                        item.loadTransferable(type: Data.self) { result in
                            switch result {
                            case .success(let data):
                                if let data {
                                    DispatchQueue.main.async { vm.visionImage = data }
                                }
                            default:
                                break
                            }
                        }
                    }), matching: .images) {
                        Label("Select Image", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(Color.pocketPrimary.opacity(0.12))
                            .foregroundStyle(Color.pocketPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(16)
                .glassCard(cornerRadius: 16)

                if vm.visionImage != nil {
                    // Task triggers card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Image Analysis")
                            .font(.headline)
                        
                        TextField("Ask a question about this image...", text: $vm.visionQuery)
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        if vm.isAnalyzingVision {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Button("Analyze Image") {
                                vm.runVisionAnalysis()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.pocketPrimary)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(16)
                    .glassCard(cornerRadius: 16)

                    // Classification results
                    if !vm.visionClassificationResults.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Top System Classifications")
                                .font(.subheadline)
                                .fontWeight(.bold)
                            
                            ForEach(vm.visionClassificationResults.prefix(3), id: \.label) { cls in
                                LabeledContent(cls.label.capitalized, value: String(format: "%.0f%%", cls.confidence * 100))
                                    .font(.footnote)
                            }
                        }
                        .padding(16)
                        .glassCard(cornerRadius: 16)
                    }

                    // Conversation feedback
                    if !vm.visionResponse.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Vision Response")
                                .font(.subheadline)
                                .fontWeight(.bold)
                            
                            Text(vm.visionResponse)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .glassCard(cornerRadius: 16)
                    }
                }
            }
        }
    }

    // MARK: - 3. SPEECH STUDIO
    @ViewBuilder
    private var speechStudio: some View {
        let isSpeechModelLoaded = vm.loadedModelIds.contains { id in
            vm.models.first { $0.id == id }?.engineKind == .speech
        }

        if !isSpeechModelLoaded {
            loadModelWarning(message: "No Speech model loaded. Go to the Catalog to load Whisper.")
        } else {
            VStack(alignment: .leading, spacing: 15) {
                // Audio recording panel
                VStack(spacing: 20) {
                    if vm.isRecording {
                        Image(systemName: "waveform")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.pocketError)
                            .scaleEffect(vm.isRecording ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.5).repeatForever(), value: vm.isRecording)
                        
                        Button("Stop Recording") {
                            vm.stopAudioRecording()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.pocketError)
                    } else {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.pocketPrimary)
                        
                        Button("Start Recording") {
                            vm.startAudioRecording()
                        }
                        .buttonStyle(.bordered)
                        .tint(.pocketPrimary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .glassCard(cornerRadius: 16)

                // Actions & transcription
                if vm.recordedAudioURL != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Speech to Text Transcription")
                            .font(.headline)

                        if vm.isTranscribing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Button("Transcribe Audio") {
                                vm.runTranscription()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.pocketPrimary)
                            .frame(maxWidth: .infinity)
                        }

                        if !vm.transcriptionText.isEmpty {
                            Text("Transcript:")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            
                            Text(vm.transcriptionText)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(16)
                    .glassCard(cornerRadius: 16)

                    // Audio Classification analysis card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Audio Event Classification")
                            .font(.headline)
                        
                        if vm.isAnalyzingAudio {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Button("Analyze Sounds") {
                                vm.analyzeRecordedAudio()
                            }
                            .buttonStyle(.bordered)
                            .tint(.pocketPrimary)
                            .frame(maxWidth: .infinity)
                        }

                        if !vm.audioAnalysisResults.isEmpty {
                            ForEach(vm.audioAnalysisResults, id: \.label) { res in
                                LabeledContent(res.label.capitalized, value: String(format: "%.0f%%", res.confidence * 100))
                                    .font(.footnote)
                            }
                        }
                    }
                    .padding(16)
                    .glassCard(cornerRadius: 16)
                }
            }
        }
    }

    // MARK: - 4. TTS STUDIO
    @ViewBuilder
    private var ttsStudio: some View {
        let isTTSModelLoaded = vm.loadedModelIds.contains { id in
            vm.models.first { $0.id == id }?.engineKind == .tts
        }

        if !isTTSModelLoaded {
            loadModelWarning(message: "No TTS model loaded. Go to the Catalog to load Apple Speech.")
        } else {
            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Speech Synthesis Text")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    
                    TextField("Enter text here...", text: $vm.ttsText, axis: .vertical)
                        .lineLimit(3...5)
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Voice Selection Picker
                    Picker("Voice Select", selection: $vm.selectedVoiceId) {
                        ForEach(vm.availableVoices) { voice in
                            Text("\(voice.name) (\(voice.language))").tag(Optional(voice.id))
                        }
                    }
                    .pickerStyle(.menu)

                    // Controls
                    LabeledContent("Synthesis Rate", value: String(format: "%.1f", vm.ttsSpeed))
                    Slider(value: $vm.ttsSpeed, in: 0.5...2.0, step: 0.1)

                    LabeledContent("Pitch Multiplier", value: String(format: "%.1f", vm.ttsPitch))
                    Slider(value: $vm.ttsPitch, in: 0.5...1.5, step: 0.1)

                    if vm.isSpeaking {
                        Button("Stop Speech", action: {
                            vm.stopSpeaking()
                        })
                        .buttonStyle(.borderedProminent)
                        .tint(.pocketError)
                        .frame(maxWidth: .infinity)
                    } else {
                        Button("Speak Aloud") {
                            vm.speakText()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.pocketPrimary)
                        .frame(maxWidth: .infinity)
                        .disabled(vm.ttsText.isEmpty)
                    }
                }
                .padding(16)
                .glassCard(cornerRadius: 16)
            }
        }
    }

    // MARK: - Warning Banner Helper
    @ViewBuilder
    private func loadModelWarning(message: String) -> some View {
        VStack(spacing: 15) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.pocketWarning)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassCard(cornerRadius: 16)
        .padding(.top, 40)
    }
}
