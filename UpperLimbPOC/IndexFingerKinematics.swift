import simd

struct JointRotationCalibration {
    private(set) var jointFromPivotRestRotation: simd_quatf?
    private(set) var calibratedForLeftHand: Bool?
    private(set) var sessionGeneration: Int?

    mutating func resolvedPivotRotation(
        jointRotation: simd_quatf,
        currentPivotRotation: simd_quatf,
        isLeftHand: Bool,
        sessionGeneration: Int
    ) -> simd_quatf {
        if calibratedForLeftHand != isLeftHand
            || self.sessionGeneration != sessionGeneration {
            jointFromPivotRestRotation = nil
            calibratedForLeftHand = isLeftHand
            self.sessionGeneration = sessionGeneration
        }

        guard let restOffset = jointFromPivotRestRotation else {
            jointFromPivotRestRotation = jointRotation.inverse
                * currentPivotRotation
            return currentPivotRotation
        }

        return jointRotation * restOffset
    }
}
