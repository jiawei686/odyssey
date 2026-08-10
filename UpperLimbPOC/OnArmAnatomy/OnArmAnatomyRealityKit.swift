#if DEBUG
import RealityKit
import UIKit

enum OnArmAnatomyAssetLoadError: LocalizedError {
    case missingNode(String)
    case implausibleBounds(node: String, extents: SIMD3<Float>)

    var errorDescription: String? {
        switch self {
        case .missingNode(let node):
            "USDZ loaded, but required node \(node) is missing."
        case .implausibleBounds(let node, let extents):
            "USDZ node \(node) has invalid metre bounds: \(extents)."
        }
    }
}

@MainActor
enum OnArmAnatomyRealityKitFactory {
    static let rootName = "OnArmAnatomyRoot"
    private static let assetOffsetName = "OnArmAnatomyAssetOffset"

    static func loadRoot() async throws -> (
        root: Entity,
        evidence: OnArmAnatomyAssetEvidence
    ) {
        let asset = try await Entity(named: OnArmAnatomyAssetContract.assetName)
        guard let radius = asset.findEntity(
            named: OnArmAnatomyAssetContract.radiusNodeName
        ) else {
            throw OnArmAnatomyAssetLoadError.missingNode(
                OnArmAnatomyAssetContract.radiusNodeName
            )
        }
        guard let ulna = asset.findEntity(
            named: OnArmAnatomyAssetContract.ulnaNodeName
        ) else {
            throw OnArmAnatomyAssetLoadError.missingNode(
                OnArmAnatomyAssetContract.ulnaNodeName
            )
        }

        let radiusExtents = radius.visualBounds(
            recursive: true,
            relativeTo: asset
        ).extents
        let ulnaExtents = ulna.visualBounds(
            recursive: true,
            relativeTo: asset
        ).extents
        guard OnArmAnatomyAssetContract.plausibleRadiusLength
            .contains(radiusExtents.z) else {
            throw OnArmAnatomyAssetLoadError.implausibleBounds(
                node: OnArmAnatomyAssetContract.radiusNodeName,
                extents: radiusExtents
            )
        }
        guard OnArmAnatomyAssetContract.plausibleUlnaLength
            .contains(ulnaExtents.z) else {
            throw OnArmAnatomyAssetLoadError.implausibleBounds(
                node: OnArmAnatomyAssetContract.ulnaNodeName,
                extents: ulnaExtents
            )
        }

        applyBrightOpaqueMaterial(to: asset)
        let offset = Entity()
        offset.name = assetOffsetName
        offset.position = -OnArmAnatomyAssetContract.referenceForearmCenter
        offset.addChild(asset)

        let root = Entity()
        root.name = rootName
        root.addChild(offset)
        setVisibleScope(on: root, showFullAsset: true, opacity: 1)

        let assetURL = Bundle.main.url(
            forResource: OnArmAnatomyAssetContract.assetName,
            withExtension: "usdz"
        )
        let assetByteCount = assetURL.flatMap {
            try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize
        } ?? 0
        return (
            root,
            OnArmAnatomyAssetEvidence(
                assetByteCount: assetByteCount,
                radiusExtentsMetres: radiusExtents,
                ulnaExtentsMetres: ulnaExtents
            )
        )
    }

    static func setVisibleScope(
        on root: Entity,
        showFullAsset: Bool,
        opacity: Float
    ) {
        setVisibility(
            on: root,
            showFullAsset: showFullAsset,
            keepAncestor: false,
            opacity: min(max(opacity, 0), 1)
        )
    }

    private static func setVisibility(
        on entity: Entity,
        showFullAsset: Bool,
        keepAncestor: Bool,
        opacity: Float
    ) {
        let keep = keepAncestor
            || entity.name == OnArmAnatomyAssetContract.radiusNodeName
            || entity.name == OnArmAnatomyAssetContract.ulnaNodeName
        if entity.components[ModelComponent.self] != nil {
            entity.components.set(
                OpacityComponent(opacity: showFullAsset || keep ? opacity : 0)
            )
        }
        for child in entity.children {
            setVisibility(
                on: child,
                showFullAsset: showFullAsset,
                keepAncestor: keep,
                opacity: opacity
            )
        }
    }

    private static func applyBrightOpaqueMaterial(to entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            let material = UnlitMaterial(
                color: UIColor(
                    red: 0.95,
                    green: 0.98,
                    blue: 1,
                    alpha: 1
                )
            )
            model.materials = Array(
                repeating: material,
                count: max(model.materials.count, 1)
            )
            entity.components.set(model)
        }
        for child in entity.children {
            applyBrightOpaqueMaterial(to: child)
        }
    }
}
#endif
