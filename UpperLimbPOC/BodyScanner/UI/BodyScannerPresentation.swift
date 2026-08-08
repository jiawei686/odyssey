import Foundation

enum BodyScannerPresentation {
    static let disclosure = "CROSS-SUBJECT • APPROXIMATE • EDUCATIONAL"
    static let landmarkTruth = "Model-estimated visual landmarks • Not verified anatomical joint centres"
    static let privacy = "On-device processing • No images saved"
}

enum BodyScannerGuidanceCondition: String, CaseIterable, Sendable {
    case multiplePeople
    case noParticipant
    case bodyClipped
    case bodyTooSmall
    case armsNotSeparated
    case missingLeftHand
    case missingRightHand
    case handsNotOpen
    case sideAmbiguous
    case stabilizing
    case ready

    var instruction: String {
        switch self {
        case .multiplePeople: "Keep only one participant in view"
        case .noParticipant: "Frame one consenting participant"
        case .bodyClipped: "Show both shoulders, arms, and hands"
        case .bodyTooSmall: "Move the iPhone closer"
        case .armsNotSeparated: "Separate both arms from the torso"
        case .missingLeftHand: "Show the participant's left hand"
        case .missingRightHand: "Show the participant's right hand"
        case .handsNotOpen: "Open both hands toward the camera"
        case .sideAmbiguous: "Hold still while left and right are resolved"
        case .stabilizing: "Hold the pose steady"
        case .ready: "Upper-limb joints ready"
        }
    }
}

enum BodyScannerGuidanceResolver {
    static func resolve(
        _ conditions: Set<BodyScannerGuidanceCondition>
    ) -> BodyScannerGuidanceCondition {
        BodyScannerGuidanceCondition.allCases.first(where: conditions.contains)
            ?? .ready
    }
}

struct BodyScannerPoint: Equatable, Sendable {
    let x: Double
    let y: Double
}

struct BodyScannerFrameSize: Equatable, Sendable {
    let width: Double
    let height: Double

    static let waiting = BodyScannerFrameSize(width: 1, height: 1)
}

struct BodyScannerRect: Equatable, Sendable {
    let minX: Double
    let minY: Double
    let width: Double
    let height: Double
}

struct BodyScannerPreviewProjection: Equatable, Sendable {
    let imageRect: BodyScannerRect

    init(
        sensorWidth: Double,
        sensorHeight: Double,
        viewWidth: Double,
        viewHeight: Double
    ) {
        precondition(sensorWidth > 0 && sensorHeight > 0)
        precondition(viewWidth > 0 && viewHeight > 0)
        let scale = min(viewWidth / sensorWidth, viewHeight / sensorHeight)
        let width = sensorWidth * scale
        let height = sensorHeight * scale
        imageRect = BodyScannerRect(
            minX: (viewWidth - width) / 2,
            minY: (viewHeight - height) / 2,
            width: width,
            height: height
        )
    }

    func project(normalizedX: Double, normalizedY: Double) -> BodyScannerPoint {
        BodyScannerPoint(
            x: imageRect.minX + normalizedX * imageRect.width,
            y: imageRect.minY + normalizedY * imageRect.height
        )
    }
}

enum BodyScannerSkeletonRole: Sendable {
    case body
    case participantLeft
    case participantRight
}

enum BodyScannerPointShape: String, Sendable {
    case circle
    case triangle
    case square
}

enum BodyScannerLinePattern: String, Sendable {
    case solid
    case dashed
}

struct BodyScannerSkeletonStyle: Equatable, Sendable {
    let colourName: String
    let pointShape: BodyScannerPointShape
    let linePattern: BodyScannerLinePattern

    static func style(for role: BodyScannerSkeletonRole) -> Self {
        switch role {
        case .body:
            Self(colourName: "white", pointShape: .circle, linePattern: .solid)
        case .participantLeft:
            Self(colourName: "amber", pointShape: .triangle, linePattern: .solid)
        case .participantRight:
            Self(colourName: "cyan", pointShape: .square, linePattern: .dashed)
        }
    }
}

struct BodyScannerVisibleCounts: Equatable, Sendable {
    let bodyQualified: Int
    let bodyAvailable: Int
    let leftHandFiniteInFrame: Int
    let rightHandFiniteInFrame: Int
    let leftHandConfidence: Double?
    let rightHandConfidence: Double?

    var summary: String {
        let arm = "Arm joints \(bodyQualified)/6 • emitted \(bodyAvailable)/6"
        guard leftHandConfidence != nil || rightHandConfidence != nil
                || leftHandFiniteInFrame > 0 || rightHandFiniteInFrame > 0 else {
            return "\(arm) · Hands pending"
        }
        return [
            arm,
            "Participant L \(leftHandFiniteInFrame)/21 • hand \(percentage(leftHandConfidence))",
            "Participant R \(rightHandFiniteInFrame)/21 • hand \(percentage(rightHandConfidence))"
        ].joined(separator: " · ")
    }

    private func percentage(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int((max(0, min(1, value)) * 100).rounded()))%"
    }
}

enum BodyScannerTrackingPhase: Equatable, Sendable {
    case searching
    case partial
    case stabilizing
    case qualified(generation: UInt64)
    case frozen(generation: UInt64)
    case stale
    case failed

    var label: String {
        switch self {
        case .searching: "SEARCHING"
        case .partial: "PARTIAL"
        case .stabilizing: "STABILIZING"
        case .qualified: "TRACKING"
        case .frozen: "FROZEN"
        case .stale: "STALE"
        case .failed: "FAILED"
        }
    }

    var displayOpacity: Double {
        switch self {
        case .qualified, .frozen:
            1
        case .partial, .stabilizing:
            0.45
        case .stale:
            0.25
        case .searching, .failed:
            0
        }
    }
}

struct BodyScannerFreezeGuard: Sendable {
    private var qualifiedGeneration: UInt64?

    mutating func update(phase: BodyScannerTrackingPhase) {
        if case .qualified(let generation) = phase {
            qualifiedGeneration = generation
        } else {
            qualifiedGeneration = nil
        }
    }

    func consumeFreeze(generation: UInt64) -> Bool {
        qualifiedGeneration == generation
    }
}

enum BodyScannerAccessibilityID {
    static let entry = "bodyScanner.entry"
    static let intro = "bodyScanner.intro"
    static let consent = "bodyScanner.consent"
    static let continueButton = "bodyScanner.continue"
    static let rotate = "bodyScanner.rotate"
    static let preview = "bodyScanner.preview"
    static let overlay = "bodyScanner.overlay"
    static let guidance = "bodyScanner.guidance"
    static let status = "bodyScanner.status"
    static let counts = "bodyScanner.counts"
    static let depth = "bodyScanner.depth"
    static let freeze = "bodyScanner.freeze"
    static let error = "bodyScanner.error"
    static let retry = "bodyScanner.retry"
    static let frozenSummary = "bodyScanner.frozenSummary"
    static let reset = "bodyScanner.reset"
}
