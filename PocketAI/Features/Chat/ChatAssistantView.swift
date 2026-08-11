import SwiftUI

struct ChatAssistantView: View {
    @ObservedObject var vm: HomeViewModel
    @State private var showParamsSheet = false
    @State private var showSystemPromptSheet = false

    var isTextModelLoaded: Bool {
        if let modelId = vm.activeModelId,
           let entry = vm.models.first(where: { $0.id == modelId }),
           entry.engineKind == .text {
            return true
        }
        return false
    }

    var activeModelName: String {
        if let modelId = vm.activeModelId,
           let entry = vm.models.first(where: { $0.id == modelId }) {
            return entry.name
        }
        return "Unknown Text Model"
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isTextModelLoaded {
                // Empty state to guide model loading
                noModelView
            } else {
                // Real-time performance overlay at the top of the chat
                if let metrics = vm.activeInferenceMetrics {
                    PerformanceOverlay(
                        metrics: metrics,
                        thermalState: vm.thermalState,
                        memoryUsedFormatted: vm.memorySnapshot != nil ? formatBytes(vm.memorySnapshot!.usedByModelsBytes) : "—",
                        isVisible: vm.isGeneratingText
                    )
                    .padding(.top, 10)
                    .padding(.horizontal)
                }

                // Chat Messages Scroll
                chatScrollView

                // Input Bar Area
                inputBar
            }
        }
        .navigationTitle("Chat Studio")
        .background(Color(.systemGroupedBackground))
        .toolbar {
            if isTextModelLoaded {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSystemPromptSheet = true }) {
                        Image(systemName: "square.text.square")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showParamsSheet = true }) {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
        }
        .sheet(isPresented: $showParamsSheet) {
            ParamsSheet(params: $vm.textParameters)
        }
        .sheet(isPresented: $showSystemPromptSheet) {
            SystemPromptSheet(prompt: $vm.systemPrompt)
        }
    }

    // MARK: - Subviews

    private var noModelView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 64))
                .foregroundStyle(.pocketPrimary)
            
            Text("No Text Model Loaded")
                .font(.title3)
                .fontWeight(.bold)
            
            Text("To start chatting, you must download and load a local LLM from the catalog.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Spacer()
        }
    }

    private var chatScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if vm.chatHistory.isEmpty {
                        emptyHistoryView
                    } else {
                        ForEach(vm.chatHistory) { msg in
                            messageBubble(for: msg)
                                .id(msg.id)
                        }
                    }
                    
                    if vm.isGeneratingText && (vm.chatHistory.last?.content.isEmpty ?? true) {
                        typingIndicatorRow
                    }
                }
                .padding()
            }
            .onChange(of: vm.chatHistory.count) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: vm.chatHistory.last?.content) { _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private var emptyHistoryView: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 50)
            HStack {
                Spacer()
                Text("Chatting with \(activeModelName)")
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundStyle(.pocketPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.pocketPrimary.opacity(0.12))
                    .clipShape(Capsule())
                Spacer()
            }
            Text("Ask questions, generate ideas, or analyze text completely offline.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    @ViewBuilder
    private func messageBubble(for msg: ChatMessage) -> some View {
        let isUser = msg.role == .user
        HStack {
            if isUser { Spacer() }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(msg.content)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? Color.pocketPrimary : Color.pocketElevated)
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // Show performance details if present
                if let metrics = msg.metrics {
                    Text(String(format: "%.1f t/s • %.2fs • %@", metrics.tokensPerSecond, metrics.generationTimeSeconds, metrics.backend.displayName))
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            
            if !isUser { Spacer() }
        }
    }

    private var typingIndicatorRow: some View {
        HStack {
            TypingIndicator()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.pocketElevated)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            Spacer()
        }
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                TextField("Ask assistant...", text: $vm.chatInput, axis: .vertical)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .lineLimit(1...5)
                    .disabled(vm.isGeneratingText)

                if vm.isGeneratingText {
                    Button(action: {
                        Task { await vm.aiEngine.cancelInference(engineKind: .text) }
                    }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.pocketError)
                    }
                } else {
                    Button(action: {
                        vm.sendChatMessage()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(vm.chatInput.isEmpty ? .secondary : Color.pocketPrimary)
                    }
                    .disabled(vm.chatInput.isEmpty)
                }
            }
            .padding()
            .background(Color(.systemBackground))
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = vm.chatHistory.last {
            withAnimation {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Parameters Config Sheet
struct ParamsSheet: View {
    @Binding var params: TextGenerationParameters
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Creativity Settings") {
                    VStack(alignment: .leading) {
                        LabeledContent("Temperature", value: String(format: "%.2f", params.temperature))
                        Slider(value: $params.temperature, in: 0.1...1.5, step: 0.05)
                    }
                    VStack(alignment: .leading) {
                        LabeledContent("Top-P Sampling", value: String(format: "%.2f", params.topP))
                        Slider(value: $params.topP, in: 0.1...1.0, step: 0.05)
                    }
                    Stepper("Top-K: \(params.topK)", value: $params.topK, in: 1...100)
                }

                Section("Output Control") {
                    Stepper("Max Output Tokens: \(params.maxTokens)", value: $params.maxTokens, in: 64...4096, step: 64)
                    VStack(alignment: .leading) {
                        LabeledContent("Repetition Penalty", value: String(format: "%.2f", params.repetitionPenalty))
                        Slider(value: $params.repetitionPenalty, in: 1.0...2.0, step: 0.05)
                    }
                }
            }
            .navigationTitle("Generation Parameters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { dismiss() }
                }
            }
        }
    }
}

// MARK: - System Prompt Config Sheet
struct SystemPromptSheet: View {
    @Binding var prompt: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                TextEditor(text: $prompt)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .font(.body)
                    .padding()
                
                Spacer()
            }
            .navigationTitle("System Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
