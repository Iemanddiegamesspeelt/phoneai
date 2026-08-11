import SwiftUI

struct HomeDashboardView: View {
    @ObservedObject var vm: HomeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header card
                headerCard

                // Performance Gauges row
                gaugesRow

                // Active Downloads Section
                activeDownloadsSection

                // Active Models / Recently Loaded Section
                activeModelsSection

                // Hardware Profile details
                hardwareProfileSection
            }
            .padding()
        }
        .navigationTitle("Dashboard")
        .background(Color(.systemGroupedBackground))
        .onAppear {
            Task { await vm.refreshSystemStats() }
        }
    }

    // MARK: - Subviews

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pocket AI Studio")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Spacer()
                LocalBadge()
            }
            
            Text("Your secure, on-device local AI workstation. No internet required, maximum privacy.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(20)
        .gradientCard(.pocketPrimary, cornerRadius: 16)
    }

    private var gaugesRow: some View {
        HStack(spacing: 15) {
            // Memory Gauge
            VStack {
                if let snapshot = vm.memorySnapshot {
                    GaugeView(
                        value: snapshot.utilizationRatio,
                        label: "System Memory",
                        sublabel: "\(formatBytes(snapshot.usedByModelsBytes)) used",
                        color: snapshot.pressureLevel == .critical ? .pocketError : (snapshot.pressureLevel == .warning ? .pocketWarning : .pocketSuccess)
                    )
                } else {
                    ProgressView().frame(width: 52, height: 52)
                    Text("Memory").font(.caption2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: 14)

            // Storage Gauge
            VStack {
                let totalBytes = vm.availableStorageBytes + vm.totalInstalledBytes
                let ratio = totalBytes > 0 ? Double(vm.totalInstalledBytes) / Double(totalBytes) : 0.0
                GaugeView(
                    value: ratio,
                    label: "Models Storage",
                    sublabel: "\(formatBytes(vm.totalInstalledBytes)) / \(formatBytes(totalBytes))",
                    color: .pocketPrimary
                )
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: 14)
        }
    }

    @ViewBuilder
    private var activeDownloadsSection: some View {
        let tasks = vm.downloadTasks.values.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Active Downloads")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                ForEach(tasks) { task in
                    VStack(spacing: 8) {
                        DownloadProgressBar(task: task)
                        
                        HStack {
                            Button("Pause") {
                                vm.pauseDownload(modelId: task.modelId)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            
                            Button("Cancel") {
                                vm.cancelDownload(modelId: task.modelId)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.pocketError)
                            .controlSize(.mini)
                        }
                    }
                    .padding(8)
                    .glassCard(cornerRadius: 12)
                }
            }
        }
    }

    private var activeModelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active Model")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if vm.loadedModelIds.isEmpty {
                HStack {
                    Image(systemName: "square.dashed")
                        .foregroundStyle(.secondary)
                    Text("No models currently loaded in memory.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(15)
                .glassCard(cornerRadius: 12)
            } else {
                ForEach(vm.loadedModels, id: \.id) { (model: ModelCatalogEntry) in
                    HStack(spacing: 12) {
                        EngineKindBadge(kind: model.engineKind)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.name)
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Text("\(model.developer) • \(model.fileSizeFormatted)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        
                        StatusBadge("LOADED", color: .pocketSuccess)
                        
                        Button(action: {
                            vm.unloadModel(model.id)
                        }) {
                            Image(systemName: "power")
                                .foregroundStyle(Color.pocketError)
                                .padding(8)
                                .background(Color.pocketError.opacity(0.12))
                                .clipShape(Circle())
                        }
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 12)
                }
            }
        }
    }

    private var hardwareProfileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hardware Capability Profile")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                if let profile = vm.hardwareProfile {
                    infoRow(title: "Device Model", value: profile.deviceModel, icon: "iphone")
                    Divider().padding(.leading, 40)
                    infoRow(title: "iOS Version", value: profile.iosVersion, icon: "info.circle")
                    Divider().padding(.leading, 40)
                    infoRow(title: "Total RAM", value: profile.totalRAMFormatted, icon: "memorychip")
                    Divider().padding(.leading, 40)
                    infoRow(title: "Safe Memory for AI", value: profile.safeModelMemoryFormatted, icon: "shield")
                    Divider().padding(.leading, 40)
                    infoRow(title: "Neural Engine", value: profile.neuralEngineAvailable ? "Available (ANE)" : "Not Available", icon: "brain", color: profile.neuralEngineAvailable ? .pocketSuccess : .secondary)
                    Divider().padding(.leading, 40)
                    infoRow(title: "Metal GPU", value: profile.gpuName ?? (profile.metalSupported ? "Supported" : "Unsupported"), icon: "gpu")
                    Divider().padding(.leading, 40)
                    infoRow(title: "Thermal State", value: thermalLabel(vm.thermalState), icon: "thermometer", color: thermalColor(vm.thermalState))
                } else {
                    ProgressView().padding()
                }
            }
            .glassCard(cornerRadius: 14)
        }
    }

    private func infoRow(title: String, value: String, icon: String, color: Color = .primary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Color.pocketPrimary)
                .frame(width: 24, height: 24)
                .background(Color.pocketPrimary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .padding(12)
    }

    private func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:  return "Nominal (Cool)"
        case .fair:     return "Fair (Warm)"
        case .serious:  return "Serious (Hot)"
        case .critical: return "Critical (Throttled)"
        @unknown default: return "Unknown"
        }
    }

    private func thermalColor(_ state: ProcessInfo.ThermalState) -> Color {
        switch state {
        case .nominal:  return .pocketSuccess
        case .fair:     return .pocketWarning
        case .serious:  return .orange
        case .critical: return .pocketError
        @unknown default: return .secondary
        }
    }
}
