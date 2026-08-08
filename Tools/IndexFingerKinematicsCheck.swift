import Foundation
import simd

@main
struct IndexFingerKinematicsCheck {
    static func main() {
        var calibration = JointRotationCalibration()
        let identity = simd_quatf(angle: 0, axis: SIMD3<Float>(1, 0, 0))
        let flexed = simd_quatf(
            angle: .pi / 3,
            axis: SIMD3<Float>(1, 0, 0)
        )

        let initial = calibration.resolvedPivotRotation(
            jointRotation: identity,
            currentPivotRotation: identity,
            isLeftHand: false,
            sessionGeneration: 1
        )
        require(nearlyEqual(initial, identity), "initial pose must not snap")

        let drivenFlexion = calibration.resolvedPivotRotation(
            jointRotation: flexed,
            currentPivotRotation: initial,
            isLeftHand: false,
            sessionGeneration: 1
        )
        require(
            nearlyEqual(drivenFlexion, flexed),
            "live joint rotation must drive the calibrated pivot"
        )

        // A missing anchor does not call the resolver. The established rest
        // offset remains intact while rendering freezes at drivenFlexion.
        let reacquiredExtended = calibration.resolvedPivotRotation(
            jointRotation: identity,
            currentPivotRotation: drivenFlexion,
            isLeftHand: false,
            sessionGeneration: 1
        )
        require(
            nearlyEqual(reacquiredExtended, identity),
            "reacquisition must resume the current pose, not recalibrate stale flexion"
        )

        let newSessionPose = calibration.resolvedPivotRotation(
            jointRotation: identity,
            currentPivotRotation: drivenFlexion,
            isLeftHand: false,
            sessionGeneration: 2
        )
        require(
            nearlyEqual(newSessionPose, drivenFlexion),
            "a new ARKit session must recalibrate without an immediate snap"
        )

        print("Index-finger kinematics checks passed.")
    }

    private static func nearlyEqual(
        _ lhs: simd_quatf,
        _ rhs: simd_quatf,
        tolerance: Float = 0.0001
    ) -> Bool {
        let probe = simd_normalize(SIMD3<Float>(0.17, 0.73, 0.41))
        return simd_length(lhs.act(probe) - rhs.act(probe)) <= tolerance
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fputs("Index-finger kinematics check failed: \(message)\n", stderr)
            exit(1)
        }
    }
}
