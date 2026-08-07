import Foundation

enum BodyRegion: String, CaseIterable, Codable, Identifiable {
    case skull
    case cervicalSpine
    case chest
    case lumbarSpine
    case wholeSpine
    case pelvis
    case leftHip
    case rightHip
    case leftUpperLimb
    case rightUpperLimb
    case leftLowerLimb
    case rightLowerLimb

    var id: String { rawValue }

    var name: String {
        switch self {
        case .skull: "Skull"
        case .cervicalSpine: "Cervical Spine"
        case .chest: "Chest / Rib Cage"
        case .lumbarSpine: "Abdomen / Lumbar Spine"
        case .wholeSpine: "Entire Spine"
        case .pelvis: "Pelvis"
        case .leftHip: "Left Hip"
        case .rightHip: "Right Hip"
        case .leftUpperLimb: "Left Forearm & Hand"
        case .rightUpperLimb: "Right Forearm & Hand"
        case .leftLowerLimb: "Left Lower Limb"
        case .rightLowerLimb: "Right Lower Limb"
        }
    }

    var category: String {
        switch self {
        case .skull, .cervicalSpine, .wholeSpine:
            "Head and spine"
        case .chest, .lumbarSpine:
            "Trunk"
        case .pelvis, .leftHip, .rightHip:
            "Pelvis and hips"
        case .leftUpperLimb, .rightUpperLimb:
            "Upper limbs"
        case .leftLowerLimb, .rightLowerLimb:
            "Lower limbs"
        }
    }

    var systemImage: String {
        switch self {
        case .skull: "person.crop.circle"
        case .cervicalSpine: "figure.stand"
        case .chest: "lungs.fill"
        case .lumbarSpine: "figure.core.training"
        case .wholeSpine: "figure.strengthtraining.traditional"
        case .pelvis: "figure.stand"
        case .leftHip, .rightHip: "figure.walk"
        case .leftUpperLimb, .rightUpperLimb: "figure.arms.open"
        case .leftLowerLimb, .rightLowerLimb: "figure.run"
        }
    }

    var accentName: String {
        switch category {
        case "Head and spine": "cyan"
        case "Trunk": "blue"
        case "Pelvis and hips": "indigo"
        case "Upper limbs": "teal"
        default: "mint"
        }
    }

    var assetName: String? {
        switch self {
        case .leftUpperLimb, .rightUpperLimb:
            "hand-to-elbow-overlay"
        default:
            nil
        }
    }

    var isAvailable: Bool { assetName != nil }
    var isLeft: Bool {
        self == .leftHip || self == .leftUpperLimb || self == .leftLowerLimb
    }
}

@MainActor
final class OverlayState: ObservableObject {
    @Published var selectedRegion: BodyRegion = .rightUpperLimb
    @Published var x: Double = 0.0
    @Published var y: Double = -0.15
    @Published var z: Double = -0.70

    @Published var pitchDegrees: Double = -90.0
    @Published var yawDegrees: Double = 0.0
    @Published var rollDegrees: Double = 0.0
    @Published var scale: Double = 1.0
    @Published var opacity: Double = 0.70
    @Published var locked = false
    @Published var trackingEnabled = true

    func reset() {
        x = 0.0
        y = -0.15
        z = -0.70
        pitchDegrees = -90.0
        yawDegrees = 0.0
        rollDegrees = 0.0
        scale = 1.0
        opacity = 0.70
        locked = false
    }

    func makeVisible() {
        x = 0.0
        y = -0.15
        z = -0.70
        pitchDegrees = -90.0
        yawDegrees = 0.0
        rollDegrees = 0.0
        scale = 1.0
        opacity = 0.85
        locked = false
    }

    var snapshot: OverlaySnapshot {
        OverlaySnapshot(
            regionID: selectedRegion.rawValue,
            x: x,
            y: y,
            z: z,
            pitchDegrees: pitchDegrees,
            yawDegrees: yawDegrees,
            rollDegrees: rollDegrees,
            scale: scale,
            opacity: opacity,
            locked: locked
        )
    }

    func applyCalibration(_ snapshot: OverlaySnapshot) {
        x = snapshot.x
        y = snapshot.y
        z = snapshot.z
        pitchDegrees = snapshot.pitchDegrees
        yawDegrees = snapshot.yawDegrees
        rollDegrees = snapshot.rollDegrees
        scale = snapshot.scale
        opacity = snapshot.opacity
        locked = snapshot.locked
    }
}
