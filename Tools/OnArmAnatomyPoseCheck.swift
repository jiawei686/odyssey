import Foundation
import simd

@main
enum OnArmAnatomyPoseCheck {
    static func main() throws {
        try staticGateIsVisibleAndFullAsset()
        try searchingAfterAttachFailsClosed()
        try livePoseUsesDirectCentrelineAndUlnaScale()
        try wristTransformAndCalibrationResolveRoll()
        try calibrationOffsetsAreLocalToTrackedForearm()
        try lateralBasisDoesNotFlipNearVerticalMotion()
        try staleAndFailedTrackingFreezeThenHide()
        print("On-arm anatomy pose checks passed")
    }

    private static func staticGateIsVisibleAndFullAsset() throws {
        var resolver = OnArmAnatomyPresentationResolver()
        let result = resolver.resolve(
            resolution: searching,
            wristTransform: nil,
            trackingRequested: false,
            calibration: .init(),
            timestamp: 0
        )
        try expect(result.mode == .staticFullAsset, "pre-tracking gate must be static")
        try expect(result.isVisible, "static USDZ gate must be visible")
        try expect(result.showFullAsset, "static gate must show the full USDZ")
    }

    private static func searchingAfterAttachFailsClosed() throws {
        var resolver = OnArmAnatomyPresentationResolver()
        let result = resolver.resolve(
            resolution: searching,
            wristTransform: nil,
            trackingRequested: true,
            calibration: .init(),
            timestamp: 0
        )
        try expect(result.mode == .searchingRightForearm, "initial search must be explicit")
        try expect(!result.isVisible, "no arbitrary tracked depth may be estimated")
        try expect(!result.showFullAsset, "hands/fingers must not masquerade as tracking")
    }

    private static func livePoseUsesDirectCentrelineAndUlnaScale() throws {
        let pose = makePose(
            proximal: SIMD3<Float>(0.12, 1.1, -0.52),
            distal: SIMD3<Float>(0.12, 0.8375, -0.52)
        )
        var resolver = OnArmAnatomyPresentationResolver()
        let result = resolver.resolve(
            resolution: live(pose),
            wristTransform: matrix_identity_float4x4,
            trackingRequested: true,
            calibration: .init(),
            timestamp: 1
        )
        try expect(result.mode == .followingRightForearm, "live must follow")
        try expect(!result.showFullAsset, "live route must show radius and ulna only")
        try expect(
            simd_distance(result.transform.translation, pose.center) < 0.000_001,
            "zero calibration must place the model directly on the centreline"
        )
        try expect(
            abs(result.transform.scale.x - 1) < 0.000_001,
            "262.5 mm tracked length must preserve USDZ scale"
        )
        let mappedAxis = result.transform.rotation.act(SIMD3<Float>(0, 0, -1))
        try expect(
            simd_dot(mappedAxis, pose.direction) > 0.999,
            "USDZ elbow-to-wrist -Z axis must map to tracked forearm"
        )
    }

    private static func wristTransformAndCalibrationResolveRoll() throws {
        let pose = makePose(
            proximal: SIMD3<Float>(0, 0, 0),
            distal: SIMD3<Float>(0, 0, -0.2625)
        )
        var unrolledResolver = OnArmAnatomyPresentationResolver()
        let unrolled = unrolledResolver.resolve(
            resolution: live(pose),
            wristTransform: matrix_identity_float4x4,
            trackingRequested: true,
            calibration: .init(),
            timestamp: 1
        )
        var wrist = matrix_identity_float4x4
        wrist.columns.0 = SIMD4<Float>(0, 1, 0, 0)
        wrist.columns.1 = SIMD4<Float>(-1, 0, 0, 0)
        var rolledResolver = OnArmAnatomyPresentationResolver()
        let rolled = rolledResolver.resolve(
            resolution: live(pose),
            wristTransform: wrist,
            trackingRequested: true,
            calibration: OnArmAnatomyCalibration(rollDegrees: 10),
            timestamp: 1
        )
        let similarity = abs(simd_dot(
            unrolled.transform.rotation.vector,
            rolled.transform.rotation.vector
        ))
        try expect(similarity < 0.99, "wrist X and correction must influence roll")
    }

    private static func calibrationOffsetsAreLocalToTrackedForearm() throws {
        let pose = makePose(
            proximal: SIMD3<Float>(0, 0, 0),
            distal: SIMD3<Float>(0.26, 0, 0)
        )
        var resolver = OnArmAnatomyPresentationResolver()
        let calibration = OnArmAnatomyCalibration(
            scaleMultiplier: 1.1,
            axialMetres: 0.02,
            lateralMetres: 0.01,
            depthMetres: -0.005,
            rollDegrees: 0
        )
        let result = resolver.resolve(
            resolution: live(pose),
            wristTransform: matrix_identity_float4x4,
            trackingRequested: true,
            calibration: calibration,
            timestamp: 2
        )
        try expect(
            abs(result.transform.scale.x - (pose.length / 0.2625 * 1.1)) < 0.000_001,
            "diagnostic scale must compose with anatomical scale"
        )
        let displacement = result.transform.translation - pose.center
        try expect(
            abs(simd_dot(displacement, pose.direction) - 0.02) < 0.000_001,
            "axial calibration must follow the tracked centreline"
        )
        try expect(
            simd_length(displacement) > 0.022,
            "lateral/depth calibration must be applied"
        )
    }

    private static func lateralBasisDoesNotFlipNearVerticalMotion() throws {
        let firstPose = makePose(
            proximal: SIMD3<Float>(0, 0.8, -0.5),
            distal: SIMD3<Float>(0.003, 1.06, -0.5)
        )
        let secondPose = makePose(
            proximal: SIMD3<Float>(0, 0.8, -0.5),
            distal: SIMD3<Float>(-0.003, 1.06, -0.5)
        )
        let calibration = OnArmAnatomyCalibration(lateralMetres: 0.02)
        var resolver = OnArmAnatomyPresentationResolver()
        let first = resolver.resolve(
            resolution: live(firstPose),
            wristTransform: nil,
            trackingRequested: true,
            calibration: calibration,
            timestamp: 3
        )
        let second = resolver.resolve(
            resolution: live(secondPose),
            wristTransform: nil,
            trackingRequested: true,
            calibration: calibration,
            timestamp: 3.1
        )
        let firstOffset = simd_normalize(first.transform.translation - firstPose.center)
        let secondOffset = simd_normalize(second.transform.translation - secondPose.center)
        try expect(
            simd_dot(firstOffset, secondOffset) > 0.9,
            "calibration basis must preserve sign near vertical motion"
        )
    }

    private static func staleAndFailedTrackingFreezeThenHide() throws {
        let pose = makePose(
            proximal: SIMD3<Float>(0.1, 1.1, -0.5),
            distal: SIMD3<Float>(0.1, 0.84, -0.5)
        )
        var resolver = OnArmAnatomyPresentationResolver()
        let liveResult = resolver.resolve(
            resolution: live(pose),
            wristTransform: nil,
            trackingRequested: true,
            calibration: .init(),
            timestamp: 10
        )
        let held = resolver.resolve(
            resolution: .init(
                state: .failed,
                trackedPointCount: 0,
                detail: "stream ended",
                pose: nil
            ),
            wristTransform: nil,
            trackingRequested: true,
            calibration: .init(),
            timestamp: 11
        )
        try expect(held.mode == .staleFrozen, "brief failure must freeze")
        try expect(held.transform == liveResult.transform, "frozen pose must be exact")
        try expect(held.opacity < liveResult.opacity, "frozen pose must dim")

        let expired = resolver.resolve(
            resolution: searching,
            wristTransform: nil,
            trackingRequested: true,
            calibration: .init(),
            timestamp: 13.01
        )
        try expect(expired.mode == .hiddenAfterTimeout, "expired pose must be explicit")
        try expect(!expired.isVisible, "expired pose must hide instead of drifting")
    }

    private static var searching: AVPForearmOverlayResolution {
        .init(
            state: .searching,
            trackedPointCount: 0,
            detail: "show right forearm",
            pose: nil
        )
    }

    private static func live(
        _ pose: AVPForearmOverlayPose
    ) -> AVPForearmOverlayResolution {
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
