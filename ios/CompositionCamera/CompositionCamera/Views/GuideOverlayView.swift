import SwiftUI

/// Draws the selected composition guide, its power points and — when a subject is
/// detected — a box around it with a line to the power point it should move to.
struct GuideOverlayView: View {
    let guide: CompositionGuide
    let variant: Int
    let subjectRect: CGRect?
    let advice: CompositionAdvice?

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let points = guide.focusPoints(in: rect, variant: variant)

            ZStack {
                guide.path(in: rect, variant: variant)
                    .stroke(Color.white.opacity(0.75), lineWidth: 1)
                    .shadow(color: .black.opacity(0.6), radius: 1)

                ForEach(points.indices, id: \.self) { index in
                    let point = points[index]
                    let isTarget = advice.map { $0.target == point } ?? false
                    Circle()
                        .stroke(isTarget ? Color.yellow : Color.white.opacity(0.8),
                                lineWidth: isTarget ? 2 : 1)
                        .frame(width: isTarget ? 22 : 12, height: isTarget ? 22 : 12)
                        .position(point)
                }

                if let subjectRect, let advice {
                    let color: Color = advice.isAligned ? .green : .yellow

                    RoundedRectangle(cornerRadius: 6)
                        .stroke(color, style: StrokeStyle(lineWidth: 2, dash: advice.isAligned ? [] : [6, 4]))
                        .frame(width: subjectRect.width, height: subjectRect.height)
                        .position(x: subjectRect.midX, y: subjectRect.midY)

                    if !advice.isAligned {
                        Path { path in
                            path.move(to: advice.subjectCenter)
                            path.addLine(to: advice.target)
                        }
                        .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    }

                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .position(advice.subjectCenter)
                }
            }
            .animation(.easeOut(duration: 0.15), value: subjectRect)
        }
        .allowsHitTesting(false)
    }
}
