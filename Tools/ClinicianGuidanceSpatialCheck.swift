import Foundation
import simd

@main
enum ClinicianGuidanceSpatialCheck {
    static func main() throws {
        try normalizedEndpointsUseTheLiveForearmAxis()
        try boneVisibilityIsIndependentFromGuidancePlacement()
        try clearAndInvalidStatesHideSpatialGuidance()
        print("Clinician-guidance spatial checks passed")
    }

    private static func normalizedEndpointsUseTheLiveForearmAxis() throws {
        let pose = try makePose()
        let proximal = try requirePlacement(
            state: .initial.settingFracturePosition(0),
            pose: pose
        )
        let distal = try requirePlacement(
            state: .initial.settingFracturePosition(1),
            pose: pose
        )
        let quarter = try requirePlacement(
            state: .initial.settingFracturePosition(0.25),
            pose: pose
        )
        try require(
            approximatelyEqual(proximal.fractureMarkerCenter, pose.proximalPoint),
            "zero must map to the proximal/near-elbow endpoint"
        )
        try require(
            approximatelyEqual(distal.fractureMarkerCenter, pose.distalPoint),
            "one must map to the distal/wrist endpoint"
        )
        try require(
            approximatelyEqual(
                quarter.fractureMarkerCenter,
                pose.proximalPoint + ((pose.distalPoint - pose.proximalPoint) * 0.25)
            ),
            "intermediate positions must interpolate in AVP world coordinates"
        )
    }

    private static func boneVisibilityIsIndependentFromGuidancePlacement() throws {
        let pose = try makePose()
        let visible = ClinicianGuidanceState.initial
            .settingFracturePosition(0.6)
            .settingIncisionGuideVisible(true)
        let hiddenBone = visible.settingBoneVisible(false)
        let placement = try requirePlacement(state: hiddenBone, pose: pose)
        try require(
            placement.fractureMarkerCenter != nil,
            "hiding the bone must not hide the fracture marker"
        )
        try require(
            placement.incisionGuideCenter == placement.fractureMarkerCenter,
            "preset guide and fracture marker must share one semantic axis position"
        )
        let mappedAxis = placement.incisionGuideRotation.act(SIMD3<Float>(0, 1, 0))
        try require(
            simd_distance(mappedAxis, pose.direction) < 0.0001,
            "preset collar must remain perpendicular to the live forearm axis"
        )
    }

    private static func clearAndInvalidStatesHideSpatialGuidance() throws {
        let pose = try makePose()
        let cleared = ClinicianGuidanceState.initial
            .settingFracturePosition(0.5)
            .settingIncisionGuideVisible(true)
            .clearingGuidance()
        let clearedPlacement = try requirePlacement(state: cleared, pose: pose)
        try require(
            clearedPlacement.fractureMarkerCenter == nil
                && clearedPlacement.incisionGuideCenter == nil,
            "clear must remove both spatial guidance entities"
        )

        let invalid = ClinicianGuidanceState(
            showBone: true,
            fracturePosition: nil,
            showIncisionGuide: true
        )
        try require(
            AVPClinicianGuidanceSpatialMapper.resolve(
                pose: pose,
                appliedState: invalid
            ) == nil,
            "invalid guide-without-position state must fail closed"
        )
    }

    private static func makePose() throws -> AVPForearmOverlayPose {
        let resolution = AVPForearmOverlayPoseResolver.resolve(
            forearmArm: SIMD3<Float>(0.1, 0.2, -0.3),
            forearmWrist: SIMD3<Float>(0.32, 0.2, -0.3),
            wrist: SIMD3<Float>(0.325, 0.2, -0.3)
        )
        guard resolution.state == .live, let pose = resolution.pose else {
            throw CheckFailure(message: "fixture must resolve a live forearm pose")
        }
        return pose
    }

    private static func requirePlacement(
        state: ClinicianGuidanceState,
        pose: AVPForearmOverlayPose
    ) throws -> AVPClinicianGuidancePlacement {
        guard let placement = AVPClinicianGuidanceSpatialMapper.resolve(
            pose: pose,
            appliedState: state
        ) else {
            throw CheckFailure(message: "expected valid spatial placement")
        }
        return placement
    }

    private static func approximatelyEqual(
        _ lhs: SIMD3<Float>?,
        _ rhs: SIMD3<Float>,
        tolerance: Float = 0.0001
    ) -> Bool {
        guard let lhs else { return false }
        return simd_distance(lhs, rhs) <= tolerance
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message: message) }
    }
}

private struct CheckFailure: Error {
    let message: String
}
