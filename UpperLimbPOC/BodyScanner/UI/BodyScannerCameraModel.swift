@preconcurrency import AVFoundation
import Combine
import Foundation

struct BodyScannerLiveJoint: Equatable, Sendable, Identifiable {
    var id: String { "\(laterality.rawValue)-\(joint.rawValue)" }

    let laterality: UpperLimbLaterality
    let joint: UpperLimbJointName
    let normalizedX: Double
    let normalizedY: Double
    let confidence: Double
    let isLive: Bool
}

// Capture/session/model state is serialized by captureQueue. Published UI and
// qualification state crosses to the main queue only as immutable Sendable
// values. AVCapture invokes this NSObject delegate outside Swift actors.
final class BodyScannerCameraModel: NSObject, ObservableObject, @unchecked Sendable {
    let session = AVCaptureSession()

    @Published private(set) var status = "Camera not started"
    @Published private(set) var phase: BodyScannerTrackingPhase = .searching
    @Published private(set) var joints: [BodyScannerLiveJoint] = []
    @Published private(set) var frameSize = BodyScannerFrameSize.waiting
    @Published private(set) var captureRotationAngleDegrees: CGFloat = 0
    @Published private(set) var previewRotationAngleDegrees: CGFloat?
    @Published private(set) var diagnostics = "Waiting for oriented camera frame"
    @Published private(set) var counts = BodyScannerVisibleCounts(
        bodyQualified: 0,
        bodyAvailable: 0,
        leftHandFiniteInFrame: 0,
        rightHandFiniteInFrame: 0,
        leftHandConfidence: nil,
        rightHandConfidence: nil
    )
    @Published private(set) var frozenObservations: [UpperLimbJointObservation]?

    private let captureQueue = DispatchQueue(
        label: "com.marcel.upperlimbpoc.body-scanner.capture",
        qos: .userInitiated
    )
    private let videoOutput = AVCaptureVideoDataOutput()
    private var scanner: OCVBodyScanner?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var isConfigured = false
    private var qualificationStartedAt: TimeInterval?
    private var qualifiedFrameCount = 0
    private var qualificationGeneration: UInt64 = 0
    private var latestObservations: [UpperLimbJointObservation] = []
    private var lastDiagnosticSecond: Int?

    func start() {
        frozenObservations = nil
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startConfiguredSession()
        case .notDetermined:
            status = "Requesting camera permission…"
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.startConfiguredSession()
                    } else {
                        self.failOnMain("Camera permission denied")
                    }
                }
            }
        case .denied, .restricted:
            failOnMain("Camera permission denied — enable it in Settings")
        @unknown default:
            failOnMain("Camera permission state is unavailable")
        }
    }

    func stop() {
        captureQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func freeze() {
        guard case .qualified(let generation) = phase,
              generation == qualificationGeneration,
              !latestObservations.isEmpty else { return }
        frozenObservations = latestObservations
        phase = .frozen(generation: generation)
        stop()
    }

    func reset() {
        frozenObservations = nil
        joints = []
        resetQualificationOnMain()
        start()
    }

    private func startConfiguredSession() {
        status = "Loading pinned OpenCV models…"
        captureQueue.async { [weak self] in
            guard let self else { return }
            do {
                if !self.isConfigured {
                    try self.configureSessionAndModels()
                    self.isConfigured = true
                }
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                self.publishStatus("OpenCV upper-limb tracking")
            } catch {
                self.publishFailure(error.localizedDescription)
            }
        }
    }

    private func configureSessionAndModels() throws {
        let manifest = BodyScannerModelManifest.openCVZooPinned
        let resources = try Dictionary(
            uniqueKeysWithValues: manifest.artifacts.map { artifact in
                guard let url = Bundle.main.url(
                    forResource: artifact.fileName,
                    withExtension: nil
                ) else {
                    throw BodyScannerCameraError.missingModel(artifact.fileName)
                }
                return (
                    artifact.fileName,
                    try BodyScannerResourceInspector.fingerprint(of: url)
                )
            }
        )
        let validation = manifest.validate(resources: resources)
        guard validation.isReady else {
            throw BodyScannerCameraError.modelIntegrity
        }
        guard let personURL = Bundle.main.url(
            forResource: "person_detection_mediapipe_2023mar.onnx",
            withExtension: nil
        ), let poseURL = Bundle.main.url(
            forResource: "pose_estimation_mediapipe_2023mar.onnx",
            withExtension: nil
        ) else {
            throw BodyScannerCameraError.modelIntegrity
        }

        let scanner = OCVBodyScanner(
            verifiedModelPaths: OCVBodyScannerModelPaths(
                personDetectorPath: personURL.path,
                poseEstimatorPath: poseURL.path
            )
        )
        try scanner.loadModels()
        self.scanner = scanner

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw BodyScannerCameraError.noRearCamera
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw BodyScannerCameraError.captureConfiguration
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
        guard session.canAddOutput(videoOutput) else {
            throw BodyScannerCameraError.captureConfiguration
        }
        session.addOutput(videoOutput)
        if let connection = videoOutput.connection(with: .video) {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
            let coordinator = AVCaptureDevice.RotationCoordinator(
                device: device,
                previewLayer: nil
            )
            rotationCoordinator = coordinator
            applyCaptureRotation(
                coordinator.videoRotationAngleForHorizonLevelCapture,
                to: connection
            )
            rotationObservation = coordinator.observe(
                \.videoRotationAngleForHorizonLevelCapture,
                options: [.new]
            ) { [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelCapture
                self?.captureQueue.async { [weak self] in
                    guard let self,
                          let connection = self.videoOutput.connection(with: .video) else {
                        return
                    }
                    self.applyCaptureRotation(angle, to: connection)
                }
            }
        }
    }

    private func applyCaptureRotation(
        _ angle: CGFloat,
        to connection: AVCaptureConnection
    ) {
        guard connection.isVideoRotationAngleSupported(angle) else {
            publishFailure("Camera rotation \(Int(angle.rounded()))° is unsupported")
            return
        }
        connection.videoRotationAngle = angle
        DispatchQueue.main.async { [weak self] in
            self?.captureRotationAngleDegrees = angle
        }
    }

    func recordPreviewRotationAngle(_ angle: CGFloat) {
        precondition(Thread.isMainThread)
        previewRotationAngleDegrees = angle
    }

    func recordUnsupportedPreviewRotation(_ angle: CGFloat) {
        precondition(Thread.isMainThread)
        failOnMain("Preview rotation \(Int(angle.rounded()))° is unsupported")
        stop()
    }

    private func publishStatus(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.status = text
        }
    }

    private func publishFailure(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.failOnMain(text)
        }
    }

    private func failOnMain(_ text: String) {
        status = text
        phase = .failed
        joints = []
        latestObservations = []
    }

    private func resetQualificationOnMain() {
        qualificationGeneration &+= 1
        qualificationStartedAt = nil
        qualifiedFrameCount = 0
        phase = .searching
        latestObservations = []
    }
}

extension BodyScannerCameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let scanner else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            publishFailure("Camera pixel buffer is unavailable")
            return
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let appliedRotationAngle = connection.videoRotationAngle
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixels = Data(bytes: baseAddress, count: bytesPerRow * height)
        let result: OCVUpperLimbPoseResult
        do {
            result = try scanner.inferBGRA8(
                pixels,
                width: width,
                height: height,
                bytesPerRow: bytesPerRow
            )
        } catch {
            let message = error.localizedDescription
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.status = message
                self.joints = []
                self.counts = BodyScannerVisibleCounts(
                    bodyQualified: 0,
                    bodyAvailable: 0,
                    leftHandFiniteInFrame: 0,
                    rightHandFiniteInFrame: 0,
                    leftHandConfidence: nil,
                    rightHandConfidence: nil
                )
                self.resetQualificationOnMain()
            }
            return
        }

        let raw = result.landmarks.map {
            BodyScannerPoseLandmark(
                index: $0.mediaPipeIndex,
                imageX: $0.imageX,
                imageY: $0.imageY,
                modelRelativeZ: $0.modelRelativeZ,
                visibility: $0.visibility,
                presence: $0.presence
            )
        }
        let observations = BodyScannerUpperLimbPoseMapper.map(
            landmarks: raw,
            imageWidth: Double(width),
            imageHeight: Double(height),
            minimumConfidence: 0.5
        )
        var liveJoints: [BodyScannerLiveJoint] = []
        var liveCount = 0
        for observation in observations {
            let isLive = observation.validity == UpperLimbTrackingValidity.live
                && observation.state == UpperLimbObservationState.observed
            if isLive { liveCount += 1 }
            liveJoints.append(
                BodyScannerLiveJoint(
                    laterality: observation.laterality,
                    joint: observation.joint,
                    normalizedX: observation.position.x / Double(width),
                    normalizedY: observation.position.y / Double(height),
                    confidence: observation.confidence ?? 0,
                    isLive: isLive
                )
            )
        }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let personScore = result.personScore
        let poseCropCenterX = result.poseCropCenterX
        let poseCropCenterY = result.poseCropCenterY
        let poseCropSize = result.poseCropSize
        let publishedJoints = liveJoints
        let publishedCount = liveCount

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.status = "OpenCV 4.13 • person \(Int((personScore * 100).rounded()))%"
            self.frameSize = BodyScannerFrameSize(
                width: Double(width),
                height: Double(height)
            )
            self.captureRotationAngleDegrees = appliedRotationAngle
            let diagnosticSecond = Int(timestamp.rounded(.down))
            if self.lastDiagnosticSecond != diagnosticSecond {
                self.lastDiagnosticSecond = diagnosticSecond
                let previewAngle = self.previewRotationAngleDegrees.map {
                    "\(Int($0.rounded()))°"
                } ?? "—"
                self.diagnostics = "frame \(width)×\(height) • capture \(Int(appliedRotationAngle.rounded()))° • preview \(previewAngle) • pose crop \(Int(poseCropSize.rounded())) px @ \(Int(poseCropCenterX.rounded())),\(Int(poseCropCenterY.rounded()))"
                print("[BodyScanner] \(self.diagnostics)")
            }
            self.joints = publishedJoints
            self.latestObservations = observations
            self.counts = BodyScannerVisibleCounts(
                bodyQualified: publishedCount,
                bodyAvailable: observations.count,
                leftHandFiniteInFrame: 0,
                rightHandFiniteInFrame: 0,
                leftHandConfidence: nil,
                rightHandConfidence: nil
            )
            self.consumeQualification(liveCount: publishedCount, timestamp: timestamp)
        }
    }

    private func consumeQualification(
        liveCount: Int,
        timestamp: TimeInterval
    ) {
        guard liveCount == 6 else {
            resetQualificationOnMain()
            phase = liveCount > 0 ? .partial : .searching
            return
        }

        if qualificationStartedAt == nil {
            qualificationStartedAt = timestamp
            qualifiedFrameCount = 0
            qualificationGeneration &+= 1
        }
        qualifiedFrameCount += 1
        let elapsed = timestamp - (qualificationStartedAt ?? timestamp)
        if qualifiedFrameCount >= 10, elapsed >= 1.0 {
            phase = .qualified(generation: qualificationGeneration)
        } else {
            phase = .stabilizing
        }
    }
}

private enum BodyScannerCameraError: LocalizedError {
    case missingModel(String)
    case modelIntegrity
    case modelLoad
    case noRearCamera
    case captureConfiguration

    var errorDescription: String? {
        switch self {
        case .missingModel(let name): "Missing pinned model: \(name)"
        case .modelIntegrity: "Pinned model integrity check failed"
        case .modelLoad: "OpenCV could not load the pinned models"
        case .noRearCamera: "Rear 1× camera is unavailable"
        case .captureConfiguration: "Camera output could not be configured"
        }
    }
}
