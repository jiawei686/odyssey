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

        // The validated factory has already centred the Blender USDZ. Keep its
        // authored local -Z elbow-to-wrist axis unchanged: the presentation
        // resolver maps that axis directly into the live AVP forearm pose.
        loaded.root.name = assetRootName

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
