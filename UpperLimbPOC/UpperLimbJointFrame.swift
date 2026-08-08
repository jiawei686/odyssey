import Foundation

enum UpperLimbLaterality: String, Codable, CaseIterable, Sendable {
    case left
    case right
}

enum UpperLimbJointName: String, Codable, CaseIterable, Sendable {
    case shoulder
    case elbow
    case wrist
    case distalRadius
    case distalUlna
    case palmCenter
    case thumbCMC
    case thumbMCP
    case thumbIP
    case thumbTip
    case indexMCP
    case indexPIP
    case indexDIP
    case indexTip
    case middleMCP
    case middlePIP
    case middleDIP
    case middleTip
    case ringMCP
    case ringPIP
    case ringDIP
    case ringTip
    case littleMCP
    case littlePIP
    case littleDIP
    case littleTip
}

enum UpperLimbCoordinateSpace: String, Codable, Sendable {
    case imagePixels
    case normalizedImage
    case modelRelative
    case iPhoneCamera
    case avpWorld
    case anatomyModel
    case sectionalImage
}

enum UpperLimbCoordinateUnit: String, Codable, Sendable {
    case pixels
    case unitless
    case metres
}

struct UpperLimbJointPosition: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let z: Double?
    let space: UpperLimbCoordinateSpace
    let unit: UpperLimbCoordinateUnit

    var isCoordinateContractValid: Bool {
        guard x.isFinite, y.isFinite, z.map(\.isFinite) ?? true else {
            return false
        }

        switch space {
        case .imagePixels:
            return unit == .pixels && z == nil
        case .normalizedImage:
            return unit == .unitless && z == nil
        case .modelRelative:
            return unit == .unitless && z != nil
        case .iPhoneCamera, .avpWorld, .anatomyModel, .sectionalImage:
            return unit == .metres && z != nil
        }
    }
}

enum UpperLimbConfidenceScope: String, Codable, Sendable {
    case landmark
    case hand
    case unavailable
}

enum UpperLimbDepthSource: String, Codable, Sendable {
    case lidar
    case calibratedMetricModel
    case modelRelative
    case none
}

enum UpperLimbTrackingValidity: String, Codable, Sendable {
    case live
    case partial
    case stale
    case failed
}

enum UpperLimbObservationState: String, Codable, Sendable {
    case observed
    case estimated
    case unavailable
    case ambiguous
}

struct UpperLimbJointObservation: Codable, Equatable, Sendable {
    let laterality: UpperLimbLaterality
    let joint: UpperLimbJointName
    let position: UpperLimbJointPosition
    let confidence: Double?
    let confidenceScope: UpperLimbConfidenceScope
    let depthSource: UpperLimbDepthSource
    let validity: UpperLimbTrackingValidity
    let state: UpperLimbObservationState

    var isTruthful: Bool {
        guard position.isCoordinateContractValid else { return false }
        if let confidence,
           (!confidence.isFinite || !(0...1).contains(confidence)) {
            return false
        }

        switch confidenceScope {
        case .landmark:
            guard confidence != nil else { return false }
        case .hand:
            // MP-HandPose exposes one confidence for the complete hand. It belongs
            // in UpperLimbHandEvidence, never on an individual finger point.
            return false
        case .unavailable:
            guard confidence == nil else { return false }
        }

        if depthSource == .modelRelative,
           position.space != .modelRelative {
            return false
        }
        if position.space == .modelRelative,
           depthSource != .modelRelative {
            return false
        }
        return true
    }
}

struct UpperLimbHandEvidence: Codable, Equatable, Sendable {
    let laterality: UpperLimbLaterality
    let handConfidence: Double
    let handednessConfidence: Double?

    var isTruthful: Bool {
        handConfidence.isFinite && (0...1).contains(handConfidence)
            && (handednessConfidence.map { $0.isFinite && (0...1).contains($0) } ?? true)
    }
}

struct UpperLimbJointFrame: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let sessionID: UUID
    let calibrationID: UUID
    let senderClockID: UUID
    let sequence: UInt64
    let capturedAtMonotonic: TimeInterval
    let observations: [UpperLimbJointObservation]
    let handEvidence: [UpperLimbHandEvidence]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        sessionID: UUID,
        calibrationID: UUID,
        senderClockID: UUID,
        sequence: UInt64,
        capturedAtMonotonic: TimeInterval,
        observations: [UpperLimbJointObservation],
        handEvidence: [UpperLimbHandEvidence] = []
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.calibrationID = calibrationID
        self.senderClockID = senderClockID
        self.sequence = sequence
        self.capturedAtMonotonic = capturedAtMonotonic
        self.observations = observations
        self.handEvidence = handEvidence
    }

    var isTruthful: Bool {
        schemaVersion == Self.currentSchemaVersion
            && capturedAtMonotonic.isFinite
            && capturedAtMonotonic >= 0
            && observations.allSatisfy(\.isTruthful)
            && handEvidence.allSatisfy(\.isTruthful)
            && Set(handEvidence.map(\.laterality)).count == handEvidence.count
    }
}

enum UpperLimbJointFrameRejection: String, Codable, Equatable, Sendable {
    case unsupportedSchema
    case sessionMismatch
    case calibrationMismatch
    case clockMismatch
    case nonIncreasingSequence
    case stale
    case futureTimestamp
    case invalidPayload
}

enum UpperLimbJointFrameGateResult: Equatable, Sendable {
    case accepted
    case rejected(UpperLimbJointFrameRejection)
}

struct UpperLimbJointFrameGate: Sendable {
    let sessionID: UUID
    let calibrationID: UUID
    let senderClockID: UUID
    let senderToReceiverClockOffsetSeconds: TimeInterval
    let maximumAgeSeconds: TimeInterval
    let maximumFutureSkewSeconds: TimeInterval

    private(set) var lastAcceptedSequence: UInt64?

    init(
        sessionID: UUID,
        calibrationID: UUID,
        senderClockID: UUID,
        senderToReceiverClockOffsetSeconds: TimeInterval,
        maximumAgeSeconds: TimeInterval,
        maximumFutureSkewSeconds: TimeInterval = 0.05
    ) {
        precondition(maximumAgeSeconds > 0)
        precondition(maximumFutureSkewSeconds >= 0)
        self.sessionID = sessionID
        self.calibrationID = calibrationID
        self.senderClockID = senderClockID
        self.senderToReceiverClockOffsetSeconds = senderToReceiverClockOffsetSeconds
        self.maximumAgeSeconds = maximumAgeSeconds
        self.maximumFutureSkewSeconds = maximumFutureSkewSeconds
    }

    mutating func accept(
        _ frame: UpperLimbJointFrame,
        now receiverMonotonicTime: TimeInterval
    ) -> UpperLimbJointFrameGateResult {
        guard frame.schemaVersion == UpperLimbJointFrame.currentSchemaVersion else {
            return .rejected(.unsupportedSchema)
        }
        guard frame.sessionID == sessionID else {
            return .rejected(.sessionMismatch)
        }
        guard frame.calibrationID == calibrationID else {
            return .rejected(.calibrationMismatch)
        }
        guard frame.senderClockID == senderClockID else {
            return .rejected(.clockMismatch)
        }
        guard frame.isTruthful,
              receiverMonotonicTime.isFinite,
              senderToReceiverClockOffsetSeconds.isFinite else {
            return .rejected(.invalidPayload)
        }
        if let lastAcceptedSequence,
           frame.sequence <= lastAcceptedSequence {
            return .rejected(.nonIncreasingSequence)
        }

        let capturedInReceiverClock = frame.capturedAtMonotonic
            + senderToReceiverClockOffsetSeconds
        let age = receiverMonotonicTime - capturedInReceiverClock
        guard age <= maximumAgeSeconds else {
            return .rejected(.stale)
        }
        guard age >= -maximumFutureSkewSeconds else {
            return .rejected(.futureTimestamp)
        }

        lastAcceptedSequence = frame.sequence
        return .accepted
    }
}
