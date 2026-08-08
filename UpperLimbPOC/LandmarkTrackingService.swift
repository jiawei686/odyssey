import ARKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import simd

@MainActor
final class LandmarkTrackingService: ObservableObject {
    struct ForearmFit {
        let elbowPosition: SIMD3<Float>
        let wristPosition: SIMD3<Float>
        let rotation: simd_quatf
        let scale: Float
    }

    enum Phase: Equatable {
        case idle
        case simulatorUnavailable
        case unsupported
        case authorizationDenied
        case searching
        case partial
        case tracking
        case invalidDistance
        case failed(String)

        var message: String {
            switch self {
            case .idle: "Tracking is idle"
            case .simulatorUnavailable: "Marker tracking requires a physical Apple Vision Pro"
            case .unsupported: "Image tracking is unavailable on this device"
            case .authorizationDenied: "World-sensing permission was denied"
            case .searching: "Show both ELBOW and WRIST markers"
            case .partial: "One marker found — show both markers"
            case .tracking: "Both markers detected — live alignment"
            case .invalidDistance: "Markers are outside the expected forearm distance"
            case .failed(let reason): "Tracking failed: \(reason)"
            }
        }
    }

    enum HandPhase: Equatable {
        case idle
        case simulatorUnavailable
        case unsupported
        case authorizationDenied
        case running
        case failed(String)

        var message: String {
            switch self {
            case .idle: "Hand tracking is idle"
            case .simulatorUnavailable: "Hand joints require a physical Apple Vision Pro"
            case .unsupported: "Hand tracking is unavailable on this device"
            case .authorizationDenied: "Hands Tracking permission was denied"
            case .running: "Hand joint stream is running"
            case .failed(let reason): "Hand tracking failed: \(reason)"
            }
        }

        var canRetry: Bool {
            switch self {
            case .authorizationDenied, .failed:
                true
            default:
                false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var fit: ForearmFit?
    @Published private(set) var isTracking = false
    @Published private(set) var isAvailableOnDevice = false
    @Published private(set) var isHandTracking = false
    @Published private(set) var handPhase: HandPhase = .idle
    @Published private(set) var handTrackingGeneration = 0
    @Published private(set) var leftHandJointTransforms: [HandSkeleton.JointName: simd_float4x4] = [:]
    @Published private(set) var rightHandJointTransforms: [HandSkeleton.JointName: simd_float4x4] = [:]
    @Published private(set) var isProbeRecording = false
    @Published private(set) var probeReport: JointProbeReport?
    @Published private(set) var probeSecondsRemaining = 30
    @Published private(set) var probeSelectedHand: JointProbeHand = .left
    @Published private(set) var probeBoneVisible = false
    @Published private(set) var probeSectionFraction = 0.55
    @Published private(set) var leftHandAnchorUpdateCount = 0
    @Published private(set) var rightHandAnchorUpdateCount = 0
    @Published private(set) var leftForearmResolution = AVPForearmOverlayResolution(
        state: .searching,
        trackedPointCount: 0,
        detail: "Show the selected forearm and hand",
        pose: nil
    )
    @Published private(set) var rightForearmResolution = AVPForearmOverlayResolution(
        state: .searching,
        trackedPointCount: 0,
        detail: "Show the selected forearm and hand",
        pose: nil
    )

    private let session = ARKitSession()
    private var provider: ImageTrackingProvider?
    private var handProvider: HandTrackingProvider?
    private var updateTask: Task<Void, Never>?
    private var handUpdateTask: Task<Void, Never>?
    private var probeTimerTask: Task<Void, Never>?
    private var elbowTransform: simd_float4x4?
    private var wristTransform: simd_float4x4?
    private var leftIndexFingerWasTracked = false
    private var rightIndexFingerWasTracked = false
    private var probeAccumulator = JointProbeAccumulator(
        expectedJointCount: HandSkeleton.JointName.allCases.count,
        expectedCriticalJointCount: 3
    )
    private var leftForearmTracker = AVPForearmOverlayTracker()
    private var rightForearmTracker = AVPForearmOverlayTracker()

    private let referenceForearmLength: Float = 0.2625
    private let smoothingFactor: Float = 0.24
    private let requiredIndexJointNames: [HandSkeleton.JointName] = [
        .indexFingerKnuckle,
        .indexFingerIntermediateBase,
        .indexFingerIntermediateTip
    ]
    private let probeCriticalJointNames: [HandSkeleton.JointName] = [
        .wrist,
        .forearmWrist,
        .forearmArm
    ]

    func start() async {
        guard updateTask == nil, handUpdateTask == nil else { return }

#if targetEnvironment(simulator)
        phase = .simulatorUnavailable
        isAvailableOnDevice = false
        handPhase = .simulatorUnavailable
        return
#else
        guard ImageTrackingProvider.isSupported else {
            phase = .unsupported
            isAvailableOnDevice = false
            handPhase = HandTrackingProvider.isSupported
                ? .failed("image-landmark tracking is required for this overlay")
                : .unsupported
            return
        }

        do {
            let referenceImages = try loadReferenceImages()
            var authorizationTypes = ImageTrackingProvider.requiredAuthorizations
            if HandTrackingProvider.isSupported {
                authorizationTypes.append(
                    contentsOf: HandTrackingProvider.requiredAuthorizations
                )
            }
            let authorization = await session.requestAuthorization(for: authorizationTypes)

            let imageAuthorizationDenied = ImageTrackingProvider
                .requiredAuthorizations
                .contains { authorization[$0] == .denied }
            guard !imageAuthorizationDenied else {
                phase = .authorizationDenied
                isAvailableOnDevice = false
                handPhase = .failed(
                    "world-sensing permission is required for overlay alignment"
                )
                return
            }

            let handAuthorizationGranted = HandTrackingProvider.isSupported
                && !HandTrackingProvider.requiredAuthorizations.contains {
                    authorization[$0] == .denied
                }

            let provider = ImageTrackingProvider(referenceImages: referenceImages)
            self.provider = provider
            let handProvider = handAuthorizationGranted
                ? HandTrackingProvider()
                : nil
            self.handProvider = handProvider
            if !HandTrackingProvider.isSupported {
                handPhase = .unsupported
            } else if !handAuthorizationGranted {
                handPhase = .authorizationDenied
            }
            var providers: [any DataProvider] = [provider]
            if let handProvider {
                providers.append(handProvider)
            }
            try await session.run(providers)

            phase = .searching
            isAvailableOnDevice = true
            if handProvider != nil {
                handTrackingGeneration += 1
                handPhase = .running
            }

            updateTask = Task { [weak self] in
                for await update in provider.anchorUpdates {
                    guard !Task.isCancelled else { break }
                    self?.consume(update.anchor)
                }
                guard !Task.isCancelled else { return }
                self?.handleProviderStreamEnded()
            }
            if let handProvider {
                startHandAnchorUpdates(from: handProvider)
            }
        } catch {
            phase = .failed(error.localizedDescription)
            isAvailableOnDevice = false
            handPhase = .failed(error.localizedDescription)
        }
#endif
    }

    func startHandJointProbe() async {
        guard updateTask == nil, handUpdateTask == nil else { return }

#if targetEnvironment(simulator)
        handPhase = .simulatorUnavailable
        publishForearmFailure("Physical Apple Vision Pro required")
        return
#else
        guard HandTrackingProvider.isSupported else {
            handPhase = .unsupported
            publishForearmFailure("HandTrackingProvider is unavailable")
            return
        }

        let authorization = await session.requestAuthorization(
            for: HandTrackingProvider.requiredAuthorizations
        )
        let authorizationDenied = HandTrackingProvider.requiredAuthorizations
            .contains { authorization[$0] == .denied }
        guard !authorizationDenied else {
            handPhase = .authorizationDenied
            publishForearmFailure("Hands Tracking permission was denied")
            return
        }

        do {
            let handProvider = HandTrackingProvider()
            self.handProvider = handProvider
            try await session.run([handProvider])
            handTrackingGeneration += 1
            handPhase = .running
            print("[UL-SELF-ARM] HandTrackingProvider session running")
            startHandAnchorUpdates(from: handProvider)
        } catch {
            handProvider = nil
            handPhase = .failed(error.localizedDescription)
            publishForearmFailure(error.localizedDescription)
        }
#endif
    }

    func selectProbeHand(_ hand: JointProbeHand) {
        probeSelectedHand = hand
    }

    func setProbeBoneVisible(_ isVisible: Bool) {
        probeBoneVisible = isVisible
    }

    func setProbeSectionFraction(_ fraction: Double) {
        probeSectionFraction = min(max(fraction, 0), 1)
        let timestamp = ProcessInfo.processInfo.systemUptime
        updateForearmResolution(
            isLeft: true,
            transforms: leftHandJointTransforms,
            timestamp: timestamp
        )
        updateForearmResolution(
            isLeft: false,
            transforms: rightHandJointTransforms,
            timestamp: timestamp
        )
    }

    func beginProbeMeasurement(durationSeconds: Int = 30) {
        guard handPhase == .running else { return }
        let durationSeconds = max(1, durationSeconds)
        probeTimerTask?.cancel()
        probeAccumulator = JointProbeAccumulator(
            expectedJointCount: HandSkeleton.JointName.allCases.count,
            expectedCriticalJointCount: probeCriticalJointNames.count
        )
        probeAccumulator.start(at: ProcessInfo.processInfo.systemUptime)
        probeReport = nil
        probeSecondsRemaining = durationSeconds
        isProbeRecording = true

        probeTimerTask = Task { [weak self] in
            for remaining in stride(
                from: durationSeconds - 1,
                through: 0,
                by: -1
            ) {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.probeSecondsRemaining = remaining
            }
            self?.finishProbeMeasurement()
        }
    }

    func finishProbeMeasurement() {
        guard isProbeRecording else { return }
        isProbeRecording = false
        probeTimerTask?.cancel()
        probeTimerTask = nil
        probeReport = probeAccumulator.finish(
            at: ProcessInfo.processInfo.systemUptime
        )
    }

    func resetProbeMeasurement() {
        probeTimerTask?.cancel()
        probeTimerTask = nil
        isProbeRecording = false
        probeSecondsRemaining = 30
        probeReport = nil
        probeAccumulator = JointProbeAccumulator(
            expectedJointCount: HandSkeleton.JointName.allCases.count,
            expectedCriticalJointCount: probeCriticalJointNames.count
        )
    }

    func stop() {
        if isProbeRecording {
            finishProbeMeasurement()
        } else {
            probeTimerTask?.cancel()
            probeTimerTask = nil
        }
        updateTask?.cancel()
        updateTask = nil
        handUpdateTask?.cancel()
        handUpdateTask = nil
        session.stop()
        provider = nil
        handProvider = nil
        elbowTransform = nil
        wristTransform = nil
        fit = nil
        isTracking = false
        isAvailableOnDevice = false
        isHandTracking = false
        handPhase = .idle
        probeBoneVisible = false
        leftHandJointTransforms = [:]
        rightHandJointTransforms = [:]
        leftHandAnchorUpdateCount = 0
        rightHandAnchorUpdateCount = 0
        leftForearmTracker.reset()
        rightForearmTracker.reset()
        leftForearmResolution = AVPForearmOverlayPoseResolver.resolve(
            forearmArm: nil,
            forearmWrist: nil,
            wrist: nil
        )
        rightForearmResolution = leftForearmResolution
        leftIndexFingerWasTracked = false
        rightIndexFingerWasTracked = false
        phase = .idle
    }

    func retry() async {
        stop()
        await start()
    }

    private func handleProviderStreamEnded() {
        updateTask = nil
        provider = nil
        isTracking = false
        isAvailableOnDevice = false
        phase = .failed("tracking session ended — retry tracking")
    }

    private func handleHandProviderStreamEnded() {
        handUpdateTask = nil
        handProvider = nil
        isHandTracking = false
        leftHandJointTransforms = [:]
        rightHandJointTransforms = [:]
        handPhase = .failed("hand-tracking stream ended — retry tracking")
        publishForearmFailure("Hand-tracking stream ended")
    }

    private func startHandAnchorUpdates(from provider: HandTrackingProvider) {
        handUpdateTask = Task { [weak self] in
            for await update in provider.anchorUpdates {
                guard !Task.isCancelled else { break }
                self?.consume(update.anchor)
            }
            guard !Task.isCancelled else { return }
            self?.handleHandProviderStreamEnded()
        }
    }

    private func consume(_ anchor: ImageAnchor) {
        guard let name = anchor.referenceImage.name?.lowercased() else { return }
        let transform = anchor.isTracked ? anchor.originFromAnchorTransform : nil

        if name.contains("elbow") {
            elbowTransform = transform
        } else if name.contains("wrist") {
            wristTransform = transform
        }

        updateFit()
    }

    private func consume(_ anchor: HandAnchor) {
        guard anchor.isTracked, let skeleton = anchor.handSkeleton else {
            if anchor.chirality == .left {
                leftHandJointTransforms = [:]
                updateForearmResolution(
                    isLeft: true,
                    transforms: [:],
                    timestamp: ProcessInfo.processInfo.systemUptime
                )
            } else {
                rightHandJointTransforms = [:]
                updateForearmResolution(
                    isLeft: false,
                    transforms: [:],
                    timestamp: ProcessInfo.processInfo.systemUptime
                )
            }
            recordHandAnchorDiagnostic(anchor: anchor, transforms: [:])
            recordProbeSample(anchor: anchor, transforms: [:])
            updateHandTrackingState()
            return
        }

        var transforms: [HandSkeleton.JointName: simd_float4x4] = [:]
        for jointName in HandSkeleton.JointName.allCases {
            let joint = skeleton.joint(jointName)
            guard joint.isTracked else { continue }
            transforms[jointName] = anchor.originFromAnchorTransform
                * joint.anchorFromJointTransform
        }

        if anchor.chirality == .left {
            leftHandJointTransforms = transforms
            updateForearmResolution(
                isLeft: true,
                transforms: transforms,
                timestamp: ProcessInfo.processInfo.systemUptime
            )
        } else {
            rightHandJointTransforms = transforms
            updateForearmResolution(
                isLeft: false,
                transforms: transforms,
                timestamp: ProcessInfo.processInfo.systemUptime
            )
        }
        recordHandAnchorDiagnostic(anchor: anchor, transforms: transforms)
        recordProbeSample(anchor: anchor, transforms: transforms)
        updateHandTrackingState()
    }

    private func recordProbeSample(
        anchor: HandAnchor,
        transforms: [HandSkeleton.JointName: simd_float4x4]
    ) {
        guard isProbeRecording else { return }
        let hand: JointProbeHand = anchor.chirality == .left ? .left : .right
        let trackedCriticalJointCount = probeCriticalJointNames.filter {
            transforms[$0] != nil
        }.count
        var trackedCriticalSignals: Set<JointProbeCriticalSignal> = []
        if transforms[.forearmArm] != nil {
            trackedCriticalSignals.insert(.forearmArm)
        }
        if transforms[.forearmWrist] != nil {
            trackedCriticalSignals.insert(.forearmWrist)
        }
        if transforms[.wrist] != nil {
            trackedCriticalSignals.insert(.wrist)
        }
        probeAccumulator.record(
            timestamp: ProcessInfo.processInfo.systemUptime,
            hand: hand,
            trackedJointCount: transforms.count,
            trackedCriticalJointCount: trackedCriticalJointCount,
            trackedCriticalSignals: trackedCriticalSignals
        )
    }

    private func recordHandAnchorDiagnostic(
        anchor: HandAnchor,
        transforms: [HandSkeleton.JointName: simd_float4x4]
    ) {
        let updateCount: Int
        if anchor.chirality == .left {
            leftHandAnchorUpdateCount += 1
            updateCount = leftHandAnchorUpdateCount
        } else {
            rightHandAnchorUpdateCount += 1
            updateCount = rightHandAnchorUpdateCount
        }
        guard updateCount == 1 || updateCount.isMultiple(of: 60) else { return }
        let side = anchor.chirality == .left ? "left" : "right"
        print(
            "[UL-SELF-ARM] \(side) update=\(updateCount) "
                + "anchorTracked=\(anchor.isTracked) joints=\(transforms.count) "
                + "forearmArm=\(transforms[.forearmArm] != nil) "
                + "forearmWrist=\(transforms[.forearmWrist] != nil) "
                + "wrist=\(transforms[.wrist] != nil)"
        )
    }

    private func updateForearmResolution(
        isLeft: Bool,
        transforms: [HandSkeleton.JointName: simd_float4x4],
        timestamp: Double
    ) {
        let forearmArm = transforms[.forearmArm].map(translation(of:))
        let forearmWrist = transforms[.forearmWrist].map(translation(of:))
        let wrist = transforms[.wrist].map(translation(of:))
        if isLeft {
            leftForearmResolution = leftForearmTracker.update(
                forearmArm: forearmArm,
                forearmWrist: forearmWrist,
                wrist: wrist,
                sectionFraction: Float(probeSectionFraction),
                timestamp: timestamp
            )
        } else {
            rightForearmResolution = rightForearmTracker.update(
                forearmArm: forearmArm,
                forearmWrist: forearmWrist,
                wrist: wrist,
                sectionFraction: Float(probeSectionFraction),
                timestamp: timestamp
            )
        }
        selectReadyProbeHandIfNeeded()
    }

    private func selectReadyProbeHandIfNeeded() {
        guard !probeBoneVisible else { return }
        let selectedResolution = probeSelectedHand == .left
            ? leftForearmResolution
            : rightForearmResolution
        guard !isReady(selectedResolution) else { return }
        let otherHand: JointProbeHand = probeSelectedHand == .left ? .right : .left
        let otherResolution = otherHand == .left
            ? leftForearmResolution
            : rightForearmResolution
        if isReady(otherResolution) {
            probeSelectedHand = otherHand
        }
    }

    private func isReady(_ resolution: AVPForearmOverlayResolution) -> Bool {
        resolution.state == .live || resolution.state == .stale
    }

    private func publishForearmFailure(_ detail: String) {
        leftForearmResolution = leftForearmTracker.fail(detail: detail)
        rightForearmResolution = rightForearmTracker.fail(detail: detail)
    }

    func handJointTransforms(isLeft: Bool) -> [HandSkeleton.JointName: simd_float4x4] {
        isLeft ? leftHandJointTransforms : rightHandJointTransforms
    }

    func hasTrackedIndexFinger(isLeft: Bool) -> Bool {
        let transforms = handJointTransforms(isLeft: isLeft)
        return requiredIndexJointNames.allSatisfy { transforms[$0] != nil }
    }

    func hasPreviouslyTrackedIndexFinger(isLeft: Bool) -> Bool {
        isLeft ? leftIndexFingerWasTracked : rightIndexFingerWasTracked
    }

    private func updateHandTrackingState() {
        let leftIsTracked = hasTrackedIndexFinger(isLeft: true)
        let rightIsTracked = hasTrackedIndexFinger(isLeft: false)
        leftIndexFingerWasTracked = leftIndexFingerWasTracked || leftIsTracked
        rightIndexFingerWasTracked = rightIndexFingerWasTracked || rightIsTracked
        isHandTracking = leftIsTracked || rightIsTracked
    }

    private func updateFit() {
        guard let elbowTransform, let wristTransform else {
            isTracking = false
            phase = elbowTransform != nil || wristTransform != nil ? .partial : .searching
            return
        }

        let elbow = translation(of: elbowTransform)
        let wrist = translation(of: wristTransform)
        let offset = wrist - elbow
        let distance = simd_length(offset)

        guard (0.12...0.45).contains(distance) else {
            isTracking = false
            phase = .invalidDistance
            return
        }

        let direction = simd_normalize(offset)
        let rotation = fittedRotation(
            direction: direction,
            elbowTransform: elbowTransform,
            wristTransform: wristTransform
        )
        let rawFit = ForearmFit(
            elbowPosition: elbow,
            wristPosition: wrist,
            rotation: rotation,
            scale: distance / referenceForearmLength
        )

        if let previous = fit {
            fit = ForearmFit(
                elbowPosition: simd_mix(
                    previous.elbowPosition,
                    rawFit.elbowPosition,
                    SIMD3<Float>(repeating: smoothingFactor)
                ),
                wristPosition: simd_mix(
                    previous.wristPosition,
                    rawFit.wristPosition,
                    SIMD3<Float>(repeating: smoothingFactor)
                ),
                rotation: simd_slerp(previous.rotation, rawFit.rotation, smoothingFactor),
                scale: previous.scale + ((rawFit.scale - previous.scale) * smoothingFactor)
            )
        } else {
            fit = rawFit
        }

        isTracking = true
        phase = .tracking
    }

    private func translation(of transform: simd_float4x4) -> SIMD3<Float> {
        SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
    }

    private func fittedRotation(
        direction: SIMD3<Float>,
        elbowTransform: simd_float4x4,
        wristTransform: simd_float4x4
    ) -> simd_quatf {
        var elbowNormal = simd_normalize(SIMD3<Float>(
            elbowTransform.columns.2.x,
            elbowTransform.columns.2.y,
            elbowTransform.columns.2.z
        ))
        var wristNormal = simd_normalize(SIMD3<Float>(
            wristTransform.columns.2.x,
            wristTransform.columns.2.y,
            wristTransform.columns.2.z
        ))

        if simd_dot(elbowNormal, wristNormal) < 0 {
            wristNormal *= -1
        }

        var surfaceNormal = elbowNormal + wristNormal
        surfaceNormal -= direction * simd_dot(surfaceNormal, direction)

        if simd_length_squared(surfaceNormal) < 0.0001 {
            elbowNormal = abs(direction.y) < 0.9
                ? SIMD3<Float>(0, 1, 0)
                : SIMD3<Float>(1, 0, 0)
            surfaceNormal = elbowNormal - direction * simd_dot(elbowNormal, direction)
        }

        let worldY = simd_normalize(surfaceNormal)
        let worldZ = -direction
        let worldX = simd_normalize(simd_cross(worldY, worldZ))
        let correctedWorldY = simd_normalize(simd_cross(worldZ, worldX))
        let basis = simd_float3x3(columns: (worldX, correctedWorldY, worldZ))
        return simd_quatf(basis)
    }

    private func loadReferenceImages() throws -> [ReferenceImage] {
        try ["elbow-marker", "wrist-marker"].map { resourceName in
            guard let url = Bundle.main.url(
                forResource: resourceName,
                withExtension: "png"
            ), let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw MarkerError.missingResource(resourceName)
            }

            var reference = ReferenceImage(
                cgimage: image,
                physicalSize: CGSize(width: 0.08, height: 0.08)
            )
            reference.name = resourceName
            return reference
        }
    }
}

private enum MarkerError: LocalizedError {
    case missingResource(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            "Missing marker resource: \(name).png"
        }
    }
}
