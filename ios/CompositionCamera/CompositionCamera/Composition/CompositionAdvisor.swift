import CoreGraphics

/// Live framing advice: where the subject is, where it should go, and how to move the phone.
struct CompositionAdvice: Equatable {
    let subjectCenter: CGPoint
    let target: CGPoint
    let isAligned: Bool
    let message: String
    /// SF Symbol for the direction the *camera* should move, if any.
    let arrow: String?
}

enum CompositionAdvisor {
    /// Distance (as a fraction of the frame) at which the subject counts as "on" a power point.
    private static let alignedTolerance: CGFloat = 0.05
    /// Minimum per-axis offset worth telling the user about.
    private static let axisTolerance: CGFloat = 0.035

    static func advice(subject: CGRect,
                       kind: SubjectKind,
                       focusPoints: [CGPoint],
                       frame: CGSize) -> CompositionAdvice? {
        guard frame.width > 0, frame.height > 0 else { return nil }

        let frameArea = frame.width * frame.height
        let subjectCenter = subject.center

        // Subject fills too much of the frame: suggest stepping back before anything else.
        let tooBig = kind == .face ? subject.height > frame.height * 0.45 : subject.area > frameArea * 0.5
        if tooBig {
            return CompositionAdvice(subjectCenter: subjectCenter,
                                     target: subjectCenter,
                                     isAligned: false,
                                     message: "Lùi ra xa một chút để có khoảng thở",
                                     arrow: "arrow.down.backward.and.arrow.up.forward")
        }

        guard let target = focusPoints.min(by: {
            $0.distance(to: subjectCenter) < $1.distance(to: subjectCenter)
        }) else { return nil }

        // How far the subject has to travel inside the frame, normalized.
        let dx = (target.x - subjectCenter.x) / frame.width
        let dy = (target.y - subjectCenter.y) / frame.height

        if hypot(dx, dy) < alignedTolerance {
            let message = kind == .face ? "Bố cục đẹp! Giữ yên và chụp" : "Chủ thể đã đúng vị trí – chụp thôi!"
            return CompositionAdvice(subjectCenter: subjectCenter, target: target,
                                     isAligned: true, message: message, arrow: nil)
        }

        // To move the subject right in the frame the camera has to pan left, and so on.
        let horizontal: Pan? = dx > axisTolerance ? .left : (dx < -axisTolerance ? .right : nil)
        let vertical: Pan? = dy > axisTolerance ? .up : (dy < -axisTolerance ? .down : nil)

        let parts = [horizontal, vertical].compactMap { $0?.words }
        let message = parts.isEmpty
            ? "Dịch nhẹ máy để chủ thể vào điểm vàng"
            : "Hướng máy " + parts.joined(separator: " và ")

        return CompositionAdvice(subjectCenter: subjectCenter,
                                 target: target,
                                 isAligned: false,
                                 message: message,
                                 arrow: arrowSymbol(horizontal: horizontal, vertical: vertical))
    }

    private enum Pan {
        case left, right, up, down

        var words: String {
            switch self {
            case .left: return "sang trái"
            case .right: return "sang phải"
            case .up: return "lên trên"
            case .down: return "xuống dưới"
            }
        }
    }

    private static func arrowSymbol(horizontal: Pan?, vertical: Pan?) -> String? {
        switch (horizontal, vertical) {
        case (.left?, nil): return "arrow.left"
        case (.right?, nil): return "arrow.right"
        case (nil, .up?): return "arrow.up"
        case (nil, .down?): return "arrow.down"
        case (.left?, .up?): return "arrow.up.left"
        case (.right?, .up?): return "arrow.up.right"
        case (.left?, .down?): return "arrow.down.left"
        case (.right?, .down?): return "arrow.down.right"
        default: return nil
        }
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
