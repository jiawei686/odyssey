#if DEBUG
import ARKit
import RealityKit
import SwiftUI

struct ClinicalTwinImmersiveView: View {
    @EnvironmentObject private var tracking: LandmarkTrackingService
    @EnvironmentObject private var labState: ClinicalTwinLabState

    var body: some View {
        RealityView { content in
            labState.beginStaticSession()
            do {
                let volume = try CTForearmVolumeData.load()
                let startedAt = ContinuousClock.now
                let geometry = try await Task.detached(priority: .userInitiated) {
                    try CTForearmTwinGeometryBuilder.build(
                        volume: volume,
                        spacingMetres: CTForearmVolumeAsset.spacingMetres
                    )
                }.value
                let elapsed = startedAt.duration(to: .now)
                let root = try ClinicalTwinRealityKitFactory.makeRoot(from: geometry)
                content.add(root)
                labState.markStaticReady(ClinicalTwinRenderEvidence(
                    softTissueTriangles: geometry.softTissue.triangleCount,
                    pairedBoneATriangles: geometry.pairedBoneA.triangleCount,
                    pairedBoneBTriangles: geometry.pairedBoneB.triangleCount,
                    buildMilliseconds: elapsed.milliseconds
                ))
            } catch {
                labState.markRendererFailed(error.localizedDescription)
            }
        } update: { content in
            guard let root = content.entities.first(where: {
                $0.name == ClinicalTwinRealityKitFactory.rootName
            }) else { return }

            let resolution = labState.trackingRequested
                ? tracking.rightForearmResolution
                : AVPForearmOverlayResolution(
                    state: .searching,
                    trackedPointCount: 0,
                    detail: "Static reference requested",
                    pose: nil
                )
            let presentation = labState.resolvePresentation(
                resolution: resolution,
                wristTransform: tracking.rightHandJointTransforms[.wrist],
                timestamp: ProcessInfo.processInfo.systemUptime
            )
            root.transform = Transform(
                scale: presentation.transform.scale,
                rotation: presentation.transform.rotation,
                translation: presentation.transform.translation
            )
            applyReveal(
                to: root,
                reveal: Float(labState.revealAnatomy),
                presentationOpacity: presentation.opacity
            )
        }
    }

    private func applyReveal(
        to root: Entity,
        reveal: Float,
        presentationOpacity: Float
    ) {
        let clampedReveal = min(max(reveal, 0), 1)
        let surfaceOpacity = max(0.035, 0.88 * (1 - clampedReveal))
            * presentationOpacity
        let boneOpacity = (0.035 + 0.965 * clampedReveal)
            * presentationOpacity
        root.findEntity(named: ClinicalTwinRealityKitFactory.softTissueName)?
            .components.set(OpacityComponent(opacity: surfaceOpacity))
        root.findEntity(named: ClinicalTwinRealityKitFactory.pairedBoneAName)?
            .components.set(OpacityComponent(opacity: boneOpacity))
        root.findEntity(named: ClinicalTwinRealityKitFactory.pairedBoneBName)?
            .components.set(OpacityComponent(opacity: boneOpacity))
    }
}

private extension Duration {
    var milliseconds: Double {
        let parts = components
        return Double(parts.seconds) * 1_000
            + Double(parts.attoseconds) / 1_000_000_000_000_000
    }
}
#endif
