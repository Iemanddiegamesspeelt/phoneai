import SwiftUI

// MARK: - Design System

/// PocketAI's design system: colors, typography, spacing, and reusable components.
/// Gives the app a polished, premium Apple-quality feel.

// MARK: - Colors

public extension Color {
    /// Primary accent — a vibrant blue-purple gradient endpoint.
    static let pocketPrimary = Color(red: 0.35, green: 0.45, blue: 1.0)
    /// Secondary accent — warm coral.
    static let pocketSecondary = Color(red: 1.0, green: 0.45, blue: 0.4)
    /// Tertiary accent — teal.
    static let pocketTertiary = Color(red: 0.3, green: 0.85, blue: 0.8)
    /// Success green.
    static let pocketSuccess = Color(red: 0.3, green: 0.85, blue: 0.5)
    /// Warning amber.
    static let pocketWarning = Color(red: 1.0, green: 0.75, blue: 0.2)
    /// Error red.
    static let pocketError = Color(red: 1.0, green: 0.35, blue: 0.35)

    /// Surface background for cards.
    static let pocketSurface = Color(.systemBackground).opacity(0.8)
    /// Elevated surface (for glassmorphism).
    static let pocketElevated = Color(.secondarySystemBackground).opacity(0.6)
    /// Subtle text color.
    static let pocketSubtle = Color(.secondaryLabel)
}

// MARK: - Gradients

public extension LinearGradient {
    /// Primary gradient for hero elements.
    static let pocketPrimary = LinearGradient(
        colors: [Color.pocketPrimary, Color(red: 0.6, green: 0.35, blue: 1.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Warm gradient for creative/image features.
    static let pocketWarm = LinearGradient(
        colors: [Color(red: 1.0, green: 0.5, blue: 0.3), Color(red: 1.0, green: 0.3, blue: 0.5)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Cool gradient for data/technical features.
    static let pocketCool = LinearGradient(
        colors: [Color(red: 0.2, green: 0.6, blue: 1.0), Color.pocketTertiary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Surface gradient for card backgrounds.
    static let pocketSurface = LinearGradient(
        colors: [
            Color(.systemBackground).opacity(0.95),
            Color(.systemBackground).opacity(0.85)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - View Modifiers

/// Glassmorphism card style.
public struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 16

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
            )
    }
}

/// Gradient card style with border.
public struct GradientCard: ViewModifier {
    let gradient: LinearGradient
    var cornerRadius: CGFloat = 16

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(gradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            )
    }
}

/// Subtle press animation for interactive elements.
public struct PressableStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

public extension View {
    /// Apply glassmorphism card styling.
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }

    /// Apply gradient card styling.
    func gradientCard(_ gradient: LinearGradient = .pocketPrimary, cornerRadius: CGFloat = 16) -> some View {
        modifier(GradientCard(gradient: gradient, cornerRadius: cornerRadius))
    }
}

// MARK: - Reusable Components

/// A compact status badge.
public struct StatusBadge: View {
    let label: String
    let color: Color
    let icon: String?

    public init(_ label: String, color: Color = .pocketPrimary, icon: String? = nil) {
        self.label = label
        self.color = color
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

/// A circular gauge for displaying utilization ratios (e.g., memory, storage).
public struct GaugeView: View {
    let value: Double // 0.0 to 1.0
    let label: String
    let sublabel: String
    let color: Color

    public init(value: Double, label: String, sublabel: String = "", color: Color = .pocketPrimary) {
        self.value = min(1, max(0, value))
        self.label = label
        self.sublabel = sublabel
        self.color = color
    }

    public var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: value)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: value)

                Text("\(Int(value * 100))%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }
            .frame(width: 52, height: 52)

            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            if !sublabel.isEmpty {
                Text(sublabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A metric display card for showing inference stats.
public struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    public init(title: String, value: String, icon: String, color: Color = .pocketPrimary) {
        self.title = title
        self.value = value
        self.icon = icon
        self.color = color
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(cornerRadius: 12)
    }
}

/// Animated typing indicator dots.
public struct TypingIndicator: View {
    @State private var phase = 0.0

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.pocketPrimary)
                    .frame(width: 6, height: 6)
                    .offset(y: sin(phase + Double(index) * 0.8) * 3)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

/// Engine kind icon with colored background.
public struct EngineKindBadge: View {
    let kind: ModelEngineKind

    public var body: some View {
        Image(systemName: kind.iconName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(colorForKind(kind))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func colorForKind(_ kind: ModelEngineKind) -> Color {
        switch kind {
        case .text:   return .pocketPrimary
        case .image:  return .pocketSecondary
        case .vision: return .purple
        case .speech: return .pocketTertiary
        case .tts:    return .orange
        case .audio:  return .pink
        case .video:  return .indigo
        }
    }
}

/// Local/offline indicator badge.
public struct LocalBadge: View {
    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.pocketSuccess)
                .frame(width: 6, height: 6)
            Text("LOCAL")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.pocketSuccess)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.pocketSuccess.opacity(0.12))
        .clipShape(Capsule())
    }
}
