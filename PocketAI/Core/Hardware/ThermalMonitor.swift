import Foundation
import Combine

// MARK: - ThermalMonitor

/// Observes device thermal state changes and publishes them as an `AsyncStream`.
/// The AIEngine uses this to throttle inference when the device gets hot.
public actor ThermalMonitor {

    /// Current thermal state.
    public private(set) var currentState: ProcessInfo.ThermalState

    /// Continuation for the async stream of thermal state changes.
    private var continuation: AsyncStream<ThermalEvent>.Continuation?

    /// The async stream of thermal events. Observe this from the AIEngine.
    public private(set) var events: AsyncStream<ThermalEvent>!

    /// Cancellable for NotificationCenter observation.
    private var cancellable: AnyCancellable?

    public init() {
        self.currentState = ProcessInfo.processInfo.thermalState

        var continuation: AsyncStream<ThermalEvent>.Continuation!
        self.events = AsyncStream { cont in
            continuation = cont
        }
        self.continuation = continuation

        // Observe thermal state changes from NotificationCenter.
        self.cancellable = NotificationCenter.default.publisher(
            for: ProcessInfo.thermalStateDidChangeNotification
        )
        .sink { [weak self] _ in
            guard let self else { return }
            Task { await self.handleThermalChange() }
        }
    }

    deinit {
        continuation?.finish()
        cancellable?.cancel()
    }

    // MARK: - Internal

    private func handleThermalChange() {
        let newState = ProcessInfo.processInfo.thermalState
        let oldState = currentState
        currentState = newState

        let event = ThermalEvent(
            previousState: oldState,
            currentState: newState,
            recommendation: Self.recommendation(for: newState)
        )
        continuation?.yield(event)
    }

    // MARK: - Recommendations

    /// Get the current workload recommendation based on thermal state.
    public static func recommendation(for state: ProcessInfo.ThermalState) -> ThermalRecommendation {
        switch state {
        case .nominal:
            return ThermalRecommendation(
                shouldThrottle: false,
                maxConcurrency: nil,
                reduceResolution: false,
                reduceBatchSize: false,
                message: nil
            )
        case .fair:
            return ThermalRecommendation(
                shouldThrottle: false,
                maxConcurrency: nil,
                reduceResolution: false,
                reduceBatchSize: false,
                message: "Device is slightly warm."
            )
        case .serious:
            return ThermalRecommendation(
                shouldThrottle: true,
                maxConcurrency: 2,
                reduceResolution: true,
                reduceBatchSize: true,
                message: "🌡️ Device is getting warm. Reducing workload to protect performance."
            )
        case .critical:
            return ThermalRecommendation(
                shouldThrottle: true,
                maxConcurrency: 1,
                reduceResolution: true,
                reduceBatchSize: true,
                message: "🔥 Device is very hot. Inference paused to prevent thermal shutdown."
            )
        @unknown default:
            return ThermalRecommendation(
                shouldThrottle: false,
                maxConcurrency: nil,
                reduceResolution: false,
                reduceBatchSize: false,
                message: nil
            )
        }
    }
}

// MARK: - ThermalEvent

/// A thermal state change event with recommendations for workload adjustment.
public struct ThermalEvent: Sendable {
    public let previousState: ProcessInfo.ThermalState
    public let currentState: ProcessInfo.ThermalState
    public let recommendation: ThermalRecommendation
    public let timestamp: Date

    public init(
        previousState: ProcessInfo.ThermalState,
        currentState: ProcessInfo.ThermalState,
        recommendation: ThermalRecommendation,
        timestamp: Date = Date()
    ) {
        self.previousState = previousState
        self.currentState = currentState
        self.recommendation = recommendation
        self.timestamp = timestamp
    }
}

// MARK: - ThermalRecommendation

/// Workload adjustment recommendations based on thermal state.
public struct ThermalRecommendation: Sendable {
    /// Whether inference should be throttled or paused.
    public let shouldThrottle: Bool

    /// Maximum concurrent operations (nil = unlimited).
    public let maxConcurrency: Int?

    /// Whether image generation resolution should be reduced.
    public let reduceResolution: Bool

    /// Whether batch sizes should be reduced.
    public let reduceBatchSize: Bool

    /// User-facing message to display, if any.
    public let message: String?
}
