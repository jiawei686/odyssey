import Foundation

enum UpperLimbIntegrationPhase: String, Codable, Equatable, Sendable {
    case awaitingCalibration
    case insufficient
    case partial
    case axisOnly
    case fullFrame
    case stale
    case failed
}

/// Authority established by the separate device-calibration exchange.
/// Packet contents must never be used to manufacture these trusted values.
struct UpperLimbCalibrationAuthority: Equatable, Sendable {
    let sessionID: UUID
    let calibrationID: UUID
    let senderClockID: UUID
    let senderToReceiverClockOffsetSeconds: TimeInterval

    var isValid: Bool {
        senderToReceiverClockOffsetSeconds.isFinite
    }
}

struct UpperLimbIntegrationState: Sendable {
    private let maximumAgeSeconds: TimeInterval
    private var gate: UpperLimbJointFrameGate?
    private var laterality: UpperLimbLaterality?
    private var model: SpatialForearmModelDefinition?
    private var lastAcceptedAtMonotonic: TimeInterval?

    private(set) var phase: UpperLimbIntegrationPhase = .awaitingCalibration
    private(set) var commonRoot: SpatialCommonRootTransform?
    private(set) var lastRejection: UpperLimbJointFrameRejection?

    init(maximumAgeSeconds: TimeInterval = 0.25) {
        precondition(maximumAgeSeconds > 0)
        self.maximumAgeSeconds = maximumAgeSeconds
    }

    var displayOpacity: Double {
        switch phase {
        case .axisOnly, .fullFrame:
            1
        case .partial:
            0.45
        case .stale:
            0.25
        case .awaitingCalibration, .insufficient, .failed:
            0
        }
    }

    mutating func activate(
        authority: UpperLimbCalibrationAuthority,
        laterality: UpperLimbLaterality,
        model: SpatialForearmModelDefinition
    ) {
        guard authority.isValid else {
            fail(reason: .invalidPayload)
            return
        }

        // A calibration exchange—not an observation packet—must measure the
        // sender clock offset and authorize the active IDs before activation.
        gate = UpperLimbJointFrameGate(
            sessionID: authority.sessionID,
            calibrationID: authority.calibrationID,
            senderClockID: authority.senderClockID,
            senderToReceiverClockOffsetSeconds: authority.senderToReceiverClockOffsetSeconds,
            maximumAgeSeconds: maximumAgeSeconds
        )
        self.laterality = laterality
        self.model = model
        phase = .insufficient
        commonRoot = nil
        lastRejection = nil
        lastAcceptedAtMonotonic = nil
    }

    mutating func consume(
        _ frame: UpperLimbJointFrame,
        receivedAtMonotonic: TimeInterval
    ) {
        guard var activeGate = gate,
              let laterality,
              let model else {
            phase = .awaitingCalibration
            commonRoot = nil
            return
        }

        let gateResult = activeGate.accept(
            frame,
            now: receivedAtMonotonic
        )
        gate = activeGate

        switch gateResult {
        case .accepted:
            lastRejection = nil
            lastAcceptedAtMonotonic = receivedAtMonotonic
            let result = SpatialJointBridge.integrateAccepted(
                frame: frame,
                gateResult: gateResult,
                laterality: laterality,
                model: model
            )
            commonRoot = result.commonRoot
            switch result.registrationState {
            case .fullFrame:
                phase = .fullFrame
            case .axisOnly:
                phase = .axisOnly
            case .insufficient:
                phase = result.acceptedJointCount > 0 ? .partial : .insufficient
            }
        case .rejected(let rejection):
            lastRejection = rejection
            if rejection == .stale {
                phase = .stale
            } else {
                phase = .failed
                commonRoot = nil
            }
        }
    }

    mutating func refresh(now: TimeInterval) {
        guard let lastAcceptedAtMonotonic else { return }
        if now - lastAcceptedAtMonotonic > maximumAgeSeconds,
           commonRoot != nil {
            phase = .stale
            lastRejection = .stale
        }
    }

    mutating func fail(reason: UpperLimbJointFrameRejection) {
        phase = .failed
        commonRoot = nil
        lastRejection = reason
    }
}
