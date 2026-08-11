import SwiftUI

public struct MainTabView: View {
    @StateObject private var vm = HomeViewModel()

    public init() {}

    public var body: some View {
        TabView {
            // Tab 1: Dashboard
            NavigationStack {
                HomeDashboardView(vm: vm)
            }
            .tabItem {
                Label("Home", systemName: "house.fill")
            }

            // Tab 2: Models
            NavigationStack {
                CatalogListView(vm: vm)
            }
            .tabItem {
                Label("Models", systemName: "cpu")
            }

            // Tab 3: Chat
            NavigationStack {
                ChatAssistantView(vm: vm)
            }
            .tabItem {
                Label("Chat", systemName: "bubble.left.and.bubble.right.fill")
            }

            // Tab 4: Create
            NavigationStack {
                CreateStudioView(vm: vm)
            }
            .tabItem {
                Label("Create", systemName: "plus.circle.fill")
            }

            // Tab 5: Settings
            NavigationStack {
                SettingsDashboardView(vm: vm)
            }
            .tabItem {
                Label("Settings", systemName: "gearshape.fill")
            }
        }
        .tint(.pocketPrimary)
        .preferredColorScheme(.dark) // Clean premium dark-theme by default
        .task {
            await vm.start()
        }
        // Unified loading overlay
        .overlay {
            if vm.isLoadingModel, let modelId = vm.loadingModelId {
                let modelName = vm.models.first { $0.id == modelId }?.name ?? "Model"
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                ModelLoadingView(
                    modelName: modelName,
                    progress: vm.loadingProgress > 0 ? vm.loadingProgress : nil,
                    onCancel: {
                        Task { await vm.aiEngine.unloadModel(modelId, engineKind: .text) }
                    }
                )
            }
        }
        // Unified alert error handler
        .alert(
            vm.currentError?.errorDescription ?? "Error occurred",
            isPresented: $vm.showErrorAlert,
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                if let reason = vm.currentError?.failureReason {
                    Text(reason)
                }
            }
        )
    }
}
