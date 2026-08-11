import SwiftUI

struct SettingsDashboardView: View {
    @ObservedObject var vm: HomeViewModel
    @State private var showResetAlert = false

    var body: some View {
        Form {
            Section("Downloads & Network") {
                Toggle(isOn: $vm.wifiOnlyDownloads) {
                    Label("WiFi-Only Downloads", systemName: "wifi")
                }
            }

            Section("Diagnostics & Overrides") {
                LabeledContent("Thermal State") {
                    Text(thermalStateLabel(vm.thermalState))
                        .fontWeight(.bold)
                        .foregroundStyle(thermalColor(vm.thermalState))
                }
                
                LabeledContent("Available Storage", value: formatBytes(vm.availableStorageBytes))
                LabeledContent("Cache Size", value: formatBytes(vm.totalInstalledBytes))
            }

            Section("Maintenance") {
                Button(role: .destructive, action: {
                    showResetAlert = true
                }) {
                    Label("Reset Models & Storage", systemName: "trash")
                }
            }

            Section("About") {
                LabeledContent("App Name", value: "Pocket AI Studio")
                LabeledContent("Version", value: "1.0.0 (Release)")
                LabeledContent("Engine Runtime", value: "AIEngine v1.0")
                LabeledContent("Frameworks", value: "Apple Silicon, Metal, CoreML")
            }
        }
        .navigationTitle("Settings")
        .alert("Reset All Storage?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Everything", role: .destructive) {
                clearAllStorage()
            }
        } message: {
            Text("This will delete all downloaded models and reset the app. You will need to download your models again.")
        }
    }

    private func clearAllStorage() {
        Task {
            // Unload any loaded models
            for modelId in vm.loadedModelIds {
                vm.unloadModel(modelId)
            }
            
            // Delete files in storage
            let fm = FileManager.default
            let storage = vm.aiEngine.storageManager
            let modelsDir = await storage.modelsDirectory
            let downloadsDir = await storage.downloadsDirectory
            
            try? fm.removeItem(at: modelsDir)
            try? fm.removeItem(at: downloadsDir)
            
            // Re-create directories
            try? fm.createDirectory(at: modelsDir, withIntermediateDirectories: true)
            try? fm.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
            
            await vm.refreshSystemStats()
        }
    }

    private func thermalStateLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:  return "Nominal"
        case .fair:     return "Fair"
        case .serious:  return "Serious"
        case .critical: return "Critical"
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
