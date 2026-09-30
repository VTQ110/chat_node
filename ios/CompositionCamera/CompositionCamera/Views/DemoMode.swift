import SwiftUI
import UIKit
import Vision

/// Screenshot mode for the Simulator, which has no camera. Enabled only in Debug builds with
/// launch arguments, e.g. `-demo YES -demoImage portrait -demoGuide goldenSpiral -demoAlign YES`.
/// A bundled sample photo stands in for the camera feed, and the subject is found by running the
/// same kind of Vision detection on that photo.
struct DemoMode {
    let image: UIImage
    let guide: CompositionGuide
    let variant: Int
    let smartGuideOn: Bool
    let levelOn: Bool
    let rollDegrees: Double
    let showTip: Bool
    let toast: String?
    let showThumbnail: Bool
    let status: CameraService.Status
    let subjectKind: SubjectKind?
    /// Subject bounds in the sample photo, normalized with a top-left origin.
    let subjectInImage: CGRect?
    /// Zoom applied to the photo, so it can be "panned" like a real camera.
    let zoom: CGFloat
    /// Move the photo so the subject sits on the nearest power point (the "after" shot).
    let align: Bool

    static let current: DemoMode? = {
        #if DEBUG
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "demo") else { return nil }
        return DemoMode(defaults: defaults)
        #else
        return nil
        #endif
    }()

    private init(defaults: UserDefaults) {
        func bool(_ key: String, default value: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
        }

        let name = defaults.string(forKey: "demoImage") ?? "portrait"
        image = Bundle.main.url(forResource: "demo_\(name)", withExtension: "jpg")
            .flatMap { UIImage(contentsOfFile: $0.path) } ?? Self.placeholder()
        guide = defaults.string(forKey: "demoGuide").flatMap(CompositionGuide.init(rawValue:)) ?? .ruleOfThirds
        variant = defaults.integer(forKey: "demoVariant")
        smartGuideOn = bool("demoSmart", default: true)
        levelOn = bool("demoLevel", default: true)
        rollDegrees = defaults.double(forKey: "demoRoll")
        showTip = bool("demoTip", default: false)
        toast = defaults.string(forKey: "demoToast")
        showThumbnail = bool("demoThumbnail", default: false)
        status = defaults.string(forKey: "demoStatus") == "unauthorized" ? .unauthorized : .running
        zoom = max(1, CGFloat(defaults.double(forKey: "demoZoom")))
        align = bool("demoAlign", default: false)

        if let manual = defaults.string(forKey: "demoSubject").flatMap(Self.parseRect) {
            subjectInImage = manual
            subjectKind = defaults.string(forKey: "demoKind") == "face" ? .face : .salientObject
        } else if let detected = Self.detectSubject(in: image) {
            subjectInImage = detected.rect
            subjectKind = detected.kind
        } else {
            subjectInImage = nil
            subjectKind = nil
        }
    }

    // MARK: - Layout

    /// Where the (zoomed, possibly shifted) photo is drawn inside the viewfinder.
    func imageFrame(in frame: CGRect) -> CGRect {
        let size = CGSize(width: frame.width * zoom, height: frame.height * zoom)
        var origin = CGPoint(x: (frame.width - size.width) / 2, y: (frame.height - size.height) / 2)

        if align, let subject = subjectInImage {
            let center = CGPoint(x: subject.midX * size.width, y: subject.midY * size.height)
            let points = guide.focusPoints(in: frame, variant: variant)
            let current = CGPoint(x: origin.x + center.x, y: origin.y + center.y)
            if let target = points.min(by: { $0.distance(to: current) < $1.distance(to: current) }) {
                origin.x = min(0, max(frame.width - size.width, target.x - center.x))
                origin.y = min(0, max(frame.height - size.height, target.y - center.y))
            }
        }
        return CGRect(origin: origin, size: size)
    }

    func subjectRect(in frame: CGRect) -> CGRect? {
        guard let subject = subjectInImage else { return nil }
        let image = imageFrame(in: frame)
        return CGRect(x: image.minX + subject.minX * image.width,
                      y: image.minY + subject.minY * image.height,
                      width: subject.width * image.width,
                      height: subject.height * image.height)
    }

    // MARK: - Helpers

    private static func parseRect(_ string: String) -> CGRect? {
        let values = string.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 4 else { return nil }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    private static func detectSubject(in image: UIImage) -> (rect: CGRect, kind: SubjectKind)? {
        guard let cgImage = image.cgImage else { return nil }
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)

        let faces = VNDetectFaceRectanglesRequest()
        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
        faces.usesCPUOnly = true
        saliency.usesCPUOnly = true
        try? handler.perform([faces, saliency])

        func topLeft(_ box: CGRect) -> CGRect {
            CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        }
        if let face = faces.results?.max(by: { $0.boundingBox.area < $1.boundingBox.area }) {
            return (topLeft(face.boundingBox), .face)
        }
        if let object = saliency.results?.first?.salientObjects?.max(by: { $0.boundingBox.area < $1.boundingBox.area }) {
            return (topLeft(object.boundingBox), .salientObject)
        }
        return nil
    }

    private static func placeholder() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        }
    }
}

/// Stands in for the camera preview in screenshot mode.
struct DemoPreviewView: View {
    let demo: DemoMode

    var body: some View {
        GeometryReader { geo in
            let rect = demo.imageFrame(in: CGRect(origin: .zero, size: geo.size))
            Image(uiImage: demo.image)
                .resizable()
                .scaledToFill()
                .frame(width: rect.width, height: rect.height)
                .clipped()
                .offset(x: rect.minX, y: rect.minY)
        }
        .clipped()
    }
}
