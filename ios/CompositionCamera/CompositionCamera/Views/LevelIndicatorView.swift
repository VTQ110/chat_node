import SwiftUI

/// A horizon line that stays level with the world; turns green when the phone is straight.
struct LevelIndicatorView: View {
    let rollDegrees: Double

    private var isLevel: Bool { abs(rollDegrees) < 1 }

    var body: some View {
        let color: Color = isLevel ? .green : .white

        VStack(spacing: 6) {
            ZStack {
                // Fixed reference ticks, aligned with the phone.
                HStack(spacing: 150) {
                    Rectangle().frame(width: 18, height: 2)
                    Rectangle().frame(width: 18, height: 2)
                }
                .foregroundColor(color.opacity(0.8))

                // World horizon.
                Rectangle()
                    .fill(color)
                    .frame(width: 130, height: isLevel ? 2 : 1.5)
                    .rotationEffect(.degrees(isLevel ? 0 : -rollDegrees))
            }
            .shadow(color: .black.opacity(0.6), radius: 1)

            Text(isLevel ? "Cân bằng" : String(format: "%.0f°", rollDegrees))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundColor(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.45)))
        }
        .animation(.easeOut(duration: 0.1), value: isLevel)
        .allowsHitTesting(false)
    }
}
