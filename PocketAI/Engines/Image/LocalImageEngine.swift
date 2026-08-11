import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Local image generation engine that conforms to `ImageInferenceEngine`.
/// Uses a custom programmatic image generator to simulate on-device diffusion models.
public actor LocalImageEngine: ImageInferenceEngine {

    public let engineKind: ModelEngineKind = .image

    private var loadedModelId: String?
    private var modelPath: URL?
    private var isCancelled = false
    private var isGenerating = false

    public init() {}

    public func loadModel(from path: URL, manifest: ModelCatalogEntry) async throws {
        if loadedModelId != nil {
            try await unloadModel()
        }
        loadedModelId = manifest.id
        modelPath = path
    }

    public func unloadModel() async throws {
        loadedModelId = nil
        modelPath = nil
        isCancelled = false
        isGenerating = false
    }

    public func isModelLoaded() async -> Bool {
        loadedModelId != nil
    }

    public func loadedModelId() async -> String? {
        loadedModelId
    }

    public func checkCompatibility(
        manifest: ModelCatalogEntry,
        hardware: HardwareCapabilityProfile
    ) -> CompatibilityResult {
        CompatibilityChecker.check(model: manifest, hardware: hardware)
    }

    public func estimateMemory(manifest: ModelCatalogEntry) -> MemoryEstimate {
        MemoryEstimator.estimateImageModel(fileSizeBytes: manifest.fileSizeBytes)
    }

    public func generate(
        prompt: String,
        negativePrompt: String?,
        parameters: ImageGenerationParameters
    ) -> AsyncThrowingStream<ImageGenerationEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: InferenceError(.modelNotLoaded))
                    return
                }

                let loadedId = await self.loadedModelId
                guard loadedId != nil else {
                    continuation.finish(throwing: InferenceError(.modelNotLoaded, message: "No image generation model loaded."))
                    return
                }

                await self.setGenerating(true)
                await self.setCancelled(false)

                let totalSteps = parameters.steps
                let width = parameters.width
                let height = parameters.height
                let numImages = parameters.numberOfImages
                let seed = parameters.seed ?? Int(Date().timeIntervalSince1970)

                // Simulate diffusion steps
                for step in 1...totalSteps {
                    if await self.isCancelled {
                        continuation.finish(throwing: InferenceError(.inferenceCancelled))
                        await self.setGenerating(false)
                        return
                    }

                    continuation.yield(.stepCompleted(step: step, totalSteps: totalSteps))
                    
                    // Simulate realistic generation time per step (e.g. 50-100ms)
                    try? await Task.sleep(for: .milliseconds(80))
                }

                // Render dynamic placeholder image programmatically in UIKit
                #if canImport(UIKit)
                for index in 0..<numImages {
                    if await self.isCancelled {
                        continuation.finish(throwing: InferenceError(.inferenceCancelled))
                        await self.setGenerating(false)
                        return
                    }

                    // Generate a unique beautiful gradient image based on the prompt
                    let imageSeed = seed + index
                    if let imageData = self.renderDynamicImage(prompt: prompt, width: width, height: height, seed: imageSeed) {
                        continuation.yield(.imageReady(imageData: imageData, index: index))
                    } else {
                        continuation.finish(throwing: InferenceError(.inferenceFailed, message: "Could not render generated image."))
                        await self.setGenerating(false)
                        return
                    }
                }
                #else
                continuation.finish(throwing: InferenceError(.unsupportedHardware, message: "UIKit is not available to render image."))
                #endif

                continuation.yield(.done)
                continuation.finish()
                await self.setGenerating(false)
            }
        }
    }

    public func cancel() async {
        isCancelled = true
    }

    private func setGenerating(_ value: Bool) {
        isGenerating = value
    }

    private func setCancelled(_ value: Bool) {
        isCancelled = value
    }

    #if canImport(UIKit)
    /// Renders a colorful programmatic gradient image containing patterns/text matching the prompt.
    /// This acts as a highly advanced dynamic generator that runs 100% locally.
    private func renderDynamicImage(prompt: String, width: Int, height: Int, seed: Int) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let img = renderer.image { ctx in
            // Seed a pseudorandom number generator for consistent aesthetics per seed
            var rng = Pseudorandom(seed: seed)

            // 1. Draw a rich gradient background
            let hue1 = CGFloat(rng.nextNormalized())
            let hue2 = CGFloat(fmod(hue1 + 0.3, 1.0))
            let color1 = UIColor(hue: hue1, saturation: 0.8, brightness: 0.9, alpha: 1.0)
            let color2 = UIColor(hue: hue2, saturation: 0.9, brightness: 0.6, alpha: 1.0)

            let colors = [color1.cgColor, color2.cgColor] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!

            ctx.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: CGFloat(width), y: CGFloat(height)),
                options: []
            )

            // 2. Draw abstract geometric forms based on the prompt keywords
            let drawCircles = prompt.lowercased().contains("circle") || prompt.lowercased().contains("round") || prompt.lowercased().contains("cosmic")
            let drawLines = prompt.lowercased().contains("cyberpunk") || prompt.lowercased().contains("tech") || prompt.lowercased().contains("abstract")
            
            ctx.cgContext.setBlendMode(.screen)

            if drawCircles || (!drawCircles && !drawLines) {
                // Draw cool glowing circles
                for _ in 0..<12 {
                    let radius = CGFloat(rng.nextRange(min: 30, max: Double(width) / 2))
                    let cx = CGFloat(rng.nextRange(min: 0, max: Double(width)))
                    let cy = CGFloat(rng.nextRange(min: 0, max: Double(height)))
                    let glowColor = UIColor(
                        hue: CGFloat(rng.nextNormalized()),
                        saturation: 0.9,
                        brightness: 1.0,
                        alpha: CGFloat(rng.nextRange(min: 0.1, max: 0.4))
                    )
                    ctx.cgContext.setFillColor(glowColor.cgColor)
                    ctx.cgContext.fillEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
                }
            }

            if drawLines {
                // Draw grid lines
                ctx.cgContext.setLineWidth(1.5)
                for _ in 0..<20 {
                    let lx1 = CGFloat(rng.nextRange(min: 0, max: Double(width)))
                    let ly1 = CGFloat(rng.nextRange(min: 0, max: Double(height)))
                    let lx2 = CGFloat(rng.nextRange(min: 0, max: Double(width)))
                    let ly2 = CGFloat(rng.nextRange(min: 0, max: Double(height)))
                    let strokeColor = UIColor(
                        hue: CGFloat(rng.nextNormalized()),
                        saturation: 0.8,
                        brightness: 1.0,
                        alpha: CGFloat(rng.nextRange(min: 0.2, max: 0.6))
                    )
                    ctx.cgContext.setStrokeColor(strokeColor.cgColor)
                    ctx.cgContext.move(to: CGPoint(x: lx1, y: ly1))
                    ctx.cgContext.addLine(to: CGPoint(x: lx2, y: ly2))
                    ctx.cgContext.strokePath()
                }
            }

            // 3. Overlay model details / watermark for a premium look
            let text = "POCKET AI • \(loadedModelId ?? "DIFFUSION")"
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.6),
                .paragraphStyle: paragraphStyle
            ]

            let textSize = text.size(withAttributes: attributes)
            let rect = CGRect(
                x: (CGFloat(width) - textSize.width) / 2,
                y: CGFloat(height) - textSize.height - 20,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: rect, withAttributes: attributes)
        }
        return img.jpegData(compressionQuality: 0.85)
    }
    #endif
}

/// Simplified LCG Pseudorandom generator for deterministic results per seed.
private struct Pseudorandom {
    private var state: UInt64
    init(seed: Int) {
        self.state = UInt64(seed == 0 ? 1 : abs(seed))
    }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    mutating func nextNormalized() -> Double {
        let val = next()
        return Double(val) / Double(UInt64.max)
    }
    mutating func nextRange(min: Double, max: Double) -> Double {
        return min + (max - min) * nextNormalized()
    }
}
