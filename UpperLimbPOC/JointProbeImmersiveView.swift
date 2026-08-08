import ARKit
import RealityKit
import SwiftUI

struct JointProbeImmersiveView: View {
    @EnvironmentObject private var tracking: LandmarkTrackingService

    private struct BoneEdge {
        let start: HandSkeleton.JointName
        let end: HandSkeleton.JointName
        let radius: Float
    }

    private let boneRootName = "TrackedArticulatedBoneRoot"

    private var boneEdges: [BoneEdge] {
        [
            BoneEdge(start: .forearmArm, end: .forearmWrist, radius: 0.009),
            BoneEdge(start: .forearmWrist, end: .wrist, radius: 0.007),
            BoneEdge(start: .wrist, end: .thumbKnuckle, radius: 0.005),
            BoneEdge(start: .thumbKnuckle, end: .thumbIntermediateBase, radius: 0.0045),
            BoneEdge(start: .thumbIntermediateBase, end: .thumbIntermediateTip, radius: 0.004),
            BoneEdge(start: .thumbIntermediateTip, end: .thumbTip, radius: 0.0035),
            BoneEdge(start: .wrist, end: .indexFingerMetacarpal, radius: 0.0055),
            BoneEdge(start: .indexFingerMetacarpal, end: .indexFingerKnuckle, radius: 0.005),
            BoneEdge(start: .indexFingerKnuckle, end: .indexFingerIntermediateBase, radius: 0.0045),
            BoneEdge(start: .indexFingerIntermediateBase, end: .indexFingerIntermediateTip, radius: 0.004),
            BoneEdge(start: .indexFingerIntermediateTip, end: .indexFingerTip, radius: 0.0035),
            BoneEdge(start: .wrist, end: .middleFingerMetacarpal, radius: 0.0055),
            BoneEdge(start: .middleFingerMetacarpal, end: .middleFingerKnuckle, radius: 0.005),
            BoneEdge(start: .middleFingerKnuckle, end: .middleFingerIntermediateBase, radius: 0.0045),
            BoneEdge(start: .middleFingerIntermediateBase, end: .middleFingerIntermediateTip, radius: 0.004),
            BoneEdge(start: .middleFingerIntermediateTip, end: .middleFingerTip, radius: 0.0035),
            BoneEdge(start: .wrist, end: .ringFingerMetacarpal, radius: 0.0055),
            BoneEdge(start: .ringFingerMetacarpal, end: .ringFingerKnuckle, radius: 0.005),
            BoneEdge(start: .ringFingerKnuckle, end: .ringFingerIntermediateBase, radius: 0.0045),
            BoneEdge(start: .ringFingerIntermediateBase, end: .ringFingerIntermediateTip, radius: 0.004),
            BoneEdge(start: .ringFingerIntermediateTip, end: .ringFingerTip, radius: 0.0035),
            BoneEdge(start: .wrist, end: .littleFingerMetacarpal, radius: 0.0055),
            BoneEdge(start: .littleFingerMetacarpal, end: .littleFingerKnuckle, radius: 0.005),
            BoneEdge(start: .littleFingerKnuckle, end: .littleFingerIntermediateBase, radius: 0.0045),
            BoneEdge(start: .littleFingerIntermediateBase, end: .littleFingerIntermediateTip, radius: 0.004),
            BoneEdge(start: .littleFingerIntermediateTip, end: .littleFingerTip, radius: 0.0035)
        ]
    }

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "JointProbeRoot"

            let markerMesh = MeshResource.generateSphere(radius: 0.003)
            let markerMaterial = UnlitMaterial(color: .cyan)
            for (index, _) in HandSkeleton.JointName.allCases.enumerated() {
                let marker = ModelEntity(
                    mesh: markerMesh,
                    materials: [markerMaterial]
                )
                marker.name = detectionMarkerName(index: index)
                marker.isEnabled = false
                root.addChild(marker)
            }

            let boneRoot = Entity()
            boneRoot.name = boneRootName
            boneRoot.isEnabled = false

            let segmentMesh = MeshResource.generateCylinder(height: 1, radius: 1)
            let jointMesh = MeshResource.generateSphere(radius: 0.005)
            let boneMaterial = SimpleMaterial(
                color: UIColor(
                    red: 0.96,
                    green: 0.86,
                    blue: 0.48,
                    alpha: 1
                ),
                roughness: 0.22,
                isMetallic: false
            )
            for (index, _) in boneEdges.enumerated() {
                let segment = ModelEntity(
                    mesh: segmentMesh,
                    materials: [boneMaterial]
                )
                segment.name = boneSegmentName(index: index)
                segment.isEnabled = false
                boneRoot.addChild(segment)
            }
            for (index, _) in HandSkeleton.JointName.allCases.enumerated() {
                let joint = ModelEntity(
                    mesh: jointMesh,
                    materials: [boneMaterial]
                )
                joint.name = boneJointName(index: index)
                joint.isEnabled = false
                boneRoot.addChild(joint)
            }
            root.addChild(boneRoot)
            content.add(root)
        } update: { content in
            guard let root = content.entities.first(where: {
                $0.name == "JointProbeRoot"
            }) else { return }

            let transforms = tracking.probeSelectedHand == .left
                ? tracking.leftHandJointTransforms
                : tracking.rightHandJointTransforms
            updateDetectionMarkers(
                in: root,
                transforms: transforms,
                visible: tracking.handPhase == .running
                    && !tracking.probeBoneVisible
            )
            updateBoneOverlay(in: root, transforms: transforms)
        }
    }

    private func updateBoneOverlay(
        in root: Entity,
        transforms: [HandSkeleton.JointName: simd_float4x4]
    ) {
        guard let boneRoot = root.findEntity(named: boneRootName) else { return }
        let resolution = tracking.probeSelectedHand == .left
            ? tracking.leftForearmResolution
            : tracking.rightForearmResolution

        guard tracking.probeBoneVisible else {
            boneRoot.isEnabled = false
            return
        }

        switch resolution.state {
        case .live:
            updateBoneSegments(in: boneRoot, transforms: transforms)
            updateBoneJoints(in: boneRoot, transforms: transforms)
            boneRoot.components.set(OpacityComponent(opacity: 1))
            boneRoot.isEnabled = true
        case .stale:
            let hasLastPose = boneRoot.children.contains { $0.isEnabled }
            boneRoot.components.set(OpacityComponent(opacity: 0.45))
            boneRoot.isEnabled = hasLastPose
        case .searching, .partial, .failed:
            boneRoot.isEnabled = false
        }
    }

    private func updateBoneSegments(
        in boneRoot: Entity,
        transforms: [HandSkeleton.JointName: simd_float4x4]
    ) {
        for (index, edge) in boneEdges.enumerated() {
            guard let segment = boneRoot.findEntity(
                named: boneSegmentName(index: index)
            ) else { continue }
            guard let start = position(of: transforms[edge.start]),
                  let end = position(of: transforms[edge.end]),
                  let resolved = AVPTrackedBoneSegmentTransformResolver.resolve(
                    start: start,
                    end: end
                  ) else {
                segment.isEnabled = false
                continue
            }
            segment.transform = Transform(
                scale: SIMD3<Float>(edge.radius, resolved.length, edge.radius),
                rotation: resolved.rotation,
                translation: resolved.center
            )
            segment.isEnabled = true
        }
    }

    private func updateBoneJoints(
        in boneRoot: Entity,
        transforms: [HandSkeleton.JointName: simd_float4x4]
    ) {
        for (index, jointName) in HandSkeleton.JointName.allCases.enumerated() {
            guard let joint = boneRoot.findEntity(
                named: boneJointName(index: index)
            ) else { continue }
            guard let jointPosition = position(of: transforms[jointName]) else {
                joint.isEnabled = false
                continue
            }
            joint.position = jointPosition
            joint.isEnabled = true
        }
    }

    private func updateDetectionMarkers(
        in root: Entity,
        transforms: [HandSkeleton.JointName: simd_float4x4],
        visible: Bool
    ) {
        for (index, jointName) in HandSkeleton.JointName.allCases.enumerated() {
            guard let marker = root.findEntity(
                named: detectionMarkerName(index: index)
            ) else { continue }
            guard visible, let jointPosition = position(of: transforms[jointName]) else {
                marker.isEnabled = false
                continue
            }
            marker.position = jointPosition
            marker.isEnabled = true
        }
    }

    private func position(of transform: simd_float4x4?) -> SIMD3<Float>? {
        guard let transform else { return nil }
        return SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
    }

    private func detectionMarkerName(index: Int) -> String {
        "DetectionMarker-\(index)"
    }

    private func boneSegmentName(index: Int) -> String {
        "TrackedBoneSegment-\(index)"
    }

    private func boneJointName(index: Int) -> String {
        "TrackedBoneJoint-\(index)"
    }
}
