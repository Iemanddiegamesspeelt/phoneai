import SwiftUI

struct CatalogListView: View {
    @ObservedObject var vm: HomeViewModel
    @State private var selectedFilter: FilterCategory = .all
    @State private var selectedModel: ModelCatalogEntry?

    enum FilterCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case text = "Text"
        case image = "Image"
        case vision = "Vision"
        case speech = "Speech"
        case tts = "TTS"

        var id: String { rawValue }
        
        var engineKind: ModelEngineKind? {
            switch self {
            case .text: return .text
            case .image: return .image
            case .vision: return .vision
            case .speech: return .speech
            case .tts: return .tts
            case .all: return nil
            }
        }
    }

    var filteredModels: [ModelCatalogEntry] {
        if let kind = selectedFilter.engineKind {
            return vm.models.filter { $0.engineKind == kind }
        }
        return vm.models
    }

    var body: some View {
        VStack(spacing: 0) {
            // Category selector bar
            pickerBar

            // Catalog list
            if filteredModels.isEmpty {
                emptyView
            } else {
                List {
                    ForEach(filteredModels) { model in
                        modelRow(for: model)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .onTapGesture {
                                selectedModel = model
                            }
                    }
                }
                .listStyle(.plain)
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle("Model Catalog")
        .sheet(item: $selectedModel) { model in
            ModelDetailSheet(model: model, vm: vm)
        }
    }

    // MARK: - Picker Bar
    private var pickerBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FilterCategory.allCases) { category in
                    Button(action: {
                        withAnimation {
                            selectedFilter = category
                        }
                    }) {
                        Text(category.rawValue)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedFilter == category ? Color.pocketPrimary : Color(.secondarySystemBackground))
                            .foregroundStyle(selectedFilter == category ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.04), radius: 3, y: 2)
    }

    // MARK: - Empty State
    private var emptyView: some View {
        VStack(spacing: 15) {
            Spacer()
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No models found in this category.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Model Row
    @ViewBuilder
    private func modelRow(for model: ModelCatalogEntry) -> some View {
        let isInstalled = vm.installedModelIds.contains(model.id)
        let isLoaded = vm.loadedModelIds.contains(model.id)
        let downloadTask = vm.downloadTasks[model.id]
        
        HStack(spacing: 12) {
            EngineKindBadge(kind: model.engineKind)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Compatibility check
                    compatibilityBadge(for: model)
                }

                Text(model.taskDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(model.fileSizeFormatted)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    
                    Text(model.format.rawValue.uppercased())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    
                    if let quant = model.quantization {
                        Text(quant.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            Spacer()

            // Dynamic Action button column
            VStack {
                if isLoaded {
                    Button("Unload") {
                        vm.unloadModel(model.id)
                    }
                    .buttonStyle(.bordered)
                    .tint(.pocketWarning)
                    .controlSize(.small)
                } else if isInstalled {
                    Button("Load") {
                        vm.loadModel(model)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pocketPrimary)
                    .controlSize(.small)
                } else if let task = downloadTask {
                    // Currently downloading
                    VStack(spacing: 2) {
                        ProgressView(value: task.progress)
                            .progressViewStyle(.linear)
                            .frame(width: 60)
                            .tint(.pocketPrimary)
                        Text(task.percentFormatted)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.pocketPrimary)
                    }
                } else {
                    // Not downloaded
                    Button(action: {
                        vm.startDownload(for: model)
                    }) {
                        Image(systemName: "arrow.down.circle")
                            .font(.title3)
                            .foregroundStyle(Color.pocketPrimary)
                    }
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isLoaded ? Color.pocketSuccess.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1.0)
        )
    }

    // MARK: - Helper Badge
    @ViewBuilder
    private func compatibilityBadge(for model: ModelCatalogEntry) -> some View {
        let result = vm.modelCompatibilities[model.id] ?? .compatible
        switch result {
        case .compatible:
            StatusBadge("COMPATIBLE", color: .pocketSuccess)
        case .marginal:
            StatusBadge("SLOW", color: .pocketWarning)
        case .incompatible:
            StatusBadge("UNSUPPORTED", color: .pocketError)
        }
    }
}

// MARK: - Model Detail Sheet
struct ModelDetailSheet: View {
    let model: ModelCatalogEntry
    @ObservedObject var vm: HomeViewModel
    @Environment(\.dismiss) var dismiss

    private var compatibilityResult: CompatibilityResult {
        vm.modelCompatibilities[model.id] ?? .compatible
    }
    
    private var isInstalled: Bool {
        vm.installedModelIds.contains(model.id)
    }
    
    private var isLoaded: Bool {
        vm.loadedModelIds.contains(model.id)
    }
    
    private var downloadTask: DownloadTask? {
        vm.downloadTasks[model.id]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header card
                    HStack(spacing: 12) {
                        EngineKindBadge(kind: model.engineKind)
                        VStack(alignment: .leading) {
                            Text(model.name)
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("Developed by \(model.developer)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Description text
                    Text(model.description)
                        .font(.body)
                        .foregroundStyle(.secondary)

                    // Hardware Specs Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Hardware Compatibility")
                            .font(.headline)
                        
                        HStack(spacing: 8) {
                            Image(systemName: compatibilityResult.statusIcon)
                                .foregroundStyle(compatibilityColor(compatibilityResult))
                            Text(compatibilityResult.statusLabel)
                                .fontWeight(.bold)
                                .foregroundStyle(compatibilityColor(compatibilityResult))
                        }

                        if case .incompatible(let reasons) = compatibilityResult {
                            ForEach(reasons, id: \.self) { reason in
                                Text("• \(reason)")
                                    .font(.footnote)
                                    .foregroundStyle(Color.pocketError)
                            }
                        }

                        if case .marginal(let warnings) = compatibilityResult {
                            ForEach(warnings, id: \.self) { warning in
                                Text("• \(warning)")
                                    .font(.footnote)
                                    .foregroundStyle(Color.pocketWarning)
                            }
                        }

                        Divider()

                        LabeledContent("Download Size", value: model.downloadSizeFormatted)
                        LabeledContent("Estimated RAM Needed", value: formatBytes(model.minimumRAMBytes))
                        LabeledContent("Quantization Method", value: model.quantization?.displayName ?? "None")
                        LabeledContent("Execution Format", value: model.format.rawValue.uppercased())
                        LabeledContent("License Type", value: model.license)
                    }
                    .padding(16)
                    .glassCard(cornerRadius: 16)

                    // Actions
                    VStack(spacing: 12) {
                        if isLoaded {
                            Button("Unload Model from RAM") {
                                vm.unloadModel(model.id)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.pocketWarning)
                            .frame(maxWidth: .infinity)
                        } else if isInstalled {
                            Button("Load Model") {
                                vm.loadModel(model)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.pocketPrimary)
                            .frame(maxWidth: .infinity)
                            
                            Button("Delete Local Files") {
                                vm.deleteModel(modelId: model.id)
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                            .tint(.pocketError)
                            .frame(maxWidth: .infinity)
                        } else if let task = downloadTask {
                            VStack(spacing: 8) {
                                DownloadProgressBar(task: task)
                                Button("Cancel Download") {
                                    vm.cancelDownload(modelId: model.id)
                                }
                                .buttonStyle(.bordered)
                                .tint(.pocketError)
                            }
                        } else {
                            Button("Download Model (\(model.downloadSizeFormatted))") {
                                vm.startDownload(for: model)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.pocketPrimary)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top)

                    if let homepage = model.homepage, let url = URL(string: homepage) {
                        Link(destination: url) {
                            HStack {
                                Spacer()
                                Image(systemName: "safari")
                                Text("View on Hugging Face")
                                Spacer()
                            }
                            .font(.footnote)
                            .foregroundStyle(Color.pocketPrimary)
                            .padding(.top, 10)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Model Specifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func compatibilityColor(_ result: CompatibilityResult) -> Color {
        switch result {
        case .compatible:   return .pocketSuccess
        case .marginal:     return .pocketWarning
        case .incompatible: return .pocketError
        }
    }
}
