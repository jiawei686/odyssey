#if DEBUG
import RealityKit

@MainActor
enum ClinicalTwinRealityKitFactory {
    static let rootName = "OdysseyRightForearmCTTwinRoot"

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

        // The validated factory has already centred the Blender USDZ under
        // this root. Keep that exact geometry-bearing hierarchy and authored
        // local -Z axis; the scene updater transforms this direct root.
        loaded.root.name = rootName
        return (loaded.root, loaded.evidence)
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
