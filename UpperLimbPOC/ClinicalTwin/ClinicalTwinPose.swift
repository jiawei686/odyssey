import Foundation
import simd

enum ClinicalTwinRendererRoute: String, Codable, Equatable, Sendable {
    case ctDerivedMeshFallback
    case anatomyToolBlenderUSDZ

    var label: String {
        switch self {
        case .ctDerivedMeshFallback: "CT-derived mesh fallback"
        case .anatomyToolBlenderUSDZ: "AnatomyTOOL Blender USDZ"
        }
    }
}

enum ClinicalTwinPresentationMode: String, Codable, Equatable, Sendable {
    case staticReference
    case following
    case staleFrozen
}

struct ClinicalTwinSpatialTransform: Equatable, Sendable {
    let scale: SIMD3<Float>
    let rotation: simd_quatf
    let translation: SIMD3<Float>
}

struct ClinicalTwinPresentation: Equatable, Sendable {
    let mode: ClinicalTwinPresentationMode
    let transform: ClinicalTwinSpatialTransform
    let opacity: Float
    let isAttachedToWearer: Bool
    let rendererRoute: ClinicalTwinRendererRoute
    let statusTitle: String
    let statusDetail: String
}

struct ClinicalTwinPresentationResolver: Sendable {
    // Validated from the authored Ulna_r bounds in the bundled Blender USDZ.
    static let referenceForearmLengthMetres: Float = 0.2625
    static let defaultSafeOffsetMetres: Float = 0.16
    static let staleOpacity: Float = 0.42
    static let staleHoldSeconds: Double = 3

    let safeOffsetMetres: Float
    private var lastSafeTransform: ClinicalTwinSpatialTransform?
    private var lastSafeTimestamp: Double?
    private var lastBesideDirection: SIMD3<Float>?

    init(safeOffsetMetres: Float = defaultSafeOffsetMetres) {
        precondition(safeOffsetMetres >= 0.12 && safeOffsetMetres <= 0.30)
        self.safeOffsetMetres = safeOffsetMetres
    }

    mutating func resolve(
        resolution: AVPForearmOverlayResolution,
        wristTransform: simd_float4x4?,
        timestamp: Double
    ) -> ClinicalTwinPresentation {
        switch resolution.state {
        case .live:
            guard let pose = resolution.pose,
                  let transform = trackedTransform(
                    pose: pose,
                    wristTransform: wristTransform
                  ) else {
                if let frozen = frozenPresentationIfRecent(timestamp: timestamp) {
                    return frozen
                }
                return staticPresentation(
                    title: "Right forearm tracking failed",
                    detail: "Static reference only — invalid tracked geometry"
                )
            }
            lastSafeTransform = transform
            lastSafeTimestamp = timestamp
            return ClinicalTwinPresentation(
                mode: .following,
                transform: transform,
                opacity: 1,
                isAttachedToWearer: true,
                rendererRoute: .anatomyToolBlenderUSDZ,
                statusTitle: "Right forearm twin attached",
                statusDetail: "Live — following Odyssey's tracked right forearm"
            )

        case .stale:
            return frozenPresentationIfRecent(timestamp: timestamp)
                ?? staticPresentation(
                    title: "Right forearm tracking interrupted",
                    detail: "Static reference only — no safe tracked pose is available",
                    opacity: Self.staleOpacity
                )

        case .searching:
            if let frozen = frozenPresentationIfRecent(timestamp: timestamp) {
                return frozen
            }
            return staticPresentation(
                title: "Static AnatomyTOOL skeletal twin",
                detail: "Static reference only — show Odyssey's right forearm to attach"
            )

        case .partial:
            if let frozen = frozenPresentationIfRecent(timestamp: timestamp) {
                return frozen
            }
            return staticPresentation(
                title: "Right forearm partially tracked",
                detail: "Static reference only — wrist and forearm endpoints are required"
            )

        case .failed:
            if let frozen = frozenPresentationIfRecent(timestamp: timestamp) {
                return frozen
            }
            return staticPresentation(
                title: "Right forearm tracking unavailable",
                detail: "Static reference only — \(resolution.detail)"
            )
        }
    }

    private mutating func trackedTransform(
        pose: AVPForearmOverlayPose,
        wristTransform: simd_float4x4?
    ) -> ClinicalTwinSpatialTransform? {
        guard pose.length.isFinite,
              (0.12 ... 0.45).contains(pose.length),
              pose.center.allFinite,
              pose.direction.allFinite else { return nil }

        let axisLength = simd_length(pose.direction)
        guard axisLength.isFinite, axisLength > 0.000_001 else { return nil }
        let axis = pose.direction / axisLength
        let rotation = resolvedRotation(axis: axis, wristTransform: wristTransform)

        let worldUp = SIMD3<Float>(0, 1, 0)
        var beside = projectedWristX(
            axis: axis,
            wristTransform: wristTransform
        ) ?? simd_cross(axis, worldUp)
        if simd_length_squared(beside) < 0.000_1,
           let lastBesideDirection {
            beside = lastBesideDirection
                - axis * simd_dot(lastBesideDirection, axis)
        }
        if simd_length_squared(beside) < 0.000_1 {
            beside = SIMD3<Float>(1, 0, 0)
                - axis * simd_dot(SIMD3<Float>(1, 0, 0), axis)
        }
        beside = simd_normalize(beside)
        if let lastBesideDirection,
           simd_dot(beside, lastBesideDirection) < 0 {
            beside *= -1
        }
        lastBesideDirection = beside
        let translation = pose.center + beside * safeOffsetMetres
        let uniformScale = pose.length / Self.referenceForearmLengthMetres

        return ClinicalTwinSpatialTransform(
            scale: SIMD3<Float>(repeating: uniformScale),
            rotation: rotation,
            translation: translation
        )
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
    ) -> ClinicalTwinPresentation? {
        guard timestamp.isFinite,
              let lastSafeTransform,
              let lastSafeTimestamp,
              timestamp >= lastSafeTimestamp,
              timestamp - lastSafeTimestamp <= Self.staleHoldSeconds else {
            self.lastSafeTransform = nil
            self.lastSafeTimestamp = nil
            self.lastBesideDirection = nil
            return nil
        }
        return ClinicalTwinPresentation(
            mode: .staleFrozen,
            transform: lastSafeTransform,
            opacity: Self.staleOpacity,
            isAttachedToWearer: false,
            rendererRoute: .anatomyToolBlenderUSDZ,
            statusTitle: "Tracking stale — twin frozen",
            statusDetail: "Last safe pose held for up to 3 seconds; the twin will not drift"
        )
    }

    private func resolvedRotation(
        axis: SIMD3<Float>,
        wristTransform: simd_float4x4?
    ) -> simd_quatf {
        let localLongAxis = SIMD3<Float>(0, 0, -1)
        let baseRotation = simd_quatf(from: localLongAxis, to: axis)
        guard let wristTransform,
              wristTransform.allFinite else { return baseRotation }

        let wristX = SIMD3<Float>(
            wristTransform.columns.0.x,
            wristTransform.columns.0.y,
            wristTransform.columns.0.z
        )
        let projectedWristX = wristX - axis * simd_dot(wristX, axis)
        let projectedLength = simd_length(projectedWristX)
        guard projectedLength.isFinite, projectedLength > 0.000_1 else {
            return baseRotation
        }

        let targetX = projectedWristX / projectedLength
        let baseX = baseRotation.act(SIMD3<Float>(1, 0, 0))
        let sine = simd_dot(simd_cross(baseX, targetX), axis)
        let cosine = min(max(simd_dot(baseX, targetX), -1), 1)
        let roll = simd_quatf(angle: atan2(sine, cosine), axis: axis)
        return simd_normalize(roll * baseRotation)
    }

    private func staticPresentation(
        title: String,
        detail: String,
        opacity: Float = 1
    ) -> ClinicalTwinPresentation {
        ClinicalTwinPresentation(
            mode: .staticReference,
            transform: Self.staticTransform,
            opacity: opacity,
            isAttachedToWearer: false,
            rendererRoute: .anatomyToolBlenderUSDZ,
            statusTitle: title,
            statusDetail: detail
        )
    }

    private static let staticTransform = ClinicalTwinSpatialTransform(
        scale: SIMD3<Float>(repeating: 1),
        rotation: simd_quatf(
            from: SIMD3<Float>(0, 0, -1),
            to: SIMD3<Float>(1, 0, 0)
        ),
        translation: SIMD3<Float>(0.18, -0.06, -0.55)
    )
}

private extension SIMD3 where Scalar == Float {
    var allFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
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
