import Foundation
import simd

@main
enum ClinicalTwinPoseCheck {
    static func main() throws {
        try staticPreviewIsTruthfulAndVisible()
        try livePoseScalesAndOffsetsBesideRightForearm()
        try wristOrientationContributesRoll()
        try besideOffsetPreservesItsSideAcrossNearVerticalMotion()
        try staleTrackingFreezesTheLastSafePose()
        try failedTrackingHoldsThenExpiresTheLastSafePose()
        print("Clinical twin pose checks passed")
    }

    private static func staticPreviewIsTruthfulAndVisible() throws {
        var resolver = ClinicalTwinPresentationResolver()
        let result = resolver.resolve(
            resolution: .init(
                state: .searching,
                trackedPointCount: 0,
                detail: "Show the right forearm",
                pose: nil
            ),
            wristTransform: nil,
            timestamp: 0
        )
        try expect(result.mode == .staticReference, "searching must use the labelled static reference")
        try expect(!result.isAttachedToWearer, "static reference must not claim attachment")
        try expect(result.opacity == 1, "static reference must remain visible")
        try expect(result.rendererRoute == .anatomyToolBlenderUSDZ, "renderer route must be truthful")
    }

    private static func livePoseScalesAndOffsetsBesideRightForearm() throws {
        let pose = makePose(
            proximal: SIMD3<Float>(0, 1.2, -0.45),
            distal: SIMD3<Float>(0, 0.94, -0.45)
        )
        var resolver = ClinicalTwinPresentationResolver(safeOffsetMetres: 0.16)
        let result = resolver.resolve(
            resolution: .init(
                state: .live,
                trackedPointCount: 3,
                detail: "live",
                pose: pose
            ),
            wristTransform: nil,
            timestamp: 1
        )
        try expect(result.mode == .following, "live tracking must follow")
        try expect(result.isAttachedToWearer, "live result must be labelled attached")
        try expect(abs(result.transform.scale.y - pose.length) < 0.000_001, "longitudinal scale must match forearm length")
        let offset = result.transform.translation - pose.center
        try expect(simd_length(offset) >= 0.16, "twin must be placed beside the real forearm")
    }

    private static func wristOrientationContributesRoll() throws {
        let pose = makePose(
            proximal: SIMD3<Float>(0, 0, 0),
            distal: SIMD3<Float>(0, 0, -0.26)
        )
        var resolverA = ClinicalTwinPresentationResolver()
        let unrolled = resolverA.resolve(
            resolution: live(pose),
            wristTransform: matrix_identity_float4x4,
            timestamp: 1
        )
        var rotatedWrist = matrix_identity_float4x4
        let wristRotation = simd_float4x4(
            simd_quatf(angle: .pi / 2, axis: pose.direction)
        )
        rotatedWrist.columns.0 = wristRotation.columns.0
        rotatedWrist.columns.1 = wristRotation.columns.1
        rotatedWrist.columns.2 = wristRotation.columns.2
        var resolverB = ClinicalTwinPresentationResolver()
        let rolled = resolverB.resolve(
            resolution: live(pose),
            wristTransform: rotatedWrist,
            timestamp: 1
        )
        let difference = abs(simd_dot(unrolled.transform.rotation.vector, rolled.transform.rotation.vector))
        try expect(difference < 0.999, "tracked wrist orientation must influence forearm roll")
    }

    private static func besideOffsetPreservesItsSideAcrossNearVerticalMotion() throws {
        let firstPose = makePose(
            proximal: SIMD3<Float>(0, 0.8, -0.5),
            distal: SIMD3<Float>(0.003, 1.06, -0.5)
        )
        let secondPose = makePose(
            proximal: SIMD3<Float>(0, 0.8, -0.5),
            distal: SIMD3<Float>(-0.003, 1.06, -0.5)
        )
        var resolver = ClinicalTwinPresentationResolver()
        let first = resolver.resolve(
            resolution: live(firstPose),
            wristTransform: nil,
            timestamp: 1
        )
        let second = resolver.resolve(
            resolution: live(secondPose),
            wristTransform: nil,
            timestamp: 1.1
        )
        let firstOffset = simd_normalize(first.transform.translation - firstPose.center)
        let secondOffset = simd_normalize(second.transform.translation - secondPose.center)
        try expect(
            simd_dot(firstOffset, secondOffset) > 0.9,
            "beside offset must not flip sides near a vertical arm pose"
        )
    }

    private static func staleTrackingFreezesTheLastSafePose() throws {
        let livePose = makePose(
            proximal: SIMD3<Float>(0.1, 1.1, -0.5),
            distal: SIMD3<Float>(0.1, 0.84, -0.5)
        )
        let changedPose = makePose(
            proximal: SIMD3<Float>(0.7, 1.4, -0.2),
            distal: SIMD3<Float>(0.7, 1.14, -0.2)
        )
        var resolver = ClinicalTwinPresentationResolver()
        let liveResult = resolver.resolve(
            resolution: live(livePose),
            wristTransform: nil,
            timestamp: 10
        )
        let staleResult = resolver.resolve(
            resolution: .init(
                state: .stale,
                trackedPointCount: 1,
                detail: "interrupted",
                pose: changedPose
            ),
            wristTransform: nil,
            timestamp: 10.5
        )
        try expect(staleResult.mode == .staleFrozen, "stale tracking must freeze")
        try expect(staleResult.transform == liveResult.transform, "stale input must not move the last safe pose")
        try expect(staleResult.opacity < liveResult.opacity, "stale twin must visibly dim")
    }

    private static func failedTrackingHoldsThenExpiresTheLastSafePose() throws {
        var resolver = ClinicalTwinPresentationResolver()
        let live = resolver.resolve(
            resolution: live(makePose(
                proximal: SIMD3<Float>(0, 1, -0.5),
                distal: SIMD3<Float>(0, 0.74, -0.5)
            )),
            wristTransform: nil,
            timestamp: 20
        )
        let held = resolver.resolve(
            resolution: .init(
                state: .failed,
                trackedPointCount: 0,
                detail: "expired",
                pose: nil
            ),
            wristTransform: nil,
            timestamp: 21
        )
        try expect(held.mode == .staleFrozen, "brief provider failure must freeze the safe pose")
        try expect(held.transform == live.transform, "provider failure must not move the safe pose")

        let expired = resolver.resolve(
            resolution: .init(
                state: .failed,
                trackedPointCount: 0,
                detail: "expired",
                pose: nil
            ),
            wristTransform: nil,
            timestamp: 23.1
        )
        try expect(expired.mode == .staticReference, "expired tracking must show a labelled static reference")
        try expect(!expired.isAttachedToWearer, "expired tracking must not claim attachment")
        try expect(expired.statusDetail.contains("Static reference"), "failure copy must expose the static fallback")
    }

    private static func live(_ pose: AVPForearmOverlayPose) -> AVPForearmOverlayResolution {
        .init(state: .live, trackedPointCount: 3, detail: "live", pose: pose)
    }

    private static func makePose(
        proximal: SIMD3<Float>,
        distal: SIMD3<Float>
    ) -> AVPForearmOverlayPose {
        let vector = distal - proximal
        let length = simd_length(vector)
        let direction = vector / length
        return AVPForearmOverlayPose(
            proximalPoint: proximal,
            distalPoint: distal,
            center: (proximal + distal) * 0.5,
            sectionCenter: (proximal + distal) * 0.5,
            direction: direction,
            rotation: simd_quatf(from: SIMD3<Float>(0, 1, 0), to: direction),
            length: length,
            overlayRadius: 0.035,
            sectionRadius: 0.047,
            sectionOffsetFromCenter: 0,
            rollResolved: false
        )
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else { throw CheckError.failed(message) }
    }

    private enum CheckError: Error {
        case failed(String)
    }
}
