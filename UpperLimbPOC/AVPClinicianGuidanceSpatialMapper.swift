import Foundation
import simd

struct AVPClinicianGuidancePlacement: Sendable {
    let fractureMarkerCenter: SIMD3<Float>?
    let incisionGuideCenter: SIMD3<Float>?
    let incisionGuideRotation: simd_quatf
    let incisionGuideRadius: Float
    let incisionGuideThickness: Float
}

enum AVPClinicianGuidanceSpatialMapper {
    static func resolve(
        pose: AVPForearmOverlayPose,
        appliedState: ClinicianGuidanceState
    ) -> AVPClinicianGuidancePlacement? {
        guard appliedState.isValid,
              pose.length.isFinite,
              pose.length > 0,
              isFinite(pose.proximalPoint),
              isFinite(pose.distalPoint),
              isFinite(pose.direction) else { return nil }

        let normalizedPosition = appliedState.fracturePosition?.value
        let center = normalizedPosition.map { value in
            pose.proximalPoint
                + ((pose.distalPoint - pose.proximalPoint) * Float(value))
        }
        let radius = min(max(pose.overlayRadius * 1.2, 0.018), 0.055)

        return AVPClinicianGuidancePlacement(
            fractureMarkerCenter: center,
            incisionGuideCenter: appliedState.showIncisionGuide ? center : nil,
            incisionGuideRotation: pose.rotation,
            incisionGuideRadius: radius,
            incisionGuideThickness: 0.004
        )
    }

    private static func isFinite(_ point: SIMD3<Float>) -> Bool {
        point.x.isFinite && point.y.isFinite && point.z.isFinite
    }
}
