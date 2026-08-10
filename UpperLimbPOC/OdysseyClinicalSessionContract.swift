import Foundation

enum OdysseyClinicalSessionProtocol {
    static let identifier = "odyssey-clinical-session"
    static let currentVersion = 1
    static let heartbeatIntervalSeconds: TimeInterval = 1
    static let staleAfterSeconds: TimeInterval = 3
    static let maximumMessageAgeSeconds: TimeInterval = 5
    static let maximumFutureSkewSeconds: TimeInterval = 1
    static let maximumRememberedMessageIDs = 64
    static let minimumTrackingConfidence = 0.7
    static let maximumIdentifierLength = 128
    static let maximumDisplayNameLength = 80
    static let maximumDetailLength = 256
    static let disclosure =
        "Reference anatomy for education — not patient-specific imaging, diagnosis, or a validated surgical plan."
}

enum OdysseyClinicalSessionEndpointRole: String, Codable, Equatable, Sendable {
    case clinicianCompanion
    case visionPro
}

struct OdysseyClinicalSessionCapability:
    RawRepresentable,
    Codable,
    Equatable,
    Hashable,
    Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let desiredReveal = Self(rawValue: "desired-reveal")
    static let appliedReveal = Self(rawValue: "applied-reveal")
    static let rendererRoute = Self(rawValue: "renderer-route")
    static let twinTrackingState = Self(rawValue: "twin-tracking-state")
    static let acknowledgment = Self(rawValue: "acknowledgment")
    static let heartbeat = Self(rawValue: "heartbeat")
    static let followArm = Self(rawValue: "follow-arm")
    static let heldPresentation = Self(rawValue: "held-presentation")

    static let requiredList: [Self] = [
        .desiredReveal,
        .appliedReveal,
        .rendererRoute,
        .twinTrackingState,
        .acknowledgment,
        .heartbeat,
        .followArm
    ]

    static let required = Set(requiredList)
}

enum OdysseyClinicalLaterality: String, Codable, Equatable, Sendable {
    case right
}

struct OdysseyClinicalPatientIdentity: Codable, Equatable, Sendable {
    let identifier: String
    let displayName: String
    let isReferenceDemoPatient: Bool

    static let odyssey = Self(
        identifier: "odyssey",
        displayName: "Odyssey",
        isReferenceDemoPatient: true
    )

    var isValid: Bool {
        !identifier.isEmpty
            && identifier.count <= OdysseyClinicalSessionProtocol.maximumIdentifierLength
            && !displayName.isEmpty
            && displayName.count <= OdysseyClinicalSessionProtocol.maximumDisplayNameLength
            && isReferenceDemoPatient
    }
}

struct OdysseyClinicalModelIdentity: Codable, Equatable, Sendable {
    let identifier: String
    let displayName: String
    let laterality: OdysseyClinicalLaterality
    let isReferenceAnatomy: Bool

    static let rightForearmVRT = Self(
        identifier: "right-forearm-vrt-reference",
        displayName: "Right Forearm VRT",
        laterality: .right,
        isReferenceAnatomy: true
    )

    var isValid: Bool {
        !identifier.isEmpty
            && identifier.count <= OdysseyClinicalSessionProtocol.maximumIdentifierLength
            && !displayName.isEmpty
            && displayName.count <= OdysseyClinicalSessionProtocol.maximumDisplayNameLength
            && laterality == .right
            && isReferenceAnatomy
    }
}

struct OdysseyClinicalSessionDescriptor: Codable, Equatable, Sendable {
    let patient: OdysseyClinicalPatientIdentity
    let model: OdysseyClinicalModelIdentity
    let disclosure: String

    static let odysseyRightForearmReference = Self(
        patient: .odyssey,
        model: .rightForearmVRT,
        disclosure: OdysseyClinicalSessionProtocol.disclosure
    )

    var isValid: Bool {
        patient == .odyssey
            && model == .rightForearmVRT
            && disclosure == OdysseyClinicalSessionProtocol.disclosure
    }
}

struct OdysseyClinicalRevealValue: Codable, Equatable, Sendable {
    static let surface = Self(unchecked: 0)
    static let bone = Self(unchecked: 1)

    let value: Double

    init?(validating value: Double) {
        guard value.isFinite, (0 ... 1).contains(value) else { return nil }
        self.value = value
    }

    init(clamping value: Double) {
        precondition(value.isFinite, "Reveal value must be finite")
        self.value = min(max(value, 0), 1)
    }

    private init(unchecked value: Double) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decoded = try container.decode(Double.self)
        guard let value = Self(validating: decoded) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Reveal value must be finite and within 0...1"
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

enum OdysseyTwinRendererRoute: String, Codable, Equatable, Sendable {
    case spatialVRT
    case ctDerivedMeshFallback
}

enum OdysseyTwinTrackingState: String, Codable, Equatable, Sendable {
    case searching
    case live
    case stale
    case failed
}

enum OdysseyTwinPresentationState: String, Codable, Equatable, Sendable {
    case followArm
    case held
}

struct OdysseyClinicalTrackingFrame: Codable, Equatable, Sendable {
    let identifier: String
    let capturedAt: Date
    let confidence: Double

    var isValid: Bool {
        !identifier.isEmpty
            && identifier.count <= OdysseyClinicalSessionProtocol.maximumIdentifierLength
            && capturedAt.timeIntervalSinceReferenceDate.isFinite
            && confidence.isFinite
            && (0 ... 1).contains(confidence)
    }

    var hasSufficientConfidence: Bool {
        isValid && confidence >= OdysseyClinicalSessionProtocol.minimumTrackingConfidence
    }

    func isFresh(
        at now: Date,
        maximumAgeSeconds: TimeInterval = OdysseyClinicalSessionProtocol.staleAfterSeconds
    ) -> Bool {
        guard isValid, maximumAgeSeconds > 0 else { return false }
        let age = now.timeIntervalSince(capturedAt)
        return age <= maximumAgeSeconds
            && age >= -OdysseyClinicalSessionProtocol.maximumFutureSkewSeconds
    }
}

struct OdysseyClinicalDesiredState: Codable, Equatable, Sendable {
    let reveal: OdysseyClinicalRevealValue
    let presentation: OdysseyTwinPresentationState

    static let initial = Self(reveal: .surface, presentation: .followArm)

    func settingReveal(_ value: Double) -> Self {
        Self(
            reveal: OdysseyClinicalRevealValue(clamping: value),
            presentation: presentation
        )
    }

    var isValid: Bool {
        // Held is reserved for AVP-reported stale-pose behavior in v1. A future
        // desired hold command requires explicit capability/version work.
        presentation == .followArm
    }
}

struct OdysseyClinicalDesiredCommand: Codable, Equatable, Sendable {
    let descriptor: OdysseyClinicalSessionDescriptor
    let desiredState: OdysseyClinicalDesiredState

    static func set(_ desiredState: OdysseyClinicalDesiredState) -> Self {
        Self(
            descriptor: .odysseyRightForearmReference,
            desiredState: desiredState
        )
    }

    var isValid: Bool {
        descriptor.isValid && desiredState.isValid
    }
}

enum OdysseyTwinApplicationState: String, Codable, Equatable, Sendable {
    case applied
    case heldStale
    case rejected
}

enum OdysseyClinicalSessionFailureReason: String, Codable, Equatable, Sendable {
    case unsupportedVersion
    case unsupportedCapability
    case invalidSession
    case invalidReveal
    case replayedMessage
    case outOfOrderMessage
    case staleMessage
    case futureTimestamp
    case trackingSearching
    case trackingStale
    case trackingFailed
    case frameMissing
    case frameStale
    case insufficientTrackingConfidence
    case rendererUnavailable
    case transportUnavailable

    var isRecoverable: Bool {
        switch self {
        case .unsupportedVersion, .invalidSession, .invalidReveal:
            false
        case .unsupportedCapability, .replayedMessage, .outOfOrderMessage,
             .staleMessage, .futureTimestamp, .trackingSearching,
             .trackingStale, .trackingFailed, .frameMissing, .frameStale,
             .insufficientTrackingConfidence, .rendererUnavailable,
             .transportUnavailable:
            true
        }
    }
}

struct OdysseyClinicalAppliedState: Codable, Equatable, Sendable {
    let descriptor: OdysseyClinicalSessionDescriptor
    let appliedReveal: OdysseyClinicalRevealValue?
    let rendererRoute: OdysseyTwinRendererRoute?
    let trackingState: OdysseyTwinTrackingState
    let presentation: OdysseyTwinPresentationState?
    let applicationState: OdysseyTwinApplicationState
    let sourceMessageID: UUID?
    let sourceSequence: UInt64?
    let trackingFrame: OdysseyClinicalTrackingFrame?
    let appliedAt: Date
    let failureReason: OdysseyClinicalSessionFailureReason?
    let detail: String?

    var isValid: Bool {
        guard descriptor.isValid,
              appliedAt.timeIntervalSinceReferenceDate.isFinite,
              (detail?.count ?? 0) <= OdysseyClinicalSessionProtocol.maximumDetailLength,
              (sourceMessageID == nil) == (sourceSequence == nil)
        else {
            return false
        }
        if sourceMessageID != nil, (sourceSequence ?? 0) == 0 {
            return false
        }

        switch applicationState {
        case .applied:
            return appliedReveal != nil
                && rendererRoute != nil
                && trackingState == .live
                && presentation == .followArm
                && sourceMessageID != nil
                && (sourceSequence ?? 0) > 0
                && trackingFrame?.hasSufficientConfidence == true
                && trackingFrame?.isFresh(at: appliedAt) == true
                && failureReason == nil
        case .heldStale:
            return appliedReveal != nil
                && rendererRoute != nil
                && trackingState == .stale
                && presentation == .held
                && sourceMessageID != nil
                && (sourceSequence ?? 0) > 0
                && trackingFrame?.hasSufficientConfidence == true
                && failureReason == .trackingStale
        case .rejected:
            return appliedReveal == nil
                && trackingState != .live
                && presentation == nil
                && trackingFrame == nil
                && failureReason != nil
        }
    }
}

struct OdysseyClinicalSessionHandshake: Codable, Equatable, Sendable {
    let endpointRole: OdysseyClinicalSessionEndpointRole
    let supportedProtocolVersions: [Int]
    let capabilities: [OdysseyClinicalSessionCapability]
    let descriptor: OdysseyClinicalSessionDescriptor
    let availableRendererRoutes: [OdysseyTwinRendererRoute]
    let peerDisplayName: String?

    var isValid: Bool {
        !supportedProtocolVersions.isEmpty
            && supportedProtocolVersions.allSatisfy { $0 > 0 }
            && Set(supportedProtocolVersions).count == supportedProtocolVersions.count
            && !capabilities.isEmpty
            && Set(capabilities).count == capabilities.count
            && Set(availableRendererRoutes).count == availableRendererRoutes.count
            && descriptor.isValid
            && (peerDisplayName?.count ?? 0)
                <= OdysseyClinicalSessionProtocol.maximumDisplayNameLength
    }

    func negotiatedCapabilities(
        with localCapabilities: Set<OdysseyClinicalSessionCapability>
    ) -> Set<OdysseyClinicalSessionCapability> {
        Set(capabilities).intersection(localCapabilities)
    }

    func hasRequiredCapabilities(
        supportedBy localCapabilities: Set<OdysseyClinicalSessionCapability>
    ) -> Bool {
        negotiatedCapabilities(with: localCapabilities)
            .isSuperset(of: OdysseyClinicalSessionCapability.required)
    }
}

enum OdysseyClinicalAcknowledgmentDisposition: String, Codable, Equatable, Sendable {
    case applied
    case acceptedPendingTracking
    case rejected
    case ignoredDuplicate
}

struct OdysseyClinicalAcknowledgment: Codable, Equatable, Sendable {
    let acknowledgedMessageID: UUID
    let acknowledgedSequence: UInt64
    let disposition: OdysseyClinicalAcknowledgmentDisposition
    let appliedFrameIdentifier: String?
    let detail: String?

    var isValid: Bool {
        guard acknowledgedSequence > 0,
              (appliedFrameIdentifier?.count ?? 0)
                <= OdysseyClinicalSessionProtocol.maximumIdentifierLength,
              appliedFrameIdentifier?.isEmpty != true,
              (detail?.count ?? 0)
                <= OdysseyClinicalSessionProtocol.maximumDetailLength
        else {
            return false
        }
        switch disposition {
        case .applied:
            return appliedFrameIdentifier != nil
        case .acceptedPendingTracking, .rejected, .ignoredDuplicate:
            return appliedFrameIdentifier == nil
        }
    }
}

enum OdysseyClinicalPeerLiveness: String, Codable, Equatable, Sendable {
    case ready
    case syncing
    case stale
    case error
}

struct OdysseyClinicalHeartbeat: Codable, Equatable, Sendable {
    let endpointRole: OdysseyClinicalSessionEndpointRole
    let liveness: OdysseyClinicalPeerLiveness
    let lastReceivedSequence: UInt64?
    let lastAppliedCommandSequence: UInt64?
    let lastAppliedFrameIdentifier: String?

    var isValid: Bool {
        (lastAppliedFrameIdentifier?.count ?? 0)
            <= OdysseyClinicalSessionProtocol.maximumIdentifierLength
    }
}

struct OdysseyClinicalSessionErrorPayload: Codable, Equatable, Sendable {
    let reason: OdysseyClinicalSessionFailureReason
    let relatedMessageID: UUID?
    let detail: String

    var isRecoverable: Bool { reason.isRecoverable }

    var isValid: Bool {
        !detail.isEmpty
            && detail.count <= OdysseyClinicalSessionProtocol.maximumDetailLength
    }
}

enum OdysseyClinicalSessionPayloadKind: String, Codable, Equatable, Sendable {
    case handshake
    case desiredState
    case appliedState
    case acknowledgment
    case heartbeat
    case error
}

struct OdysseyClinicalSessionPayload: Codable, Equatable, Sendable {
    let kind: OdysseyClinicalSessionPayloadKind
    let handshake: OdysseyClinicalSessionHandshake?
    let desiredCommand: OdysseyClinicalDesiredCommand?
    let appliedState: OdysseyClinicalAppliedState?
    let acknowledgment: OdysseyClinicalAcknowledgment?
    let heartbeat: OdysseyClinicalHeartbeat?
    let error: OdysseyClinicalSessionErrorPayload?

    static func handshake(_ value: OdysseyClinicalSessionHandshake) -> Self {
        Self(kind: .handshake, handshake: value)
    }

    static func desiredState(_ value: OdysseyClinicalDesiredCommand) -> Self {
        Self(kind: .desiredState, desiredCommand: value)
    }

    static func appliedState(_ value: OdysseyClinicalAppliedState) -> Self {
        Self(kind: .appliedState, appliedState: value)
    }

    static func acknowledgment(_ value: OdysseyClinicalAcknowledgment) -> Self {
        Self(kind: .acknowledgment, acknowledgment: value)
    }

    static func heartbeat(_ value: OdysseyClinicalHeartbeat) -> Self {
        Self(kind: .heartbeat, heartbeat: value)
    }

    static func error(_ value: OdysseyClinicalSessionErrorPayload) -> Self {
        Self(kind: .error, error: value)
    }

    private init(
        kind: OdysseyClinicalSessionPayloadKind,
        handshake: OdysseyClinicalSessionHandshake? = nil,
        desiredCommand: OdysseyClinicalDesiredCommand? = nil,
        appliedState: OdysseyClinicalAppliedState? = nil,
        acknowledgment: OdysseyClinicalAcknowledgment? = nil,
        heartbeat: OdysseyClinicalHeartbeat? = nil,
        error: OdysseyClinicalSessionErrorPayload? = nil
    ) {
        self.kind = kind
        self.handshake = handshake
        self.desiredCommand = desiredCommand
        self.appliedState = appliedState
        self.acknowledgment = acknowledgment
        self.heartbeat = heartbeat
        self.error = error
    }

    var isValid: Bool {
        let populatedCount = [
            handshake != nil,
            desiredCommand != nil,
            appliedState != nil,
            acknowledgment != nil,
            heartbeat != nil,
            error != nil
        ].filter { $0 }.count
        guard populatedCount == 1 else { return false }

        switch kind {
        case .handshake:
            return handshake?.isValid == true
        case .desiredState:
            return desiredCommand?.isValid == true
        case .appliedState:
            return appliedState?.isValid == true
        case .acknowledgment:
            return acknowledgment?.isValid == true
        case .heartbeat:
            return heartbeat?.isValid == true
        case .error:
            return error?.isValid == true
        }
    }
}

struct OdysseyClinicalSessionMessage: Codable, Equatable, Sendable {
    let protocolIdentifier: String
    let protocolVersion: Int
    let sessionID: UUID
    let messageID: UUID
    let sequence: UInt64
    let sentAt: Date
    let payload: OdysseyClinicalSessionPayload

    init(
        protocolIdentifier: String = OdysseyClinicalSessionProtocol.identifier,
        protocolVersion: Int = OdysseyClinicalSessionProtocol.currentVersion,
        sessionID: UUID,
        messageID: UUID = UUID(),
        sequence: UInt64,
        sentAt: Date,
        payload: OdysseyClinicalSessionPayload
    ) {
        self.protocolIdentifier = protocolIdentifier
        self.protocolVersion = protocolVersion
        self.sessionID = sessionID
        self.messageID = messageID
        self.sequence = sequence
        self.sentAt = sentAt
        self.payload = payload
    }

    var isStructurallyValid: Bool {
        protocolIdentifier == OdysseyClinicalSessionProtocol.identifier
            && protocolVersion > 0
            && sequence > 0
            && sentAt.timeIntervalSinceReferenceDate.isFinite
            && payload.isValid
    }
}

enum OdysseyClinicalSessionMessageRejection: String, Codable, Equatable, Sendable {
    case unsupportedVersion
    case sessionMismatch
    case invalidPayload
    case stale
    case futureTimestamp
    case replayedMessageID
    case nonIncreasingSequence
}

enum OdysseyClinicalSessionMessageGateResult: Equatable, Sendable {
    case accepted
    case rejected(OdysseyClinicalSessionMessageRejection)
}

struct OdysseyClinicalSessionMessageGate: Sendable {
    let sessionID: UUID
    let maximumAgeSeconds: TimeInterval
    let maximumFutureSkewSeconds: TimeInterval

    private(set) var lastAcceptedSequence: UInt64?
    private var acceptedMessageIDs: [UUID] = []

    init(
        sessionID: UUID,
        maximumAgeSeconds: TimeInterval =
            OdysseyClinicalSessionProtocol.maximumMessageAgeSeconds,
        maximumFutureSkewSeconds: TimeInterval =
            OdysseyClinicalSessionProtocol.maximumFutureSkewSeconds
    ) {
        precondition(maximumAgeSeconds > 0)
        precondition(maximumFutureSkewSeconds >= 0)
        self.sessionID = sessionID
        self.maximumAgeSeconds = maximumAgeSeconds
        self.maximumFutureSkewSeconds = maximumFutureSkewSeconds
    }

    mutating func accept(
        _ message: OdysseyClinicalSessionMessage,
        now: Date
    ) -> OdysseyClinicalSessionMessageGateResult {
        guard message.protocolVersion == OdysseyClinicalSessionProtocol.currentVersion else {
            return .rejected(.unsupportedVersion)
        }
        guard message.sessionID == sessionID else {
            return .rejected(.sessionMismatch)
        }
        guard message.isStructurallyValid else {
            return .rejected(.invalidPayload)
        }

        let age = now.timeIntervalSince(message.sentAt)
        guard age <= maximumAgeSeconds else { return .rejected(.stale) }
        guard age >= -maximumFutureSkewSeconds else {
            return .rejected(.futureTimestamp)
        }
        guard !acceptedMessageIDs.contains(message.messageID) else {
            return .rejected(.replayedMessageID)
        }
        if let lastAcceptedSequence,
           message.sequence <= lastAcceptedSequence {
            return .rejected(.nonIncreasingSequence)
        }

        lastAcceptedSequence = message.sequence
        acceptedMessageIDs.append(message.messageID)
        if acceptedMessageIDs.count
            > OdysseyClinicalSessionProtocol.maximumRememberedMessageIDs {
            acceptedMessageIDs.removeFirst(
                acceptedMessageIDs.count
                    - OdysseyClinicalSessionProtocol.maximumRememberedMessageIDs
            )
        }
        return .accepted
    }
}
