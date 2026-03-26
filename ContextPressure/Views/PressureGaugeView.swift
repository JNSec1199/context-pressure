// Context Pressure — AI Context Window Monitor
// Copyright (c) 2026 Jason Nichols
// Licensed under the MIT License. See LICENSE file for details.

import SwiftUI

/// Animated arc gauge showing context pressure with smooth color gradient.
struct PressureGaugeView: View {
    let percentage: Double  // 0.0 to 1.0
    let level: PressureLevel

    @State private var animatedPercentage: Double = 0

    private let lineWidth: CGFloat = 12
    private let startAngle: Double = 135
    private let endAngle: Double = 405  // 135 + 270 degrees

    var body: some View {
        ZStack {
            // Background track
            Arc(startAngle: startAngle, endAngle: endAngle)
                .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            // Filled arc with gradient
            Arc(startAngle: startAngle, endAngle: startAngle + (endAngle - startAngle) * animatedPercentage)
                .stroke(
                    AngularGradient(
                        gradient: pressureGradient,
                        center: .center,
                        startAngle: .degrees(startAngle),
                        endAngle: .degrees(startAngle + (endAngle - startAngle) * max(animatedPercentage, 0.01))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            // Center text
            VStack(spacing: 2) {
                Text("\(Int(animatedPercentage * 100))%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(colorForPercentage(animatedPercentage))

                Text(level.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(colorForPercentage(animatedPercentage))
                    .opacity(0.9)
            }
        }
        .frame(width: 120, height: 120)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animatedPercentage = percentage
            }
        }
        .onChange(of: percentage) { newValue in
            withAnimation(.easeInOut(duration: 0.5)) {
                animatedPercentage = newValue
            }
        }
    }

    // MARK: - Gradient

    private var pressureGradient: Gradient {
        if animatedPercentage < 0.5 {
            return Gradient(colors: [.green, .green])
        } else if animatedPercentage < 0.65 {
            return Gradient(colors: [.green, .yellow])
        } else if animatedPercentage < 0.75 {
            return Gradient(colors: [.green, .yellow, .orange])
        } else if animatedPercentage < 0.85 {
            return Gradient(colors: [.green, .yellow, .orange, .red])
        } else {
            return Gradient(colors: [.green, .yellow, .orange, .red, .red])
        }
    }

    private func colorForPercentage(_ pct: Double) -> Color {
        if pct < 0.5 { return .green }
        if pct < 0.65 { return .yellow }
        if pct < 0.75 { return .orange }
        return .red
    }
}

// MARK: - Arc Shape

struct Arc: Shape {
    let startAngle: Double
    let endAngle: Double

    var animatableData: Double {
        get { endAngle }
        set { }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 8
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(endAngle),
            clockwise: false
        )
        return path
    }
}

// MARK: - Mini Bar View (for compact display)

struct MiniPressureBar: View {
    let percentage: Double
    let width: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 6)

                // Fill
                RoundedRectangle(cornerRadius: 3)
                    .fill(barGradient)
                    .frame(width: max(geo.size.width * CGFloat(percentage), 4), height: 6)
            }
        }
        .frame(width: width, height: 6)
    }

    private var barGradient: LinearGradient {
        let color = colorForPct(percentage)
        return LinearGradient(
            colors: [color.opacity(0.8), color],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func colorForPct(_ pct: Double) -> Color {
        if pct < 0.5 { return .green }
        if pct < 0.65 { return .yellow }
        if pct < 0.75 { return .orange }
        return .red
    }
}
