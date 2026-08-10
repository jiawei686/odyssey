#if DEBUG
import RealityKit

@MainActor
enum ClinicalTwinRealityKitFactory {
    static let rootName = "OdysseyRightForearmCTTwinRoot"
    private static let assetRootName = "BlenderHandToElbowAssetRoot"

    static func loadRoot() async throws -> (
        root: Entity,
        evidence: OnArmAnatomyAssetEvidence
    ) {
        let loaded = try await OnArmAnatomyRealityKitFactory.loadRoot()
        OnArmAnatomyRealityKitFactory.setVisibleScope(
            on: loaded.root,
            showFullAsset: true,
            opacity: 1
        )

        // The Blender USDZ is centred by its validated asset factory and uses
        // local -Z as elbow-to-wrist. Adapt it once to the ClinicalTwin root's
        // normalized +Y longitudinal axis; the existing tracked presentation
        // can then keep its established beside-arm scale, roll, and offset.
        loaded.root.name = assetRootName
        loaded.root.transform = Transform(
            scale: SIMD3<Float>(
                1,
                1,
                1 / OnArmAnatomyAssetContract.referenceForearmLengthMetres
            ),
            rotation: simd_quatf(
                from: SIMD3<Float>(0, 0, -1),
                to: SIMD3<Float>(0, 1, 0)
            ),
            translation: .zero
        )

        let root = Entity()
        root.name = rootName
        root.addChild(loaded.root)
        return (root, loaded.evidence)
    }

    static func setPresentationOpacity(on root: Entity, opacity: Float) {
        OnArmAnatomyRealityKitFactory.setVisibleScope(
            on: root,
            showFullAsset: true,
            opacity: min(max(opacity, 0), 1)
        )
    }
}
#endif
