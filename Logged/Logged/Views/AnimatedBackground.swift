import SwiftUI

/// Animated background with floating gradient orbs
struct AnimatedBackground: View {
    @State private var animationPhase: CGFloat = 0

    var body: some View {
        ZStack {
            // Base dark background
            Theme.Colors.background
                .ignoresSafeArea()

            // Animated floating orbs - enhanced for visibility
            OrbShape(
                offset: CGPoint(x: -100, y: -150),
                animationPhase: animationPhase,
                delay: 0,
                color: Theme.Colors.accent
            )

            OrbShape(
                offset: CGPoint(x: 150, y: -100),
                animationPhase: animationPhase,
                delay: 0.5,
                color: Theme.Colors.info
            )

            OrbShape(
                offset: CGPoint(x: -80, y: 200),
                animationPhase: animationPhase,
                delay: 1,
                color: Theme.Colors.accent.opacity(0.8)
            )

            OrbShape(
                offset: CGPoint(x: 120, y: 150),
                animationPhase: animationPhase,
                delay: 1.5,
                color: Theme.Colors.info.opacity(0.6)
            )

            // Subtle grid overlay
            GridOverlay()
                .opacity(0.03)
        }
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                animationPhase = 1
            }
        }
    }
}

/// Individual animated orb
private struct OrbShape: View {
    let offset: CGPoint
    let animationPhase: CGFloat
    let delay: Double
    let color: Color

    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [color.opacity(0.4), color.opacity(0)]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)

            // Inner solid orb
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [color.opacity(0.6), color.opacity(0.2)]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 80
                    )
                )
                .frame(width: 120, height: 120)
                .blur(radius: 8)
        }
        .offset(
            x: offset.x + 50 * sin(animationPhase * CGFloat.pi * 2 + CGFloat(delay)),
            y: offset.y + 30 * cos(animationPhase * CGFloat.pi * 2 + CGFloat(delay) * 0.7)
        )
    }
}

/// Subtle grid pattern for visual interest
private struct GridOverlay: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 60
            var x = 0.0

            while x < size.width {
                var y = 0.0
                while y < size.height {
                    let rect = CGRect(x: x, y: y, width: 1, height: 1)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(Theme.Colors.textPrimary)
                    )
                    y += spacing
                }
                x += spacing
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ZStack {
        AnimatedBackground()

        VStack {
            Text("Logged")
                .font(Theme.Typography.largeTitle)
                .foregroundColor(Theme.Colors.textPrimary)

            Spacer()
        }
        .padding()
    }
}
