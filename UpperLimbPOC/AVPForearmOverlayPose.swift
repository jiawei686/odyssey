import Foundation
import simd

enum AVPForearmOverlayState: String, Equatable, Sendable {
    case searching
    case partial
    case live
    case stale
    case failed

    var label: String {
        switch self {
        case .searching: "SEARCHING"
        case .partial: "PARTIAL"
        case .live: "AXIS ONLY - LIVE"
        case .stale: "AXIS ONLY - STALE"
        case .failed: "FAILED"
        }
    }
}

struct AVPForearmOverlayPose: Sendable {
    let proximalPoint: SIMD3<Float>
    let distalPoint: SIMD3<Float>
    let center: SIMD3<Float>
    let sectionCenter: SIMD3<Float>
    let direction: SIMD3<Float>
    let rotation: simd_quatf
    let length: Float
    let overlayRadius: Float
    let sectionRadius: Float
    let sectionOffsetFromCenter: Float
    let rollResolved: Bool
}

struct AVPBoneOverlayTransform: Sendable {
    let scale: SIMD3<Float>
    let rotation: simd_quatf
    let translation: SIMD3<Float>

    func transformPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        rotation.act(point * scale) + translation
    }
}

struct AVPTrackedBoneSegmentTransform: Sendable {
    let center: SIMD3<Float>
    let rotation: simd_quatf
    let length: Float

    func transformPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        rotation.act(point) + center
    }
}

enum AVPTrackedBoneSegmentTransformResolver {
    static func resolve(
        start: SIMD3<Float>,
        end: SIMD3<Float>
    ) -> AVPTrackedBoneSegmentTransform? {
        guard isFinite(start), isFinite(end) else { return nil }
        let vector = end - start
        let length = simd_length(vector)
        guard length.isFinite, length >= 0.002, length <= 0.5 else {
            return nil
        }
        return AVPTrackedBoneSegmentTransform(
            center: (start + end) * 0.5,
            rotation: simd_quatf(
                from: SIMD3<Float>(0, 1, 0),
                to: vector / length
            ),
            length: length
        )
    }

    private static func isFinite(_ point: SIMD3<Float>) -> Bool {
        point.x.isFinite && point.y.isFinite && point.z.isFinite
    }
}

enum AVPBoneOverlayTransformResolver {
    static let referenceForearmLength: Float = 0.2625
    static let modelElbow = SIMD3<Float>(0, 0, 0.205)
    static let modelWrist = modelElbow
        + SIMD3<Float>(0, 0, -referenceForearmLength)

    static func resolve(
        pose: AVPForearmOverlayPose,
        isLeft: Bool
    ) -> AVPBoneOverlayTransform? {
        guard pose.length.isFinite, pose.length > 0,
              pose.proximalPoint.x.isFinite,
              pose.proximalPoint.y.isFinite,
              pose.proximalPoint.z.isFinite,
              pose.direction.x.isFinite,
              pose.direction.y.isFinite,
              pose.direction.z.isFinite else { return nil }

        let uniformScale = pose.length / referenceForearmLength
        let scale = isLeft
            ? SIMD3<Float>(-uniformScale, uniformScale, uniformScale)
            : SIMD3<Float>(repeating: uniformScale)
        let modelAxis = simd_normalize(modelWrist - modelElbow)
        let rotation = simd_quatf(from: modelAxis, to: pose.direction)
        let translation = pose.proximalPoint
            - rotation.act(modelElbow * scale)
        return AVPBoneOverlayTransform(
            scale: scale,
            rotation: rotation,
            translation: translation
        )
    }
}

struct AVPForearmOverlayResolution: Sendable {
    let state: AVPForearmOverlayState
    let trackedPointCount: Int
    let detail: String
    let pose: AVPForearmOverlayPose?
}

enum AVPForearmOverlayPoseResolver {
    static let sectionFraction: Float = 0.55
    private static let plausibleLengthRange: ClosedRange<Float> = 0.12...0.45
    private static let maximumWristPointSeparation: Float = 0.12

    static func resolve(
        forearmArm: SIMD3<Float>?,
        forearmWrist: SIMD3<Float>?,
        wrist: SIMD3<Float>?,
        sectionFraction: Float = sectionFraction
    ) -> AVPForearmOverlayResolution {
        let trackedPointCount = [forearmArm, forearmWrist, wrist]
            .compactMap { $0 }
            .count

        guard trackedPointCount > 0 else {
            return AVPForearmOverlayResolution(
                state: .searching,
                trackedPointCount: 0,
                detail: "Show the selected forearm and hand",
                pose: nil
            )
        }
        guard let forearmArm, let forearmWrist, let wrist else {
            return AVPForearmOverlayResolution(
                state: .partial,
                trackedPointCount: trackedPointCount,
                detail: "Need wrist, forearmWrist, and forearmArm",
                pose: nil
            )
        }
        guard [forearmArm, forearmWrist, wrist].allSatisfy(isFinite) else {
            return invalid(
                trackedPointCount: trackedPointCount,
                detail: "Provider returned non-finite joint geometry"
            )
        }

        let wristPointSeparation = simd_distance(forearmWrist, wrist)
        guard wristPointSeparation <= maximumWristPointSeparation else {
            return invalid(
                trackedPointCount: trackedPointCount,
                detail: "Provider wrist endpoints are inconsistent"
            )
        }

        let distalPoint = forearmWrist
        let forearmVector = distalPoint - forearmArm
        let length = simd_length(forearmVector)
        guard plausibleLengthRange.contains(length) else {
            return invalid(
                trackedPointCount: trackedPointCount,
                detail: "Provider forearm length is outside the POC gate"
            )
        }

        let direction = forearmVector / length
        let center = (forearmArm + distalPoint) * 0.5
        let clampedSectionFraction = min(max(sectionFraction, 0), 1)
        let sectionCenter = forearmArm
            + (direction * length * clampedSectionFraction)
        let overlayRadius = min(max(length * 0.12, 0.025), 0.045)
        let sectionRadius = overlayRadius * 1.35

        return AVPForearmOverlayResolution(
            state: .live,
            trackedPointCount: trackedPointCount,
            detail: "Generic AVP forearm axis is live",
            pose: AVPForearmOverlayPose(
                proximalPoint: forearmArm,
                distalPoint: distalPoint,
                center: center,
                sectionCenter: sectionCenter,
                direction: direction,
                rotation: simd_quatf(
                    from: SIMD3<Float>(0, 1, 0),
                    to: direction
                ),
                length: length,
                overlayRadius: overlayRadius,
                sectionRadius: sectionRadius,
                sectionOffsetFromCenter: (clampedSectionFraction - 0.5) * length,
                rollResolved: false
            )
        )
    }

    private static func invalid(
        trackedPointCount: Int,
        detail: String
    ) -> AVPForearmOverlayResolution {
        AVPForearmOverlayResolution(
            state: .failed,
            trackedPointCount: trackedPointCount,
            detail: detail,
            pose: nil
        )
    }

    private static func isFinite(_ point: SIMD3<Float>) -> Bool {
        point.x.isFinite && point.y.isFinite && point.z.isFinite
    }
}

struct AVPForearmOverlayTracker: Sendable {
    let staleWindowSeconds: Double
    private var lastLivePose: AVPForearmOverlayPose?
    private var lastLiveTimestamp: Double?

    init(staleWindowSeconds: Double = 0.4) {
        precondition(staleWindowSeconds > 0 && staleWindowSeconds <= 2)
        self.staleWindowSeconds = staleWindowSeconds
    }

    mutating func update(
        forearmArm: SIMD3<Float>?,
        forearmWrist: SIMD3<Float>?,
        wrist: SIMD3<Float>?,
        sectionFraction: Float = AVPForearmOverlayPoseResolver.sectionFraction,
        timestamp: Double
    ) -> AVPForearmOverlayResolution {
        let current = AVPForearmOverlayPoseResolver.resolve(
            forearmArm: forearmArm,
            forearmWrist: forearmWrist,
            wrist: wrist,
            sectionFraction: sectionFraction
        )
        if current.state == .live, let pose = current.pose {
            lastLivePose = pose
            lastLiveTimestamp = timestamp
            return current
        }
        if current.state == .failed {
            return fail(detail: current.detail)
        }
        if let lastLivePose, let lastLiveTimestamp,
           timestamp - lastLiveTimestamp <= staleWindowSeconds {
            return AVPForearmOverlayResolution(
                state: .stale,
                trackedPointCount: current.trackedPointCount,
                detail: "Tracking interrupted - showing a faded last pose",
                pose: lastLivePose
            )
        }
        if current.state == .searching, lastLiveTimestamp != nil {
            return fail(detail: "Forearm tracking expired")
        }
        return current
    }

    mutating func fail(detail: String) -> AVPForearmOverlayResolution {
        lastLivePose = nil
        lastLiveTimestamp = nil
        return AVPForearmOverlayResolution(
            state: .failed,
            trackedPointCount: 0,
            detail: detail,
            pose: nil
        )
    }

    mutating func reset() {
        lastLivePose = nil
        lastLiveTimestamp = nil
    }
}
