#if DEBUG
import Foundation
import simd

enum OnArmAnatomyAssetContract {
    static let assetName = "hand-to-elbow-overlay"
    static let assetFilename = "hand-to-elbow-overlay.usdz"
    static let assetSHA256 = "72ce34528dc5f56915e43c018948fd5a1898489880c19ff4c64e6e39352a3f94"
    static let radiusNodeName = "Radius_r"
    static let ulnaNodeName = "Ulna_r"
    static let referenceForearmLengthMetres: Float = 0.2625

    // Runtime bounds are measured relative to the USDZ root. The midpoint is
    // used only to place the generic radius/ulna pair on the tracked axis.
    static let referenceForearmCenter = SIMD3<Float>(
        0.023_702_2,
        0.035_067_9,
        0.078_617_4
    )

    static let plausibleRadiusLength: ClosedRange<Float> = 0.23 ... 0.25
    static let plausibleUlnaLength: ClosedRange<Float> = 0.25 ... 0.275
    static let staticTranslation = SIMD3<Float>(0, -0.04, -0.68)
}

struct OnArmAnatomyAssetEvidence: Equatable, Sendable {
    let assetByteCount: Int
    let radiusExtentsMetres: SIMD3<Float>
    let ulnaExtentsMetres: SIMD3<Float>
}

enum OnArmAnatomyVisibilityMode: String, CaseIterable, Identifiable, Sendable {
    case normalOverlay
    case seeThroughAnatomy

    var id: String { rawValue }

    var immersiveSpaceID: String {
        switch self {
        case .normalOverlay: "OnArmAnatomyNormalSpace"
        case .seeThroughAnatomy: "OnArmAnatomySeeThroughSpace"
        }
    }

    var label: String {
        switch self {
        case .normalOverlay: "Normal overlay"
        case .seeThroughAnatomy: "See-Through Anatomy"
        }
    }

    var detail: String {
        switch self {
        case .normalOverlay:
            "The real upper limb remains visible. System compositing may occlude virtual bones."
        case .seeThroughAnatomy:
            "The system hides real upper limbs and substitutes the virtual reference anatomy; it does not reveal anatomy beneath the real arm."
        }
    }
}
#endif
