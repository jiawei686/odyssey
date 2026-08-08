import Foundation

struct BodyScannerPoseLandmark: Equatable, Sendable {
    let index: Int
    let imageX: Double
    let imageY: Double
    let modelRelativeZ: Double?
    let visibility: Double
    let presence: Double
}

enum BodyScannerUpperLimbPoseMapper {
    private struct JointIdentity {
        let laterality: UpperLimbLaterality
        let joint: UpperLimbJointName
    }

    private static let jointByMediaPipeIndex: [Int: JointIdentity] = [
        11: JointIdentity(laterality: .left, joint: .shoulder),
        12: JointIdentity(laterality: .right, joint: .shoulder),
        13: JointIdentity(laterality: .left, joint: .elbow),
        14: JointIdentity(laterality: .right, joint: .elbow),
        15: JointIdentity(laterality: .left, joint: .wrist),
        16: JointIdentity(laterality: .right, joint: .wrist),
    ]

    static func map(
        landmarks: [BodyScannerPoseLandmark],
        imageWidth: Double,
        imageHeight: Double,
        minimumConfidence: Double
    ) -> [UpperLimbJointObservation] {
        guard imageWidth.isFinite, imageHeight.isFinite,
              imageWidth > 0, imageHeight > 0,
              minimumConfidence.isFinite, (0...1).contains(minimumConfidence) else {
            return []
        }

        return landmarks.compactMap { landmark in
            guard let identity = jointByMediaPipeIndex[landmark.index],
                  landmark.imageX.isFinite, landmark.imageY.isFinite,
                  (0...imageWidth).contains(landmark.imageX),
                  (0...imageHeight).contains(landmark.imageY),
                  landmark.visibility.isFinite, landmark.presence.isFinite else {
                return nil
            }

            let boundedVisibility = min(max(landmark.visibility, 0), 1)
            let boundedPresence = min(max(landmark.presence, 0), 1)
            let confidence = min(boundedVisibility, boundedPresence)
            let isQualified = confidence >= minimumConfidence

            return UpperLimbJointObservation(
                laterality: identity.laterality,
                joint: identity.joint,
                position: UpperLimbJointPosition(
                    x: landmark.imageX,
                    y: landmark.imageY,
                    z: nil,
                    space: .imagePixels,
                    unit: .pixels
                ),
                confidence: confidence,
                confidenceScope: .landmark,
                depthSource: .none,
                validity: isQualified ? .live : .partial,
                state: isQualified ? .observed : .estimated
            )
        }
    }
}
