import ARKit
import RealityKit
import SwiftUI

struct JointProbeImmersiveView: View {
    @EnvironmentObject private var tracking: LandmarkTrackingService

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "JointProbeRoot"

            for (index, _) in HandSkeleton.JointName.allCases.enumerated() {
                root.addChild(
                    makeJointSphere(
                        name: entityName(isLeft: true, index: index),
                        color: .cyan
                    )
                )
                root.addChild(
                    makeJointSphere(
                        name: entityName(isLeft: false, index: index),
                        color: .orange
                    )
                )
            }
            content.add(root)
        } update: { content in
            guard let root = content.entities.first(where: {
                $0.name == "JointProbeRoot"
            }) else { return }

            updateSpheres(
                in: root,
                isLeft: true,
                transforms: tracking.leftHandJointTransforms
            )
            updateSpheres(
                in: root,
                isLeft: false,
                transforms: tracking.rightHandJointTransforms
            )
        }
    }

    private func makeJointSphere(name: String, color: UIColor) -> ModelEntity {
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: 0.008),
            materials: [
                SimpleMaterial(
                    color: color,
                    roughness: 0.35,
                    isMetallic: false
                )
            ]
        )
        sphere.name = name
        sphere.isEnabled = false
        return sphere
    }

    private func updateSpheres(
        in root: Entity,
        isLeft: Bool,
        transforms: [HandSkeleton.JointName: simd_float4x4]
    ) {
        for (index, jointName) in HandSkeleton.JointName.allCases.enumerated() {
            guard let sphere = root.findEntity(
                named: entityName(isLeft: isLeft, index: index)
            ) else { continue }

            guard let transform = transforms[jointName] else {
                sphere.isEnabled = false
                continue
            }

            sphere.position = Transform(matrix: transform).translation
            sphere.isEnabled = true
        }
    }

    private func entityName(isLeft: Bool, index: Int) -> String {
        "JointProbe-\(isLeft ? "Left" : "Right")-\(index)"
    }
}
