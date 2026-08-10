#if DEBUG
import ARKit
import RealityKit
import SwiftUI
import UIKit

struct ClinicalTwinImmersiveView: View {
    @EnvironmentObject private var tracking: LandmarkTrackingService
    @EnvironmentObject private var labState: ClinicalTwinLabState

    var body: some View {
        RealityView { content in
            labState.beginStaticSession()
            content.add(ClinicalTwinTrackedJointOverlay.makeRoot())
            do {
                let loaded = try await ClinicalTwinRealityKitFactory.loadRoot()
                content.add(loaded.root)
                labState.markStaticReady(ClinicalTwinRenderEvidence(
                    assetByteCount: loaded.evidence.assetByteCount,
                    radiusLengthMetres: loaded.evidence.radiusExtentsMetres.z,
                    ulnaLengthMetres: loaded.evidence.ulnaExtentsMetres.z
                ))
                // Renderer readiness is the deterministic session boundary.
                // Start the provider here instead of waiting for coordinator
                // polling to notice two independently published states.
                await labState.startRightForearmTracking(using: tracking)
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
            ClinicalTwinRealityKitFactory.setPresentationOpacity(
                on: root,
                opacity: Float(labState.revealAnatomy) * presentation.opacity
            )
            ClinicalTwinTrackedJointOverlay.update(
                in: content,
                transforms: tracking.rightHandJointTransforms,
                visible: labState.trackingRequested
                    && tracking.handPhase == .running
                    && tracking.rightForearmResolution.state == .live
            )
        }
    }
}

@MainActor
private enum ClinicalTwinTrackedJointOverlay {
    private struct JointLabel {
        let joint: HandSkeleton.JointName
        let text: String
        let color: UIColor
    }

    private static let rootName = "ClinicalTwinTrackedRightJointLabels"
    private static let labels = [
        JointLabel(joint: .forearmArm, text: "NEAR ELBOW", color: .systemBlue),
        JointLabel(joint: .wrist, text: "WRIST", color: .systemGreen),
        JointLabel(joint: .indexFingerKnuckle, text: "INDEX MCP", color: .systemOrange),
        JointLabel(joint: .indexFingerIntermediateBase, text: "INDEX PIP", color: .systemYellow),
        JointLabel(joint: .indexFingerIntermediateTip, text: "INDEX DIP", color: .systemPink)
    ]

    static func makeRoot() -> Entity {
        let root = Entity()
        root.name = rootName
        root.isEnabled = false

        for (index, label) in labels.enumerated() {
            let anchor = Entity()
            anchor.name = labelName(index: index)
            anchor.isEnabled = false

            let marker = ModelEntity(
                mesh: .generateSphere(radius: 0.005),
                materials: [UnlitMaterial(color: label.color)]
            )
            marker.name = "Marker"
            anchor.addChild(marker)

            let text = ModelEntity(
                mesh: .generateText(
                    label.text,
                    extrusionDepth: 0.0003,
                    font: .systemFont(ofSize: 0.012, weight: .semibold)
                ),
                materials: [UnlitMaterial(color: label.color)]
            )
            text.name = "Label"
            text.position = SIMD3<Float>(0.008, 0.008, 0)
            anchor.addChild(text)
            root.addChild(anchor)
        }
        return root
    }

    static func update(
        in content: RealityViewContent,
        transforms: [HandSkeleton.JointName: simd_float4x4],
        visible: Bool
    ) {
        guard let root = content.entities.first(where: { $0.name == rootName }) else {
            return
        }
        guard visible else {
            root.isEnabled = false
            return
        }

        var hasVisibleJoint = false
        for (index, label) in labels.enumerated() {
            guard let anchor = root.findEntity(named: labelName(index: index)) else {
                continue
            }
            guard let transform = transforms[label.joint],
                  let position = finitePosition(of: transform) else {
                anchor.isEnabled = false
                continue
            }
            anchor.position = position
            anchor.isEnabled = true
            hasVisibleJoint = true
        }
        root.isEnabled = hasVisibleJoint
    }

    private static func finitePosition(
        of transform: simd_float4x4
    ) -> SIMD3<Float>? {
        let position = SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
        guard position.x.isFinite,
              position.y.isFinite,
              position.z.isFinite else { return nil }
        return position
    }

    private static func labelName(index: Int) -> String {
        "ClinicalTwinTrackedJointLabel-\(index)"
    }
}
#endif
