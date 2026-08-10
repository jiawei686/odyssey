#if DEBUG
import RealityKit
import UIKit

@MainActor
enum ClinicalTwinRealityKitFactory {
    static let rootName = "OdysseyRightForearmCTTwinRoot"
    static let softTissueName = "CTDerivedSoftTissueShell"
    static let pairedBoneAName = "CTDerivedPairedForearmBoneA"
    static let pairedBoneBName = "CTDerivedPairedForearmBoneB"

    static func makeRoot(from geometry: CTForearmTwinGeometry) throws -> Entity {
        let root = Entity()
        root.name = rootName

        let softTissue = ModelEntity(
            mesh: try meshResource(
                from: geometry.softTissue,
                name: softTissueName
            ),
            materials: [SimpleMaterial(
                color: UIColor(
                    red: 0.90,
                    green: 0.46,
                    blue: 0.34,
                    alpha: 1
                ),
                roughness: 0.62,
                isMetallic: false
            )]
        )
        softTissue.name = softTissueName

        let boneMaterial = SimpleMaterial(
            color: UIColor(
                red: 1,
                green: 0.92,
                blue: 0.67,
                alpha: 1
            ),
            roughness: 0.24,
            isMetallic: false
        )
        let pairedBoneA = ModelEntity(
            mesh: try meshResource(
                from: geometry.pairedBoneA,
                name: pairedBoneAName
            ),
            materials: [boneMaterial]
        )
        pairedBoneA.name = pairedBoneAName
        let pairedBoneB = ModelEntity(
            mesh: try meshResource(
                from: geometry.pairedBoneB,
                name: pairedBoneBName
            ),
            materials: [boneMaterial]
        )
        pairedBoneB.name = pairedBoneBName

        root.addChild(softTissue)
        root.addChild(pairedBoneA)
        root.addChild(pairedBoneB)
        return root
    }

    private static func meshResource(
        from part: CTForearmTwinMeshPart,
        name: String
    ) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(part.positions)
        descriptor.normals = MeshBuffers.Normals(part.normals)
        descriptor.primitives = .triangles(part.indices)
        return try MeshResource.generate(from: [descriptor])
    }
}
#endif
