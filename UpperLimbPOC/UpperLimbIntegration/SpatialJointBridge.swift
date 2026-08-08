import Foundation

struct SpatialForearmModelDefinition: Equatable, Sendable {
    let laterality: UpperLimbLaterality
    let elbow: LandmarkVector3
    let wrist: LandmarkVector3
    let distalRadius: LandmarkVector3?
    let distalUlna: LandmarkVector3?
    let humanReviewed: Bool
}

enum SpatialRegisteredRoot: String, Equatable, Sendable {
    case sharedForearmRoot
}

struct SpatialCommonRootTransform: Equatable, Sendable {
    let transform: SimilarityTransform3D
    let rollResolved: Bool
    let anatomyRoot: SpatialRegisteredRoot
    let sectionalRoot: SpatialRegisteredRoot
}

struct SpatialJointBridgeResult: Equatable, Sendable {
    let registrationState: LandmarkRegistrationReadiness
    let commonRoot: SpatialCommonRootTransform?
    let acceptedJointCount: Int
}

enum SpatialJointBridge {
    static let minimumConfidence = 0.5

    static func integrateAccepted(
        frame: UpperLimbJointFrame,
        gateResult: UpperLimbJointFrameGateResult,
        laterality: UpperLimbLaterality,
        model: SpatialForearmModelDefinition
    ) -> SpatialJointBridgeResult {
        guard gateResult == .accepted,
              frame.isTruthful,
              model.humanReviewed,
              model.laterality == laterality else {
            return insufficient()
        }

        let eligible = frame.observations.filter {
            isEligible($0, laterality: laterality)
        }
        let byJoint = Dictionary(grouping: eligible, by: \.joint)

        func point(_ joint: UpperLimbJointName) -> LandmarkVector3? {
            guard let samples = byJoint[joint], samples.count == 1,
                  let sample = samples.first,
                  let z = sample.position.z else { return nil }
            return LandmarkVector3(
                x: sample.position.x,
                y: sample.position.y,
                z: z
            )
        }

        // The first physical slice is intentionally elbow+wrist axis-only.
        // Distal landmarks and roll remain inert until that slice is verified.
        guard let elbow = point(.elbow),
              let observedWrist = point(.wrist) else {
            return insufficient(acceptedJointCount: eligible.count)
        }

        guard let transform = axisTransform(
                modelElbow: model.elbow,
                modelWrist: model.wrist,
                observedElbow: elbow,
                observedWrist: observedWrist
              ) else {
            return insufficient(acceptedJointCount: eligible.count)
        }

        return SpatialJointBridgeResult(
            registrationState: .axisOnly,
            commonRoot: SpatialCommonRootTransform(
                transform: transform,
                rollResolved: false,
                anatomyRoot: .sharedForearmRoot,
                sectionalRoot: .sharedForearmRoot
            ),
            acceptedJointCount: eligible.count
        )
    }

    private static func isEligible(
        _ observation: UpperLimbJointObservation,
        laterality: UpperLimbLaterality
    ) -> Bool {
        guard observation.isTruthful,
              observation.laterality == laterality,
              observation.position.space == .avpWorld,
              observation.position.unit == .metres,
              observation.validity == .live,
              observation.state == .observed else {
            return false
        }
        return observation.confidence.map { $0 >= minimumConfidence } ?? true
    }

    private static func axisTransform(
        modelElbow: LandmarkVector3,
        modelWrist: LandmarkVector3,
        observedElbow: LandmarkVector3,
        observedWrist: LandmarkVector3
    ) -> SimilarityTransform3D? {
        let modelOffset = modelWrist - modelElbow
        let observedOffset = observedWrist - observedElbow
        guard modelOffset.length > 1e-9,
              observedOffset.length > 1e-9,
              let modelAxis = try? modelOffset.normalized(),
              let observedAxis = try? observedOffset.normalized() else {
            return nil
        }

        let rotation = shortestArcRotation(from: modelAxis, to: observedAxis)
        let scale = observedOffset.length / modelOffset.length
        guard scale.isFinite, scale > 0 else { return nil }
        let translation = observedElbow
            - rotation.applying(to: modelElbow) * scale
        return SimilarityTransform3D(
            scale: scale,
            rotation: rotation,
            translation: translation
        )
    }

    private static func shortestArcRotation(
        from source: LandmarkVector3,
        to destination: LandmarkVector3
    ) -> Matrix3x3 {
        let cosine = max(-1, min(1, source.dot(destination)))
        let cross = source.cross(destination)
        let sine = cross.length

        if sine < 1e-9 {
            if cosine > 0 {
                return .identity
            }
            let helper = abs(source.x) < 0.8
                ? LandmarkVector3(x: 1, y: 0, z: 0)
                : LandmarkVector3(x: 0, y: 1, z: 0)
            let axis = (try? source.cross(helper).normalized())
                ?? LandmarkVector3(x: 0, y: 0, z: 1)
            return halfTurn(around: axis)
        }

        let axis = cross / sine
        let x = axis.x
        let y = axis.y
        let z = axis.z
        let oneMinusCosine = 1 - cosine
        return Matrix3x3(values: [
            oneMinusCosine * x * x + cosine,
            oneMinusCosine * x * y - sine * z,
            oneMinusCosine * x * z + sine * y,
            oneMinusCosine * x * y + sine * z,
            oneMinusCosine * y * y + cosine,
            oneMinusCosine * y * z - sine * x,
            oneMinusCosine * x * z - sine * y,
            oneMinusCosine * y * z + sine * x,
            oneMinusCosine * z * z + cosine
        ])
    }

    private static func halfTurn(around axis: LandmarkVector3) -> Matrix3x3 {
        let x = axis.x
        let y = axis.y
        let z = axis.z
        return Matrix3x3(values: [
            2 * x * x - 1, 2 * x * y, 2 * x * z,
            2 * x * y, 2 * y * y - 1, 2 * y * z,
            2 * x * z, 2 * y * z, 2 * z * z - 1
        ])
    }

    private static func insufficient(
        acceptedJointCount: Int = 0
    ) -> SpatialJointBridgeResult {
        SpatialJointBridgeResult(
            registrationState: .insufficient,
            commonRoot: nil,
            acceptedJointCount: acceptedJointCount
        )
    }
}
