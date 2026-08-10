#if DEBUG
import ARKit
import Foundation
import RealityKit
import SwiftUI
import UIKit

struct ClinicalTwinImmersiveView: View {
    @EnvironmentObject private var tracking: LandmarkTrackingService
    @EnvironmentObject private var labState: ClinicalTwinLabState
    @StateObject private var sceneDriver = ClinicalTwinSceneUpdateDriver()
    @State private var sceneUpdateSubscription: EventSubscription?

    var body: some View {
        RealityView { content in
            sceneUpdateSubscription?.cancel()
            sceneDriver.reset()
            labState.beginStaticSession()
            let jointOverlayRoot = ClinicalTwinTrackedJointOverlay.makeRoot()
            content.add(jointOverlayRoot)
            do {
                let loaded = try await ClinicalTwinRealityKitFactory.loadRoot()
                content.add(loaded.root)
                sceneDriver.install(
                    root: loaded.root,
                    jointOverlayRoot: jointOverlayRoot
                )
                sceneUpdateSubscription = content.subscribe(
                    to: SceneEvents.Update.self
                ) { _ in
                    sceneDriver.update(tracking: tracking, labState: labState)
                }
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
        }
        .onDisappear {
            sceneUpdateSubscription?.cancel()
            sceneUpdateSubscription = nil
            sceneDriver.reset()
        }
    }
}

@MainActor
private final class ClinicalTwinSceneUpdateDriver: ObservableObject {
    private var root: Entity?
    private var jointOverlayRoot: Entity?
    private var updateCount = 0

    func install(root: Entity, jointOverlayRoot: Entity) {
        self.root = root
        self.jointOverlayRoot = jointOverlayRoot
        updateCount = 0
    }

    func reset() {
        root = nil
        jointOverlayRoot = nil
        updateCount = 0
    }

    func update(
        tracking: LandmarkTrackingService,
        labState: ClinicalTwinLabState
    ) {
        guard let root, let jointOverlayRoot else { return }
        updateCount += 1

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
        let sceneTransform = Transform(
            scale: presentation.transform.scale,
            rotation: presentation.transform.rotation,
            translation: presentation.transform.translation
        )
        root.setTransformMatrix(sceneTransform.matrix, relativeTo: nil)
        ClinicalTwinRealityKitFactory.setPresentationOpacity(
            on: root,
            opacity: Float(labState.revealAnatomy) * presentation.opacity
        )
        ClinicalTwinTrackedJointOverlay.update(
            root: jointOverlayRoot,
            transforms: tracking.rightHandJointTransforms,
            visible: labState.trackingRequested
                && tracking.handPhase == .running
                && resolution.state == .live
        )

        if updateCount == 1 || updateCount.isMultiple(of: 30) {
            emitDebugEvidence(
                resolution: resolution,
                presentation: presentation,
                root: root
            )
        }
    }

    private func emitDebugEvidence(
        resolution: AVPForearmOverlayResolution,
        presentation: ClinicalTwinPresentation,
        root: Entity
    ) {
        let local = root.transform.translation
        let world = root.position(relativeTo: nil)
        let pose: String
        if let value = resolution.pose {
            pose = String(
                format: "center=(%.3f,%.3f,%.3f) direction=(%.3f,%.3f,%.3f) length=%.3f",
                value.center.x,
                value.center.y,
                value.center.z,
                value.direction.x,
                value.direction.y,
                value.direction.z,
                value.length
            )
        } else {
            pose = "pose=nil"
        }
        print(
            String(
                format: "CLINICAL_TWIN_FRAME count=%d resolution=%@ mode=%@ %@ root=%@ children=%d local=(%.3f,%.3f,%.3f) world=(%.3f,%.3f,%.3f)",
                updateCount,
                resolution.state.rawValue,
                presentation.mode.rawValue,
                pose,
                root.name,
                root.children.count,
                local.x,
                local.y,
                local.z,
                world.x,
                world.y,
                world.z
            )
        )
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
        root: Entity,
        transforms: [HandSkeleton.JointName: simd_float4x4],
        visible: Bool
    ) {
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
