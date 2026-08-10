#if DEBUG
import Foundation
import simd

struct OnArmAnatomyCalibration: Equatable, Sendable {
    var scaleMultiplier: Float = 1
    var axialMetres: Float = 0
    var lateralMetres: Float = 0
    var depthMetres: Float = 0
    var rollDegrees: Float = 0

    var clamped: Self {
        Self(
            scaleMultiplier: min(max(scaleMultiplier, 0.8), 1.2),
            axialMetres: min(max(axialMetres, -0.05), 0.05),
            lateralMetres: min(max(lateralMetres, -0.03), 0.03),
            depthMetres: min(max(depthMetres, -0.03), 0.03),
            rollDegrees: min(max(rollDegrees, -45), 45)
        )
    }
}

enum OnArmAnatomyPresentationMode: String, Equatable, Sendable {
    case staticFullAsset
    case searchingRightForearm
    case followingRightForearm
    case staleFrozen
    case hiddenAfterTimeout
}

struct OnArmAnatomySpatialTransform: Equatable, Sendable {
    let scale: SIMD3<Float>
    let rotation: simd_quatf
    let translation: SIMD3<Float>
}

struct OnArmAnatomyPresentation: Equatable, Sendable {
    let mode: OnArmAnatomyPresentationMode
    let transform: OnArmAnatomySpatialTransform
    let isVisible: Bool
    let showFullAsset: Bool
    let opacity: Float
    let statusTitle: String
    let statusDetail: String
}

struct OnArmAnatomyPresentationResolver: Sendable {
    static let staleHoldSeconds: Double = 3
    static let staleOpacity: Float = 0.38

    private var lastSafeTransform: OnArmAnatomySpatialTransform?
    private var lastSafeTimestamp: Double?
    private var lastLateralBasis: SIMD3<Float>?

    mutating func resolve(
        resolution: AVPForearmOverlayResolution,
        wristTransform: simd_float4x4?,
        trackingRequested: Bool,
        calibration: OnArmAnatomyCalibration,
        timestamp: Double
    ) -> OnArmAnatomyPresentation {
        guard trackingRequested else { return staticPresentation }

        if resolution.state == .live,
           let pose = resolution.pose,
           let transform = trackedTransform(
               pose: pose,
               wristTransform: wristTransform,
               calibration: calibration.clamped
           ) {
            lastSafeTransform = transform
            lastSafeTimestamp = timestamp
            return OnArmAnatomyPresentation(
                mode: .followingRightForearm,
                transform: transform,
                isVisible: true,
                showFullAsset: false,
                opacity: 1,
                statusTitle: "Radius and ulna aligned to right forearm",
                statusDetail: "Live best-fit reference alignment; tracking wrist roll and forearm axis"
            )
        }

        if let frozen = frozenPresentationIfRecent(timestamp: timestamp) {
            return frozen
        }

        let isInitialSearch = lastSafeTimestamp == nil
        return OnArmAnatomyPresentation(
            mode: isInitialSearch ? .searchingRightForearm : .hiddenAfterTimeout,
            transform: staticPresentation.transform,
            isVisible: false,
            showFullAsset: false,
            opacity: 0,
            statusTitle: isInitialSearch
                ? "Searching for Odyssey's right forearm"
                : "Tracking expired — anatomy hidden",
            statusDetail: isInitialSearch
                ? "Need live right forearmArm, forearmWrist, and wrist transforms"
                : "No safe pose for more than 3 seconds; hidden rather than drifting"
        )
    }

    mutating func reset() {
        lastSafeTransform = nil
        lastSafeTimestamp = nil
        lastLateralBasis = nil
    }

    private mutating func trackedTransform(
        pose: AVPForearmOverlayPose,
        wristTransform: simd_float4x4?,
        calibration: OnArmAnatomyCalibration
    ) -> OnArmAnatomySpatialTransform? {
        guard pose.length.isFinite,
              (0.12 ... 0.45).contains(pose.length),
              pose.center.allFinite,
              pose.direction.allFinite else { return nil }

        let axisLength = simd_length(pose.direction)
        guard axisLength.isFinite, axisLength > 0.000_001 else { return nil }
        let axis = pose.direction / axisLength

        var lateral = projectedWristX(
            axis: axis,
            wristTransform: wristTransform
        ) ?? projectedFallback(axis: axis)
        guard simd_length_squared(lateral) > 0.000_001 else { return nil }
        lateral = simd_normalize(lateral)
        if let lastLateralBasis, simd_dot(lateral, lastLateralBasis) < 0 {
            lateral *= -1
        }
        lastLateralBasis = lateral

        var depth = simd_cross(lateral, axis)
        guard simd_length_squared(depth) > 0.000_001 else { return nil }
        depth = simd_normalize(depth)

        let localLongAxis = SIMD3<Float>(0, 0, -1)
        let baseRotation = simd_quatf(from: localLongAxis, to: axis)
        let baseLateral = baseRotation.act(SIMD3<Float>(1, 0, 0))
        let wristRoll = atan2(
            simd_dot(simd_cross(baseLateral, lateral), axis),
            min(max(simd_dot(baseLateral, lateral), -1), 1)
        )
        let rollRadians = calibration.rollDegrees * .pi / 180
        let rotation = simd_normalize(
            simd_quatf(angle: wristRoll + rollRadians, axis: axis)
                * baseRotation
        )

        let uniformScale = pose.length
            / OnArmAnatomyAssetContract.referenceForearmLengthMetres
            * calibration.scaleMultiplier
        guard uniformScale.isFinite, uniformScale > 0 else { return nil }

        let translation = pose.center
            + axis * calibration.axialMetres
            + lateral * calibration.lateralMetres
            + depth * calibration.depthMetres
        return OnArmAnatomySpatialTransform(
            scale: SIMD3<Float>(repeating: uniformScale),
            rotation: rotation,
            translation: translation
        )
    }

    private mutating func projectedFallback(axis: SIMD3<Float>) -> SIMD3<Float> {
        if let lastLateralBasis {
            let projected = lastLateralBasis
                - axis * simd_dot(lastLateralBasis, axis)
            if simd_length_squared(projected) > 0.000_001 { return projected }
        }
        for candidate in [
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(0, 0, 1)
        ] {
            let projected = candidate - axis * simd_dot(candidate, axis)
            if simd_length_squared(projected) > 0.000_001 { return projected }
        }
        return .zero
    }

    private func projectedWristX(
        axis: SIMD3<Float>,
        wristTransform: simd_float4x4?
    ) -> SIMD3<Float>? {
        guard let wristTransform, wristTransform.allFinite else { return nil }
        let wristX = SIMD3<Float>(
            wristTransform.columns.0.x,
            wristTransform.columns.0.y,
            wristTransform.columns.0.z
        )
        let projected = wristX - axis * simd_dot(wristX, axis)
        let length = simd_length(projected)
        guard length.isFinite, length > 0.000_1 else { return nil }
        return projected / length
    }

    private mutating func frozenPresentationIfRecent(
        timestamp: Double
    ) -> OnArmAnatomyPresentation? {
        guard timestamp.isFinite,
              let lastSafeTransform,
              let lastSafeTimestamp,
              timestamp >= lastSafeTimestamp,
              timestamp - lastSafeTimestamp <= Self.staleHoldSeconds else {
            if let lastSafeTimestamp,
               timestamp.isFinite,
               timestamp - lastSafeTimestamp > Self.staleHoldSeconds {
                self.lastSafeTransform = nil
                self.lastLateralBasis = nil
            }
            return nil
        }
        return OnArmAnatomyPresentation(
            mode: .staleFrozen,
            transform: lastSafeTransform,
            isVisible: true,
            showFullAsset: false,
            opacity: Self.staleOpacity,
            statusTitle: "Tracking stale — anatomy frozen",
            statusDetail: "Holding the exact last safe pose for up to 3 seconds; no drift"
        )
    }

    private var staticPresentation: OnArmAnatomyPresentation {
        OnArmAnatomyPresentation(
            mode: .staticFullAsset,
            transform: OnArmAnatomySpatialTransform(
                scale: SIMD3<Float>(repeating: 1),
                rotation: simd_quatf(
                    from: SIMD3<Float>(0, 0, -1),
                    to: SIMD3<Float>(1, 0, 0)
                ),
                translation: OnArmAnatomyAssetContract.staticTranslation
            ),
            isVisible: true,
            showFullAsset: true,
            opacity: 1,
            statusTitle: "Static full anatomy asset",
            statusDetail: "Confirm the real USDZ is visible before enabling right-forearm tracking"
        )
    }
}

private extension SIMD3 where Scalar == Float {
    var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}

private extension simd_float4x4 {
    var allFinite: Bool {
        columns.0.allFinite
            && columns.1.allFinite
            && columns.2.allFinite
            && columns.3.allFinite
    }
}

private extension SIMD4 where Scalar == Float {
    var allFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite && w.isFinite
    }
}
#endif
