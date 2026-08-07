import Foundation
import simd

enum OverlayTint: String, CaseIterable, Codable, Identifiable {
    case cyan
    case blue
    case green
    case amber
    case magenta
    case white

    var id: String { rawValue }

    var name: String {
        switch self {
        case .cyan: "Cyan"
        case .blue: "Blue"
        case .green: "Green"
        case .amber: "Amber"
        case .magenta: "Magenta"
        case .white: "White"
        }
    }

    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .cyan: (0.25, 0.95, 1.00)
        case .blue: (0.25, 0.55, 1.00)
        case .green: (0.30, 1.00, 0.55)
        case .amber: (1.00, 0.68, 0.20)
        case .magenta: (1.00, 0.32, 0.82)
        case .white: (1.00, 1.00, 1.00)
        }
    }
}

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
    enum SectionSourceStatus: Equatable {
        case notLoaded
        case referenceTextures
        case syntheticFallback

        var message: String {
            switch self {
            case .notLoaded:
                "Reference textures have not been loaded yet"
            case .referenceTextures:
                "Showing bundled NLM reference textures"
            case .syntheticFallback:
                "A reference texture failed to load — synthetic fallback may be shown"
            }
        }
    }

    static let referenceSliceCount = 5

    @Published var selectedRegion: BodyRegion = .rightUpperLimb
    @Published var x: Double = 0.0
    @Published var y: Double = -0.15
    @Published var z: Double = -0.70

    @Published var pitchDegrees: Double = -90.0
    @Published var yawDegrees: Double = 0.0
    @Published var rollDegrees: Double = 0.0
    @Published var scale: Double = 1.0
    @Published var opacity: Double = 0.70
    @Published var tint: OverlayTint = .cyan
    @Published var locked = false
    @Published var trackingEnabled = true
    @Published var sectionVisible = false
    @Published var normalizedSlicePosition: Double = 0.5
    @Published var sectionOpacity: Double = 0.68
    @Published private(set) var selectedSliceIndex = 2
    @Published private(set) var sectionSourceStatus: SectionSourceStatus = .notLoaded
    @Published private(set) var focusedBoneName = "Forearm anatomy"
    @Published private(set) var focusedBoneDescription = "Single-pinch a bone to identify it. Double-pinch the overlay to change imaging mode."

    let sliceCount = referenceSliceCount

    var imagingModeName: String {
        sectionVisible ? "3D bone + axial section" : "3D bone"
    }

    func reset() {
        x = 0.0
        y = -0.15
        z = -0.70
        pitchDegrees = -90.0
        yawDegrees = 0.0
        rollDegrees = 0.0
        scale = 1.0
        opacity = 0.70
        tint = .cyan
        locked = false
        sectionVisible = false
        setSectionPosition(0.5)
        sectionOpacity = 0.68
    }

    func resetPlacement() {
        x = 0.0
        y = -0.15
        z = -0.70
        pitchDegrees = -90.0
        yawDegrees = 0.0
        rollDegrees = 0.0
        scale = 1.0
        locked = false
    }

    func makeVisible() {
        resetPlacement()
        opacity = max(opacity, 0.85)
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
            tintID: tint.rawValue,
            locked: locked,
            sectionVisible: sectionVisible,
            normalizedSlicePosition: normalizedSlicePosition,
            sectionOpacity: sectionOpacity,
            selectedSliceIndex: selectedSliceIndex,
            sliceCount: sliceCount
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
        opacity = min(max(snapshot.opacity, 0.25), 1.00)
        tint = OverlayTint(rawValue: snapshot.tintID) ?? .cyan
        locked = snapshot.locked
        sectionVisible = snapshot.sectionVisible
        sectionOpacity = min(max(snapshot.sectionOpacity, 0.15), 1.0)
        setSectionPosition(snapshot.normalizedSlicePosition)
    }

    func setSectionPosition(_ position: Double) {
        let clamped = min(max(position, 0.0), 1.0)
        normalizedSlicePosition = clamped
        selectedSliceIndex = Int(
            (clamped * Double(sliceCount - 1)).rounded()
        )
    }

    func selectSlice(_ index: Int) {
        let clamped = min(max(index, 0), sliceCount - 1)
        selectedSliceIndex = clamped
        normalizedSlicePosition = Double(clamped) / Double(sliceCount - 1)
    }

    func cycleImagingMode() {
        sectionVisible.toggle()
    }

    func setSectionSourceStatus(_ status: SectionSourceStatus) {
        sectionSourceStatus = status
    }

    func captureManualPlacement(
        position: SIMD3<Float>,
        entityScale: SIMD3<Float>
    ) {
        x = min(max(Double(position.x), -0.50), 0.50)
        y = min(max(Double(position.y), -0.50), 0.50)
        z = min(max(Double(position.z), -1.50), -0.20)
        let measuredScale = Double(
            (abs(entityScale.x) + abs(entityScale.y) + abs(entityScale.z)) / 3
        )
        scale = min(max(measuredScale, 0.50), 1.50)
    }

    func focusBone(entityName: String?) {
        let identifier = entityName?
            .replacingOccurrences(of: "_r", with: "")
            .replacingOccurrences(of: "_l", with: "")
            .lowercased() ?? ""

        switch identifier {
        case let value where value.contains("radius"):
            focusedBoneName = "Radius"
            focusedBoneDescription = "The lateral forearm bone on the thumb side; it rotates around the ulna during pronation and supination."
        case let value where value.contains("ulna"):
            focusedBoneName = "Ulna"
            focusedBoneDescription = "The medial forearm bone on the little-finger side; its proximal end forms the main hinge of the elbow."
        case let value where value.contains("metacarpal"):
            focusedBoneName = "Metacarpal"
            focusedBoneDescription = "One of five long bones connecting the wrist carpal bones to the finger phalanges."
        case let value where value.contains("phalanx"):
            focusedBoneName = "Phalanx"
            focusedBoneDescription = "A finger bone. Each finger has proximal, middle, and distal phalanges; the thumb has two."
        case let value where value.contains("scaphoid"):
            focusedBoneName = "Scaphoid"
            focusedBoneDescription = "A proximal-row carpal bone on the thumb side and a common site of wrist fracture."
        case let value where value.contains("lunate"):
            focusedBoneName = "Lunate"
            focusedBoneDescription = "A central proximal-row carpal bone that articulates with the radius."
        case let value where value.contains("triquetrum"):
            focusedBoneName = "Triquetrum"
            focusedBoneDescription = "A proximal-row carpal bone on the ulnar side of the wrist."
        case let value where value.contains("pisiform"):
            focusedBoneName = "Pisiform"
            focusedBoneDescription = "A small sesamoid carpal bone on the palmar surface of the triquetrum."
        case let value where value.contains("trapezium"):
            focusedBoneName = "Trapezium"
            focusedBoneDescription = "The carpal bone supporting the thumb carpometacarpal joint."
        case let value where value.contains("trapezoid"):
            focusedBoneName = "Trapezoid"
            focusedBoneDescription = "A distal-row carpal bone between the trapezium and capitate."
        case let value where value.contains("capitate"):
            focusedBoneName = "Capitate"
            focusedBoneDescription = "The largest carpal bone, centrally located in the distal row."
        case let value where value.contains("hamate"):
            focusedBoneName = "Hamate"
            focusedBoneDescription = "An ulnar distal-row carpal bone with a palmar hook."
        default:
            focusedBoneName = "Forearm and hand"
            focusedBoneDescription = "This educational model contains the radius, ulna, eight carpal bones, five metacarpals, and finger phalanges."
        }
    }
}
