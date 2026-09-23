import AVFoundation
import Photos
import UIKit
import Vision

/// What kind of subject the camera is currently tracking.
enum SubjectKind {
    case face
    case salientObject
}

/// Owns the capture session: live preview, photo capture and subject detection
/// (faces via AVCaptureMetadataOutput, other subjects via Vision saliency).
final class CameraService: NSObject, ObservableObject {
    enum Status {
        case idle
        case running
        case unauthorized
        case failed
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var position: AVCaptureDevice.Position = .back
    /// Subject bounds in preview-layer (view) coordinates.
    @Published private(set) var subjectRect: CGRect?
    @Published private(set) var subjectKind: SubjectKind?
    @Published private(set) var lastPhoto: UIImage?
    @Published private(set) var isCapturing = false
    @Published var toastMessage: String?

    let session = AVCaptureSession()
    /// Set by `CameraPreviewView`; used to map detection results into view coordinates.
    weak var previewLayer: AVCaptureVideoPreviewLayer?

    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let analysisQueue = DispatchQueue(label: "camera.analysis", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let metadataOutput = AVCaptureMetadataOutput()

    // Session-queue state.
    private var videoInput: AVCaptureDeviceInput?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var isConfigured = false
    private var photoDelegates: [Int64: PhotoCaptureDelegate] = [:]

    // Analysis-queue state.
    private var lastSaliencyRun = Date.distantPast
    private var lastFaceSeen = Date.distantPast
    private var consecutiveMisses = 0

    private static let saliencyInterval: TimeInterval = 0.25
    private static let faceHoldTime: TimeInterval = 0.6
    private static let missesBeforeClearing = 3

    // MARK: - Lifecycle

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.startSession()
                } else {
                    DispatchQueue.main.async { self?.status = .unauthorized }
                }
            }
        default:
            status = .unauthorized
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func startSession() {
        sessionQueue.async {
            if !self.isConfigured && !self.configureSession() {
                DispatchQueue.main.async { self.status = .failed }
                return
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async { self.status = .running }
        }
    }

    private func configureSession() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard let device = Self.camera(at: currentPosition),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)
        videoInput = input

        guard session.canAddOutput(photoOutput) else { return false }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: analysisQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            // Keep analysis frames in raw sensor orientation so their normalized
            // coordinates match the metadata-output coordinate space.
            if let connection = videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }

        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: analysisQueue)
            enableFaceDetection()
        }

        isConfigured = true
        return true
    }

    private func enableFaceDetection() {
        if metadataOutput.availableMetadataObjectTypes.contains(.face) {
            metadataOutput.metadataObjectTypes = [.face]
        }
    }

    private static func camera(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    // MARK: - Controls

    func switchCamera() {
        sessionQueue.async {
            let newPosition: AVCaptureDevice.Position = self.currentPosition == .back ? .front : .back
            guard let device = Self.camera(at: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: device) else { return }

            self.session.beginConfiguration()
            if let oldInput = self.videoInput {
                self.session.removeInput(oldInput)
            }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoInput = newInput
                self.currentPosition = newPosition
            } else if let oldInput = self.videoInput {
                self.session.addInput(oldInput)
            }
            if let connection = self.videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            self.enableFaceDetection()
            self.session.commitConfiguration()

            let position = self.currentPosition
            DispatchQueue.main.async {
                self.position = position
                self.subjectRect = nil
                self.subjectKind = nil
            }
        }
    }

    /// Lets the user tap to focus/expose on a point of the preview.
    func focus(at layerPoint: CGPoint) {
        guard let previewLayer else { return }
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
        sessionQueue.async {
            guard let device = self.videoInput?.device, (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
        }
    }

    func capturePhoto() {
        guard status == .running, !isCapturing else { return }
        isCapturing = true

        sessionQueue.async {
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()
            }
            settings.photoQualityPrioritization = .balanced

            if let connection = self.photoOutput.connection(with: .video) {
                Self.setPortrait(connection)
            }

            let delegate = PhotoCaptureDelegate { [weak self] data in
                self?.handleCapturedPhoto(data, id: settings.uniqueID)
            }
            self.photoDelegates[settings.uniqueID] = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private static func setPortrait(_ connection: AVCaptureConnection) {
        if #available(iOS 17.0, *) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    private func handleCapturedPhoto(_ data: Data?, id: Int64) {
        sessionQueue.async { self.photoDelegates[id] = nil }

        guard let data else {
            DispatchQueue.main.async {
                self.isCapturing = false
                self.toastMessage = "Không chụp được ảnh"
            }
            return
        }

        let image = UIImage(data: data)
        DispatchQueue.main.async {
            self.isCapturing = false
            self.lastPhoto = image
        }

        PhotoLibrary.save(data) { saved in
            DispatchQueue.main.async {
                self.toastMessage = saved ? "Đã lưu vào thư viện Ảnh" : "Chưa có quyền lưu ảnh"
            }
        }
    }

    // MARK: - Subject tracking

    /// Publishes a subject rect given in metadata-output coordinates
    /// (normalized, top-left origin, sensor orientation). Called on the analysis queue.
    private func report(_ deviceRect: CGRect?, kind: SubjectKind?) {
        if deviceRect == nil {
            consecutiveMisses += 1
            guard consecutiveMisses >= Self.missesBeforeClearing else { return }
        } else {
            consecutiveMisses = 0
        }

        DispatchQueue.main.async {
            guard let deviceRect, let kind, let layer = self.previewLayer else {
                self.subjectRect = nil
                self.subjectKind = nil
                return
            }
            let rect = layer.layerRectConverted(fromMetadataOutputRect: deviceRect)
            if let previous = self.subjectRect, self.subjectKind == kind {
                // Smooth out detection jitter.
                self.subjectRect = previous.interpolated(to: rect, amount: 0.35)
            } else {
                self.subjectRect = rect
            }
            self.subjectKind = kind
        }
    }
}

// MARK: - Face detection

extension CameraService: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        let faces = metadataObjects.compactMap { $0 as? AVMetadataFaceObject }
        guard let largest = faces.max(by: { $0.bounds.area < $1.bounds.area }) else { return }
        lastFaceSeen = Date()
        report(largest.bounds, kind: .face)
    }
}

// MARK: - Saliency detection

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date()
        // Faces take priority; only look for other subjects when no face is visible.
        guard now.timeIntervalSince(lastFaceSeen) > Self.faceHoldTime,
              now.timeIntervalSince(lastSaliencyRun) > Self.saliencyInterval,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastSaliencyRun = now

        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([request])

        let objects = request.results?.first?.salientObjects ?? []
        guard let best = objects.max(by: { $0.boundingBox.area < $1.boundingBox.area }),
              best.boundingBox.area < 0.6 else {
            // Nothing stands out (or the whole frame is "salient"): no subject.
            report(nil, kind: nil)
            return
        }

        // Vision uses a bottom-left origin; metadata coordinates use top-left.
        let box = best.boundingBox
        let deviceRect = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        report(deviceRect, kind: .salientObject)
    }
}

// MARK: - Helpers

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Data?) -> Void

    init(completion: @escaping (Data?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        completion(error == nil ? photo.fileDataRepresentation() : nil)
    }
}

private enum PhotoLibrary {
    static func save(_ data: Data, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                completion(false)
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }, completionHandler: { success, _ in
                completion(success)
            })
        }
    }
}

extension CGRect {
    var area: CGFloat { width * height }

    var center: CGPoint { CGPoint(x: midX, y: midY) }

    func interpolated(to other: CGRect, amount t: CGFloat) -> CGRect {
        CGRect(x: minX + (other.minX - minX) * t,
               y: minY + (other.minY - minY) * t,
               width: width + (other.width - width) * t,
               height: height + (other.height - height) * t)
    }
}
