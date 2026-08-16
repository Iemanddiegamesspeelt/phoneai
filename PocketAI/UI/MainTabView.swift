import SwiftUI

@MainActor
public struct MainTabView: View {
    @StateObject private var vm = HomeViewModel()

    public init() {}

    public var body: some View {
        tabViewContent
            .tint(.pocketPrimary)
            .preferredColorScheme(.dark)
            .task {
                await vm.start()
            }
            .overlay {
                loadingOverlay
            }
            .alert(
                vm.currentError?.errorDescription ?? "Error occurred",
                isPresented: $vm.showErrorAlert,
                actions: {
                    Button("OK", role: .cancel) {}
                },
                message: {
                    Text(vm.currentError?.failureReason ?? "")
                }
            )
    }

    @ViewBuilder
    private var tabViewContent: some View {
        TabView {
            NavigationStack {
                HomeDashboardView(vm: vm)
            }
            .tabItem {
                Label("Home", systemName: "house.fill")
            }

            NavigationStack {
                CatalogListView(vm: vm)
            }
            .tabItem {
                Label("Models", systemName: "cpu")
            }

            NavigationStack {
                ChatAssistantView(vm: vm)
            }
            .tabItem {
                Label("Chat", systemName: "bubble.left.and.bubble.right.fill")
            }

            NavigationStack {
                CreateStudioView(vm: vm)
            }
            .tabItem {
                Label("Create", systemName: "plus.circle.fill")
            }

            NavigationStack {
                SettingsDashboardView(vm: vm)
            }
            .tabItem {
                Label("Settings", systemName: "gearshape.fill")
            }
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if vm.isLoadingModel, let modelId = vm.loadingModelId {
            let modelName = vm.models.first { $0.id == modelId }?.name ?? "Model"
            ZStack {
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
    }
}
