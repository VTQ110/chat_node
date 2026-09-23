import SwiftUI

/// A composition overlay the photographer can frame the shot against.
enum CompositionGuide: String, CaseIterable, Identifiable {
    case ruleOfThirds
    case goldenRatio
    case goldenSpiral
    case goldenTriangle
    case diagonals
    case symmetry
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ruleOfThirds: return "1/3"
        case .goldenRatio: return "Tỉ lệ vàng"
        case .goldenSpiral: return "Xoắn ốc"
        case .goldenTriangle: return "Tam giác"
        case .diagonals: return "Đường chéo"
        case .symmetry: return "Đối xứng"
        case .none: return "Tắt"
        }
    }

    var icon: String {
        switch self {
        case .ruleOfThirds: return "squareshape.split.3x3"
        case .goldenRatio: return "rectangle.split.3x3"
        case .goldenSpiral: return "hurricane"
        case .goldenTriangle: return "triangle"
        case .diagonals: return "line.diagonal"
        case .symmetry: return "plus.viewfinder"
        case .none: return "eye.slash"
        }
    }

    /// Short shooting tip shown when the guide is selected.
    var tip: String {
        switch self {
        case .ruleOfThirds:
            return "Đặt chủ thể tại một giao điểm, đường chân trời trùng với đường 1/3 trên hoặc dưới."
        case .goldenRatio:
            return "Giống quy tắc 1/3 nhưng các đường gần tâm hơn (0.382 / 0.618) – cảm giác cân đối, tự nhiên."
        case .goldenSpiral:
            return "Để mắt người xem đi theo đường xoắn, đặt chi tiết quan trọng nhất ở tâm xoắn. Nhấn ↻ để xoay."
        case .goldenTriangle:
            return "Xếp các đường nét, cạnh chéo theo đường chéo; chủ thể đặt ở chân đường vuông góc. Nhấn ↻ để lật."
        case .diagonals:
            return "Dùng đường chéo để tạo chiều sâu và chuyển động: đường ray, con đường, cầu thang…"
        case .symmetry:
            return "Đặt chủ thể chính giữa khi khung cảnh đối xứng: kiến trúc, mặt nước phản chiếu, chân dung."
        case .none:
            return "Đã tắt lưới bố cục."
        }
    }

    /// Number of orientations the guide can be flipped/rotated through.
    var variantCount: Int {
        switch self {
        case .goldenSpiral: return 4
        case .goldenTriangle, .diagonals: return 2
        default: return 1
        }
    }

    // MARK: - Geometry

    func path(in rect: CGRect, variant: Int) -> Path {
        let map = Mapper(rect: rect, variant: variant)
        var path = Path()

        func line(_ a: CGPoint, _ b: CGPoint) {
            path.move(to: map.point(a))
            path.addLine(to: map.point(b))
        }

        switch self {
        case .ruleOfThirds:
            addGrid(to: &path, fractions: [1.0 / 3, 2.0 / 3], rect: rect)

        case .goldenRatio:
            addGrid(to: &path, fractions: [1 - Self.inversePhi, Self.inversePhi], rect: rect)

        case .goldenSpiral:
            let spiral = Self.unitSpiral
            for square in spiral.squares {
                path.addPath(Path(map.rect(square)))
            }
            guard let first = spiral.arcs.first else { break }
            var spiralPath = Path()
            spiralPath.move(to: map.point(first.start))
            for arc in spiral.arcs {
                spiralPath.addCurve(to: map.point(arc.end),
                                    control1: map.point(arc.control1),
                                    control2: map.point(arc.control2))
            }
            path.addPath(spiralPath)

        case .goldenTriangle:
            let (footA, footB) = triangleFeet(in: rect)
            line(CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1))
            line(CGPoint(x: 1, y: 0), footA)
            line(CGPoint(x: 0, y: 1), footB)

        case .diagonals:
            line(CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1))
            line(CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1))
            // Baroque/sinister 45° lines from the short edges.
            let aspect = rect.width / max(rect.height, 1)
            line(CGPoint(x: 0, y: 0), CGPoint(x: 1, y: aspect))
            line(CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1 - aspect))

        case .symmetry:
            line(CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1))
            line(CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5))

        case .none:
            break
        }
        return path
    }

    /// The "power points" where a subject looks best for this guide, in `rect` coordinates.
    func focusPoints(in rect: CGRect, variant: Int) -> [CGPoint] {
        let map = Mapper(rect: rect, variant: variant)
        switch self {
        case .ruleOfThirds, .diagonals:
            let f: [CGFloat] = [1.0 / 3, 2.0 / 3]
            return f.flatMap { x in f.map { y in map.point(CGPoint(x: x, y: y)) } }
        case .goldenRatio:
            let f: [CGFloat] = [1 - Self.inversePhi, Self.inversePhi]
            return f.flatMap { x in f.map { y in map.point(CGPoint(x: x, y: y)) } }
        case .goldenSpiral:
            return [map.point(Self.unitSpiral.eye)]
        case .goldenTriangle:
            let (footA, footB) = triangleFeet(in: rect)
            return [map.point(footA), map.point(footB)]
        case .symmetry:
            return [map.point(CGPoint(x: 0.5, y: 0.5))]
        case .none:
            return []
        }
    }

    private func addGrid(to path: inout Path, fractions: [CGFloat], rect: CGRect) {
        for f in fractions {
            let x = rect.minX + rect.width * f
            let y = rect.minY + rect.height * f
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
    }

    /// Feet of the perpendiculars dropped from the top-right and bottom-left corners
    /// onto the top-left → bottom-right diagonal, in unit coordinates. The feet depend
    /// on the real aspect ratio, so they are computed from `rect`'s size.
    private func triangleFeet(in rect: CGRect) -> (CGPoint, CGPoint) {
        let w = rect.width, h = rect.height
        let d2 = max(w * w + h * h, 1)
        let tA = (w * w) / d2   // from the top-right corner
        let tB = (h * h) / d2   // from the bottom-left corner
        return (CGPoint(x: tA, y: tA), CGPoint(x: tB, y: tB))
    }

    // MARK: - Golden spiral

    static let phi: CGFloat = (1 + sqrt(5)) / 2
    static let inversePhi: CGFloat = 1 / phi

    struct Arc {
        let start: CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint
    }

    /// Fibonacci spiral built inside a portrait golden rectangle, normalized to the unit square.
    static let unitSpiral: (squares: [CGRect], arcs: [Arc], eye: CGPoint) = {
        enum Side { case top, right, bottom, left }
        let sides: [Side] = [.top, .right, .bottom, .left]
        let k: CGFloat = 0.5523 // Bézier constant for a quarter circle.
        let phi = CompositionGuide.phi

        var remaining = CGRect(x: 0, y: 0, width: 1, height: phi)
        var squares: [CGRect] = []
        var arcs: [Arc] = []

        for i in 0..<12 {
            let square: CGRect
            let start: CGPoint, end: CGPoint, corner: CGPoint
            let r = remaining
            switch sides[i % 4] {
            case .top:
                square = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.width)
                remaining = CGRect(x: r.minX, y: r.minY + r.width, width: r.width, height: r.height - r.width)
                start = CGPoint(x: square.minX, y: square.minY)
                end = CGPoint(x: square.maxX, y: square.maxY)
                corner = CGPoint(x: square.maxX, y: square.minY)
            case .right:
                square = CGRect(x: r.maxX - r.height, y: r.minY, width: r.height, height: r.height)
                remaining = CGRect(x: r.minX, y: r.minY, width: r.width - r.height, height: r.height)
                start = CGPoint(x: square.maxX, y: square.minY)
                end = CGPoint(x: square.minX, y: square.maxY)
                corner = CGPoint(x: square.maxX, y: square.maxY)
            case .bottom:
                square = CGRect(x: r.minX, y: r.maxY - r.width, width: r.width, height: r.width)
                remaining = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height - r.width)
                start = CGPoint(x: square.maxX, y: square.maxY)
                end = CGPoint(x: square.minX, y: square.minY)
                corner = CGPoint(x: square.minX, y: square.maxY)
            case .left:
                square = CGRect(x: r.minX, y: r.minY, width: r.height, height: r.height)
                remaining = CGRect(x: r.minX + r.height, y: r.minY, width: r.width - r.height, height: r.height)
                start = CGPoint(x: square.minX, y: square.maxY)
                end = CGPoint(x: square.maxX, y: square.minY)
                corner = CGPoint(x: square.minX, y: square.minY)
            }
            squares.append(square)
            arcs.append(Arc(start: start,
                            control1: CGPoint(x: start.x + (corner.x - start.x) * k,
                                              y: start.y + (corner.y - start.y) * k),
                            control2: CGPoint(x: end.x + (corner.x - end.x) * k,
                                              y: end.y + (corner.y - end.y) * k),
                            end: end))
        }

        // Squash the golden rectangle into the unit square.
        func normPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: p.y / phi) }
        func normRect(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: r.minY / phi, width: r.width, height: r.height / phi)
        }
        return (squares.prefix(6).map(normRect),
                arcs.map { Arc(start: normPoint($0.start), control1: normPoint($0.control1),
                               control2: normPoint($0.control2), end: normPoint($0.end)) },
                normPoint(CGPoint(x: remaining.midX, y: remaining.midY)))
    }()
}

/// Maps unit-square coordinates into a rect, applying the guide's flip variant.
private struct Mapper {
    let rect: CGRect
    let flipX: Bool
    let flipY: Bool

    init(rect: CGRect, variant: Int) {
        self.rect = rect
        flipX = variant & 1 != 0
        flipY = variant & 2 != 0
    }

    func point(_ unit: CGPoint) -> CGPoint {
        let x = flipX ? 1 - unit.x : unit.x
        let y = flipY ? 1 - unit.y : unit.y
        return CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }

    func rect(_ unit: CGRect) -> CGRect {
        let a = point(CGPoint(x: unit.minX, y: unit.minY))
        let b = point(CGPoint(x: unit.maxX, y: unit.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}
