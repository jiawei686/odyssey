import Foundation

enum ClinicianGuidanceProtocol {
    static let currentVersion = 1
    static let heartbeatIntervalSeconds: TimeInterval = 1
    static let staleAfterSeconds: TimeInterval = 3
    static let maximumMessageAgeSeconds: TimeInterval = 5
    static let maximumFutureSkewSeconds: TimeInterval = 1
    static let maximumRememberedMessageIDs = 64
}

enum ClinicianGuidanceEndpointRole: String, Codable, Equatable, Sendable {
    case companion
    case visionPro
}

struct ClinicianGuidanceCapability: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.singleValueContainer()
        rawValue = try values.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.singleValueContainer()
        try values.encode(rawValue)
    }

    static let desiredGuidance = Self(rawValue: "desired-guidance")
    static let appliedGuidance = Self(rawValue: "applied-guidance")
    static let acknowledgment = Self(rawValue: "acknowledgment")
    static let heartbeat = Self(rawValue: "heartbeat")
    static let normalizedForearmPosition = Self(rawValue: "normalized-forearm-position")
    static let presetIncisionGuide = Self(rawValue: "preset-incision-guide")
    static let clearGuidance = Self(rawValue: "clear-guidance")

    static let judgeMVPList: [Self] = [
        .desiredGuidance,
        .appliedGuidance,
        .acknowledgment,
        .heartbeat,
        .normalizedForearmPosition,
        .presetIncisionGuide,
        .clearGuidance
    ]

    static let judgeMVP = Set(judgeMVPList)
}

enum ClinicianParticipantSide: String, Codable, Equatable, Sendable {
    case unknown
    case left
    case right
}

struct ClinicianForearmPosition: Codable, Equatable, Sendable {
    static let proximal = Self(unchecked: 0)
    static let midpoint = Self(unchecked: 0.5)
    static let distal = Self(unchecked: 1)

    let value: Double

    init?(validating value: Double) {
        guard value.isFinite, (0...1).contains(value) else { return nil }
        self.value = value
    }

    init(clamping value: Double) {
        precondition(value.isFinite, "Forearm position must be finite")
        self.value = min(max(value, 0), 1)
    }

    private init(unchecked value: Double) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.singleValueContainer()
        let decoded = try values.decode(Double.self)
        guard let position = Self(validating: decoded) else {
            throw DecodingError.dataCorruptedError(
                in: values,
                debugDescription: "Forearm position must be finite and within 0...1"
            )
        }
        self = position
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.singleValueContainer()
        try values.encode(value)
    }
}

struct ClinicianGuidanceState: Codable, Equatable, Sendable {
    let showBone: Bool
    let fracturePosition: ClinicianForearmPosition?
    let showIncisionGuide: Bool

    static let initial = Self(
        showBone: true,
        fracturePosition: nil,
        showIncisionGuide: false
    )

    var isValid: Bool {
        !showIncisionGuide || fracturePosition != nil
    }

    func settingBoneVisible(_ isVisible: Bool) -> Self {
        Self(
            showBone: isVisible,
            fracturePosition: fracturePosition,
            showIncisionGuide: showIncisionGuide
        )
    }

    func settingFracturePosition(_ value: Double) -> Self {
        Self(
            showBone: showBone,
            fracturePosition: ClinicianForearmPosition(clamping: value),
            showIncisionGuide: showIncisionGuide
        )
    }

    func settingIncisionGuideVisible(_ isVisible: Bool) -> Self {
        Self(
            showBone: showBone,
            fracturePosition: isVisible
                ? (fracturePosition ?? .midpoint)
                : fracturePosition,
            showIncisionGuide: isVisible
        )
    }

    func clearingGuidance() -> Self {
        Self(
            showBone: showBone,
            fracturePosition: nil,
            showIncisionGuide: false
        )
    }
}

enum ClinicianGuidanceCommandAction: String, Codable, Equatable, Sendable {
    case setGuidance
    case clearGuidance
}

struct ClinicianGuidanceCommand: Codable, Equatable, Sendable {
    let action: ClinicianGuidanceCommandAction
    let desiredState: ClinicianGuidanceState

    static func set(_ desiredState: ClinicianGuidanceState) -> Self {
        Self(action: .setGuidance, desiredState: desiredState)
    }

    static func clear(preservingBoneVisible isVisible: Bool) -> Self {
        Self(
            action: .clearGuidance,
            desiredState: ClinicianGuidanceState(
                showBone: isVisible,
                fracturePosition: nil,
                showIncisionGuide: false
            )
        )
    }

    var isValid: Bool {
        guard desiredState.isValid else { return false }
        switch action {
        case .setGuidance:
            return true
        case .clearGuidance:
            return desiredState.fracturePosition == nil
                && !desiredState.showIncisionGuide
        }
    }
}

enum ClinicianGuidanceTrackingStatus: String, Codable, Equatable, Sendable {
    case live
    case stale
    case unavailable
    case failed
}

enum ClinicianGuidanceApplicationStatus: String, Codable, Equatable, Sendable {
    case applied
    case partiallyApplied
    case notApplied
}

struct ClinicianGuidanceAppliedState: Codable, Equatable, Sendable {
    let state: ClinicianGuidanceState
    let participantSide: ClinicianParticipantSide
    let trackingStatus: ClinicianGuidanceTrackingStatus
    let applicationStatus: ClinicianGuidanceApplicationStatus
    let sourceMessageID: UUID?
    let sourceSequence: UInt64?
    let detail: String?

    var isValid: Bool {
        state.isValid
            && ((sourceMessageID == nil) == (sourceSequence == nil))
            && (detail?.count ?? 0) <= 256
    }
}

struct ClinicianGuidanceHandshake: Codable, Equatable, Sendable {
    let endpointRole: ClinicianGuidanceEndpointRole
    let supportedProtocolVersions: [Int]
    let capabilities: [ClinicianGuidanceCapability]
    let peerDisplayName: String?

    var isValid: Bool {
        !supportedProtocolVersions.isEmpty
            && supportedProtocolVersions.allSatisfy { $0 > 0 }
            && Set(supportedProtocolVersions).count == supportedProtocolVersions.count
            && !capabilities.isEmpty
            && Set(capabilities).count == capabilities.count
            && (peerDisplayName?.count ?? 0) <= 80
    }

    func unsupportedCapabilities(
        supported: Set<ClinicianGuidanceCapability>
    ) -> Set<ClinicianGuidanceCapability> {
        Set(capabilities).subtracting(supported)
    }
}

enum ClinicianGuidanceAcknowledgmentDisposition: String, Codable, Equatable, Sendable {
    case applied
    case acceptedPendingTracking
    case ignoredDuplicate
    case rejected
}

struct ClinicianGuidanceAcknowledgment: Codable, Equatable, Sendable {
    let acknowledgedMessageID: UUID
    let acknowledgedSequence: UInt64
    let disposition: ClinicianGuidanceAcknowledgmentDisposition
    let detail: String?

    var isValid: Bool {
        acknowledgedSequence > 0 && (detail?.count ?? 0) <= 256
    }
}

enum ClinicianGuidancePeerLiveness: String, Codable, Equatable, Sendable {
    case ready
    case syncing
    case stale
    case error
}

struct ClinicianGuidanceHeartbeat: Codable, Equatable, Sendable {
    let endpointRole: ClinicianGuidanceEndpointRole
    let liveness: ClinicianGuidancePeerLiveness
    let lastReceivedSequence: UInt64?
    let lastAppliedCommandSequence: UInt64?
}

enum ClinicianGuidanceErrorCode: String, Codable, Equatable, Sendable {
    case unsupportedVersion
    case unsupportedCapability
    case malformedMessage
    case staleMessage
    case replayedMessage
    case outOfOrderMessage
    case trackingUnavailable
    case mappingUnavailable
    case transportUnavailable

    var isRecoverable: Bool {
        switch self {
        case .malformedMessage, .unsupportedVersion:
            false
        case .unsupportedCapability, .staleMessage, .replayedMessage,
             .outOfOrderMessage, .trackingUnavailable, .mappingUnavailable,
             .transportUnavailable:
            true
        }
    }
}

struct ClinicianGuidanceErrorPayload: Codable, Equatable, Sendable {
    let code: ClinicianGuidanceErrorCode
    let relatedMessageID: UUID?
    let detail: String

    var isRecoverable: Bool { code.isRecoverable }

    var isValid: Bool {
        !detail.isEmpty && detail.count <= 256
    }
}

enum ClinicianGuidancePayloadKind: String, Codable, Equatable, Sendable {
    case handshake
    case desiredGuidance
    case appliedGuidance
    case acknowledgment
    case heartbeat
    case error
}

struct ClinicianGuidancePayload: Codable, Equatable, Sendable {
    let kind: ClinicianGuidancePayloadKind
    let handshake: ClinicianGuidanceHandshake?
    let command: ClinicianGuidanceCommand?
    let appliedState: ClinicianGuidanceAppliedState?
    let acknowledgment: ClinicianGuidanceAcknowledgment?
    let heartbeat: ClinicianGuidanceHeartbeat?
    let error: ClinicianGuidanceErrorPayload?

    static func handshake(_ value: ClinicianGuidanceHandshake) -> Self {
        Self(kind: .handshake, handshake: value)
    }

    static func desiredGuidance(_ value: ClinicianGuidanceCommand) -> Self {
        Self(kind: .desiredGuidance, command: value)
    }

    static func appliedGuidance(_ value: ClinicianGuidanceAppliedState) -> Self {
        Self(kind: .appliedGuidance, appliedState: value)
    }

    static func acknowledgment(_ value: ClinicianGuidanceAcknowledgment) -> Self {
        Self(kind: .acknowledgment, acknowledgment: value)
    }

    static func heartbeat(_ value: ClinicianGuidanceHeartbeat) -> Self {
        Self(kind: .heartbeat, heartbeat: value)
    }

    static func error(_ value: ClinicianGuidanceErrorPayload) -> Self {
        Self(kind: .error, error: value)
    }

    private init(
        kind: ClinicianGuidancePayloadKind,
        handshake: ClinicianGuidanceHandshake? = nil,
        command: ClinicianGuidanceCommand? = nil,
        appliedState: ClinicianGuidanceAppliedState? = nil,
        acknowledgment: ClinicianGuidanceAcknowledgment? = nil,
        heartbeat: ClinicianGuidanceHeartbeat? = nil,
        error: ClinicianGuidanceErrorPayload? = nil
    ) {
        self.kind = kind
        self.handshake = handshake
        self.command = command
        self.appliedState = appliedState
        self.acknowledgment = acknowledgment
        self.heartbeat = heartbeat
        self.error = error
    }

    var isStructurallyValid: Bool {
        let populatedCount = [
            handshake != nil,
            command != nil,
            appliedState != nil,
            acknowledgment != nil,
            heartbeat != nil,
            error != nil
        ].filter { $0 }.count
        guard populatedCount == 1 else { return false }

        switch kind {
        case .handshake:
            return handshake?.isValid == true
        case .desiredGuidance:
            return command?.isValid == true
        case .appliedGuidance:
            return appliedState?.isValid == true
        case .acknowledgment:
            return acknowledgment?.isValid == true
        case .heartbeat:
            return heartbeat != nil
        case .error:
            return error?.isValid == true
        }
    }
}

struct ClinicianGuidanceMessage: Codable, Equatable, Sendable {
    let protocolVersion: Int
    let sessionID: UUID
    let messageID: UUID
    let sequence: UInt64
    let sentAt: Date
    let payload: ClinicianGuidancePayload

    init(
        protocolVersion: Int = ClinicianGuidanceProtocol.currentVersion,
        sessionID: UUID,
        messageID: UUID = UUID(),
        sequence: UInt64,
        sentAt: Date,
        payload: ClinicianGuidancePayload
    ) {
        self.protocolVersion = protocolVersion
        self.sessionID = sessionID
        self.messageID = messageID
        self.sequence = sequence
        self.sentAt = sentAt
        self.payload = payload
    }

    var isStructurallyValid: Bool {
        protocolVersion > 0 && sequence > 0 && payload.isStructurallyValid
    }
}

enum ClinicianGuidanceMessageRejection: String, Codable, Equatable, Sendable {
    case unsupportedVersion
    case sessionMismatch
    case invalidPayload
    case stale
    case futureTimestamp
    case replayedMessageID
    case nonIncreasingSequence
}

enum ClinicianGuidanceMessageGateResult: Equatable, Sendable {
    case accepted
    case rejected(ClinicianGuidanceMessageRejection)
}

struct ClinicianGuidanceMessageGate: Sendable {
    let sessionID: UUID
    let maximumAgeSeconds: TimeInterval
    let maximumFutureSkewSeconds: TimeInterval

    private(set) var lastAcceptedSequence: UInt64?
    private var acceptedMessageIDs: [UUID] = []

    init(
        sessionID: UUID,
        maximumAgeSeconds: TimeInterval = ClinicianGuidanceProtocol.maximumMessageAgeSeconds,
        maximumFutureSkewSeconds: TimeInterval = ClinicianGuidanceProtocol.maximumFutureSkewSeconds
    ) {
        precondition(maximumAgeSeconds > 0)
        precondition(maximumFutureSkewSeconds >= 0)
        self.sessionID = sessionID
        self.maximumAgeSeconds = maximumAgeSeconds
        self.maximumFutureSkewSeconds = maximumFutureSkewSeconds
    }

    mutating func accept(
        _ message: ClinicianGuidanceMessage,
        now: Date
    ) -> ClinicianGuidanceMessageGateResult {
        guard message.protocolVersion == ClinicianGuidanceProtocol.currentVersion else {
            return .rejected(.unsupportedVersion)
        }
        guard message.sessionID == sessionID else {
            return .rejected(.sessionMismatch)
        }
        guard message.isStructurallyValid else {
            return .rejected(.invalidPayload)
        }

        let age = now.timeIntervalSince(message.sentAt)
        guard age <= maximumAgeSeconds else {
            return .rejected(.stale)
        }
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
        if acceptedMessageIDs.count > ClinicianGuidanceProtocol.maximumRememberedMessageIDs {
            acceptedMessageIDs.removeFirst(
                acceptedMessageIDs.count - ClinicianGuidanceProtocol.maximumRememberedMessageIDs
            )
        }
        return .accepted
    }
}

enum ClinicianGuidanceConnectionStatus: String, Codable, Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case syncing
    case stale
    case error
}

struct ClinicianGuidanceClientState: Equatable, Sendable {
    let connectionStatus: ClinicianGuidanceConnectionStatus
    let desiredGuidanceState: ClinicianGuidanceState
    let appliedGuidanceState: ClinicianGuidanceAppliedState?
    let pendingMessageID: UUID?
    let lastAcknowledgedAt: Date?
    let lastError: ClinicianGuidanceErrorPayload?
    let peerDisplayName: String?

    var participantSide: ClinicianParticipantSide {
        appliedGuidanceState?.participantSide ?? .unknown
    }

    var canSendGuidanceCommands: Bool {
        connectionStatus == .connected && pendingMessageID == nil
    }
}

@MainActor
protocol ClinicianGuidanceControlling: AnyObject {
    var clinicianGuidanceState: ClinicianGuidanceClientState { get }

    func setBoneVisible(_ isVisible: Bool)
    func setFracturePosition(_ normalizedPosition: Double)
    func setIncisionGuideVisible(_ isVisible: Bool)
    func clearGuidance()
    func retryConnection()
}

struct ClinicianGuidanceActionSet {
    let setBoneVisible: (Bool) -> Void
    let setFracturePosition: (Double) -> Void
    let setIncisionGuideVisible: (Bool) -> Void
    let clearGuidance: () -> Void
    let retry: (() -> Void)?
}
