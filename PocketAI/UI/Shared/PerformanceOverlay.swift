import SwiftUI

// MARK: - PerformanceOverlay

/// Compact overlay shown during inference displaying real-time metrics.
public struct PerformanceOverlay: View {
    let metrics: InferenceMetrics?
    let thermalState: ProcessInfo.ThermalState
    let memoryUsedFormatted: String
    let isVisible: Bool

    public init(
        metrics: InferenceMetrics? = nil,
        thermalState: ProcessInfo.ThermalState = .nominal,
        memoryUsedFormatted: String = "—",
        isVisible: Bool = true
    ) {
        self.metrics = metrics
        self.thermalState = thermalState
        self.memoryUsedFormatted = memoryUsedFormatted
        self.isVisible = isVisible
    }

    public var body: some View {
        if isVisible, let metrics {
            HStack(spacing: 12) {
                // Tokens/sec
                metricItem(
                    icon: "speedometer",
                    value: String(format: "%.1f", metrics.tokensPerSecond),
                    unit: "tok/s"
                )

                Divider()
                    .frame(height: 16)

                // Memory
                metricItem(
                    icon: "memorychip",
                    value: memoryUsedFormatted,
                    unit: ""
                )

                Divider()
                    .frame(height: 16)

                // Backend
                metricItem(
                    icon: backendIcon(metrics.activeBackend),
                    value: metrics.activeBackend.displayName,
                    unit: ""
                )

                // Thermal indicator
                if thermalState != .nominal {
                    Divider()
                        .frame(height: 16)
                    thermalIndicator
                }
            }
            .font(.caption2)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassCard(cornerRadius: 20)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func metricItem(icon: String, value: String, unit: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var thermalIndicator: some View {
        HStack(spacing: 3) {
            Image(systemName: thermalIcon)
                .font(.system(size: 9))
                .foregroundStyle(thermalColor)
            Text(thermalLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(thermalColor)
        }
    }

    private var thermalIcon: String {
        switch thermalState {
        case .fair:     return "thermometer.medium"
        case .serious:  return "thermometer.high"
        case .critical: return "flame"
        default:        return "thermometer.low"
        }
    }

    private var thermalColor: Color {
        switch thermalState {
        case .fair:     return .pocketWarning
        case .serious:  return .orange
        case .critical: return .pocketError
        default:        return .pocketSuccess
        }
    }

    private var thermalLabel: String {
        switch thermalState {
        case .fair:     return "Warm"
        case .serious:  return "Hot"
        case .critical: return "Critical"
        default:        return "OK"
        }
    }

    private func backendIcon(_ backend: InferenceBackendKind) -> String {
        switch backend {
        case .neuralEngine: return "brain"
        case .gpu, .metal:  return "gpu"
        case .mlx:          return "cpu"
        case .coreml:       return "brain.head.profile"
        case .cpu:          return "cpu"
        }
    }
}

// MARK: - Download Progress Bar

/// A styled download progress view with speed and ETA.
public struct DownloadProgressBar: View {
    let task: DownloadTask

    public init(task: DownloadTask) {
        self.task = task
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Model name and status
            HStack {
                Text(task.modelName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(task.percentFormatted)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.pocketPrimary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.pocketPrimary.opacity(0.12))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.pocketPrimary, Color(red: 0.5, green: 0.4, blue: 1.0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * task.progress, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: task.progress)
                }
            }
            .frame(height: 8)

            // Stats row
            HStack {
                Text(task.progressFormatted)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(task.speedFormatted)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("•")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                Text("ETA: \(task.etaFormatted)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }
}

/// Loading indicator for model loading.
public struct ModelLoadingView: View {
    let modelName: String
    let progress: Double?
    let onCancel: () -> Void

    public var body: some View {
        VStack(spacing: 16) {
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.pocketPrimary)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.pocketPrimary)
            }

            Text("Loading \(modelName)…")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Cancel", action: onCancel)
                .font(.subheadline)
                .foregroundStyle(Color.pocketError)
        }
        .padding(24)
        .glassCard()
    }
}

/// Error display view with recovery suggestions.
public struct InferenceErrorView: View {
    let error: InferenceError
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?

    public init(error: InferenceError, onDismiss: @escaping () -> Void, onRetry: (() -> Void)? = nil) {
        self.error = error
        self.onDismiss = onDismiss
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.pocketError)
                Text(error.errorDescription ?? "Error")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            if let reason = error.failureReason {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(Color.pocketPrimary)
                    .padding(8)
                    .background(Color.pocketPrimary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if error.isRecoverable, let onRetry {
                Button("Try Again", action: onRetry)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.pocketPrimary)
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.pocketError.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.pocketError.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
