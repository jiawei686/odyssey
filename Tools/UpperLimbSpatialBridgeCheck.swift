import Foundation

@main
struct UpperLimbSpatialBridgeCheck {
    static func main() throws {
        try knownAxisTransformIsAxisOnlyAndShared()
        try distalTripletCannotAdvanceTheAxisOnlySlice()
        try wrongSpaceLateralityAndStateFailClosed()
        try rejectedLeadGateCannotMoveAnatomy()
        print("Upper-limb spatial bridge checks passed")
    }

    private static func knownAxisTransformIsAxisOnlyAndShared() throws {
        let result = SpatialJointBridge.integrateAccepted(
            frame: frame([
                observed(.elbow, side: .right, point: .init(x: 1, y: 2, z: 3)),
                observed(.wrist, side: .right, point: .init(x: 1, y: 4, z: 3))
            ]),
            gateResult: .accepted,
            laterality: .right,
            model: modelDefinition()
        )

        try require(result.registrationState == .axisOnly, "two points must be axis-only")
        guard let root = result.commonRoot else {
            throw CheckFailure(message: "axis-only result needs a root transform")
        }
        try require(!root.rollResolved, "two points cannot resolve roll")
        try require(root.anatomyRoot == root.sectionalRoot, "3D and sectional content must share one root")
        let transformedElbow = root.transform.applying(to: .zero)
        let transformedWrist = root.transform.applying(to: .init(x: 0, y: 1, z: 0))
        try require((transformedElbow - .init(x: 1, y: 2, z: 3)).length < 1e-9, "elbow mapping mismatch")
        try require((transformedWrist - .init(x: 1, y: 4, z: 3)).length < 1e-9, "wrist mapping mismatch")
    }

    private static func distalTripletCannotAdvanceTheAxisOnlySlice() throws {
        let result = SpatialJointBridge.integrateAccepted(
            frame: frame([
                observed(.elbow, side: .right, point: .init(x: 1, y: -2, z: 0.5)),
                observed(.distalRadius, side: .right, point: .init(x: -1, y: -1.8, z: 0.5)),
                observed(.distalUlna, side: .right, point: .init(x: -1, y: -2.2, z: 0.5))
            ]),
            gateResult: .accepted,
            laterality: .right,
            model: modelDefinition()
        )
        try require(result.registrationState == .insufficient, "distal triplet must remain gated until the later phase")
        try require(result.commonRoot == nil, "the first slice must not infer a wrist or resolve roll from distal points")
    }

    private static func wrongSpaceLateralityAndStateFailClosed() throws {
        let wrongSpace = UpperLimbJointObservation(
            laterality: .right,
            joint: .elbow,
            position: .init(x: 0, y: 0, z: 1, space: .iPhoneCamera, unit: .metres),
            confidence: 0.9,
            confidenceScope: .landmark,
            depthSource: .lidar,
            validity: .live,
            state: .observed
        )
        let staleWrist = UpperLimbJointObservation(
            laterality: .right,
            joint: .wrist,
            position: .init(x: 0, y: 1, z: 1, space: .avpWorld, unit: .metres),
            confidence: 0.9,
            confidenceScope: .landmark,
            depthSource: .lidar,
            validity: .stale,
            state: .observed
        )
        let otherSide = observed(.wrist, side: .left, point: .init(x: 0, y: 1, z: 1))
        let result = SpatialJointBridge.integrateAccepted(
            frame: frame([wrongSpace, staleWrist, otherSide]),
            gateResult: .accepted,
            laterality: .right,
            model: modelDefinition()
        )
        try require(result.registrationState == .insufficient, "wrong-space, wrong-side, or stale samples must not drive anatomy")
        try require(result.commonRoot == nil, "invalid samples must not produce a transform")
    }

    private static func rejectedLeadGateCannotMoveAnatomy() throws {
        let result = SpatialJointBridge.integrateAccepted(
            frame: frame([
                observed(.elbow, side: .right, point: .init(x: 0, y: 0, z: 0)),
                observed(.wrist, side: .right, point: .init(x: 0, y: 1, z: 0))
            ]),
            gateResult: .rejected(.calibrationMismatch),
            laterality: .right,
            model: modelDefinition()
        )
        try require(result.registrationState == .insufficient, "rejected lead gate must fail closed")
    }

    private static func modelDefinition() -> SpatialForearmModelDefinition {
        SpatialForearmModelDefinition(
            laterality: .right,
            elbow: .zero,
            wrist: .init(x: 0, y: 1, z: 0),
            distalRadius: .init(x: 0.1, y: 1, z: 0),
            distalUlna: .init(x: -0.1, y: 1, z: 0),
            humanReviewed: true
        )
    }

    private static func frame(_ observations: [UpperLimbJointObservation]) -> UpperLimbJointFrame {
        UpperLimbJointFrame(
            sessionID: UUID(),
            calibrationID: UUID(),
            senderClockID: UUID(),
            sequence: 1,
            capturedAtMonotonic: 1,
            observations: observations
        )
    }

    private static func observed(
        _ joint: UpperLimbJointName,
        side: UpperLimbLaterality,
        point: LandmarkVector3
    ) -> UpperLimbJointObservation {
        UpperLimbJointObservation(
            laterality: side,
            joint: joint,
            position: .init(x: point.x, y: point.y, z: point.z, space: .avpWorld, unit: .metres),
            confidence: 0.9,
            confidenceScope: .landmark,
            depthSource: .lidar,
            validity: .live,
            state: .observed
        )
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message: message) }
    }
}

private struct CheckFailure: Error {
    let message: String
}
