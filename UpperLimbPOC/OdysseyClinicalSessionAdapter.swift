import Foundation

private enum OdysseyClinicalFieldUpdate<Value> {
    case keep
    case set(Value)
}

enum OdysseyClinicalSessionConnectionState: String, Codable, Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case syncing
    case stale
    case error
}

struct OdysseyClinicalSessionClientState: Equatable, Sendable {
    let descriptor: OdysseyClinicalSessionDescriptor
    let connectionState: OdysseyClinicalSessionConnectionState
    let desiredState: OdysseyClinicalDesiredState
    let appliedState: OdysseyClinicalAppliedState?
    let pendingMessageID: UUID?
    let pendingSequence: UInt64?
    let lastAcknowledgedAt: Date?
    let lastAppliedAt: Date?
    let negotiatedCapabilities: Set<OdysseyClinicalSessionCapability>
    let peerDisplayName: String?
    let lastError: OdysseyClinicalSessionErrorPayload?

    static let disconnected = Self(
        descriptor: .odysseyRightForearmReference,
        connectionState: .disconnected,
        desiredState: .initial,
        appliedState: nil,
        pendingMessageID: nil,
        pendingSequence: nil,
        lastAcknowledgedAt: nil,
        lastAppliedAt: nil,
        negotiatedCapabilities: [],
        peerDisplayName: nil,
        lastError: nil
    )

    var canSendCommands: Bool {
        connectionState == .connected
            && pendingMessageID == nil
            && pendingSequence == nil
            && negotiatedCapabilities.isSuperset(
                of: OdysseyClinicalSessionCapability.required
            )
    }

    var isPending: Bool {
        pendingMessageID != nil
    }

    var confirmedReveal: OdysseyClinicalRevealValue? {
        guard connectionState == .connected,
              appliedState?.applicationState == .applied,
              appliedState?.trackingState == .live
        else {
            return nil
        }
        return appliedState?.appliedReveal
    }

    var rendererRoute: OdysseyTwinRendererRoute? {
        appliedState?.rendererRoute
    }

    var trackingState: OdysseyTwinTrackingState {
        if connectionState == .stale || connectionState == .disconnected {
            return appliedState == nil ? .searching : .stale
        }
        return appliedState?.trackingState ?? .searching
    }

    var presentationState: OdysseyTwinPresentationState? {
        appliedState?.presentation
    }

    var isDesiredStateConfirmed: Bool {
        !isPending
            && connectionState == .connected
            && confirmedReveal == desiredState.reveal
    }
}

@MainActor
protocol OdysseyClinicalSessionControlling: AnyObject {
    var odysseyClinicalSessionState: OdysseyClinicalSessionClientState { get }

    func setReveal(_ normalizedReveal: Double)
    func retryConnection()
}

struct OdysseyClinicalSessionActionSet {
    let setReveal: (Double) -> Void
    let retry: (() -> Void)?
}

/// A transport-independent reducer used by the production session adapter and
/// by frontend mocks. It never marks desired state as applied: only a valid AVP
/// applied-state message can update `appliedState`.
struct OdysseyClinicalSessionAdapter: Sendable {
    private(set) var state: OdysseyClinicalSessionClientState

    init(state: OdysseyClinicalSessionClientState = .disconnected) {
        self.state = state
    }

    mutating func beginConnecting() {
        state = replacing(
            connectionState: .connecting,
            pendingMessageID: .set(nil),
            pendingSequence: .set(nil),
            negotiatedCapabilities: [],
            peerDisplayName: .set(nil),
            lastError: .set(nil)
        )
    }

    mutating func disconnect(detail: String = "Vision Pro disconnected") {
        state = replacing(
            connectionState: .disconnected,
            pendingMessageID: .set(nil),
            pendingSequence: .set(nil),
            negotiatedCapabilities: [],
            peerDisplayName: .set(nil),
            lastError: .set(OdysseyClinicalSessionErrorPayload(
                reason: .transportUnavailable,
                relatedMessageID: nil,
                detail: bounded(detail)
            ))
        )
    }

    @discardableResult
    mutating func acceptVisionHandshake(
        _ handshake: OdysseyClinicalSessionHandshake
    ) -> Bool {
        guard handshake.isValid, handshake.endpointRole == .visionPro else {
            rejectConnection(
                reason: .invalidSession,
                detail: "Vision Pro advertised an invalid Odyssey session"
            )
            return false
        }
        guard handshake.supportedProtocolVersions.contains(
            OdysseyClinicalSessionProtocol.currentVersion
        ) else {
            rejectConnection(
                reason: .unsupportedVersion,
                detail: "Vision Pro did not negotiate clinical-session version 1"
            )
            return false
        }

        let localCapabilities = OdysseyClinicalSessionCapability.required
        let negotiated = handshake.negotiatedCapabilities(with: localCapabilities)
        guard negotiated.isSuperset(of: OdysseyClinicalSessionCapability.required) else {
            rejectConnection(
                reason: .unsupportedCapability,
                detail: "Vision Pro is missing a required clinical-session capability"
            )
            return false
        }
        guard !handshake.availableRendererRoutes.isEmpty else {
            rejectConnection(
                reason: .rendererUnavailable,
                detail: "Vision Pro reported no available anatomical renderer"
            )
            return false
        }

        state = replacing(
            connectionState: .connected,
            negotiatedCapabilities: negotiated,
            peerDisplayName: .set(handshake.peerDisplayName),
            lastError: .set(nil)
        )
        return true
    }

    /// Creates a single in-flight desired command. A disconnected, stale,
    /// unsupported, invalid, or already-pending state returns `nil` and does
    /// not queue work for a later connection.
    mutating func prepareRevealCommand(
        _ normalizedReveal: Double,
        messageID: UUID,
        sequence: UInt64
    ) -> OdysseyClinicalDesiredCommand? {
        guard state.canSendCommands,
              sequence > 0,
              let reveal = OdysseyClinicalRevealValue(validating: normalizedReveal)
        else {
            return nil
        }

        let desired = OdysseyClinicalDesiredState(
            reveal: reveal,
            presentation: .followArm
        )
        state = replacing(
            connectionState: .syncing,
            desiredState: desired,
            pendingMessageID: .set(messageID),
            pendingSequence: .set(sequence),
            lastError: .set(nil)
        )
        return .set(desired)
    }

    /// ACK records transport/application progress but deliberately does not
    /// synthesize an applied reveal. The separately received AVP snapshot is
    /// the only source of `appliedState` truth.
    @discardableResult
    mutating func receiveAcknowledgment(
        _ acknowledgment: OdysseyClinicalAcknowledgment,
        receivedAt: Date
    ) -> Bool {
        guard acknowledgment.isValid,
              acknowledgment.acknowledgedMessageID == state.pendingMessageID,
              acknowledgment.acknowledgedSequence == state.pendingSequence
        else {
            return false
        }

        switch acknowledgment.disposition {
        case .applied, .acceptedPendingTracking:
            state = replacing(
                lastAcknowledgedAt: .set(receivedAt),
                lastError: .set(nil)
            )
        case .rejected:
            state = replacing(
                connectionState: .connected,
                pendingMessageID: .set(nil),
                pendingSequence: .set(nil),
                lastAcknowledgedAt: .set(receivedAt),
                lastError: .set(OdysseyClinicalSessionErrorPayload(
                    reason: .trackingFailed,
                    relatedMessageID: acknowledgment.acknowledgedMessageID,
                    detail: bounded(acknowledgment.detail ?? "AVP rejected the command")
                ))
            )
        case .ignoredDuplicate:
            state = replacing(
                connectionState: .connected,
                pendingMessageID: .set(nil),
                pendingSequence: .set(nil),
                lastAcknowledgedAt: .set(receivedAt),
                lastError: .set(OdysseyClinicalSessionErrorPayload(
                    reason: .replayedMessage,
                    relatedMessageID: acknowledgment.acknowledgedMessageID,
                    detail: bounded(
                        acknowledgment.detail ?? "AVP ignored a duplicate command"
                    )
                ))
            )
        }
        return true
    }

    /// Accepts either the applied result for the current command or an AVP
    /// snapshot during reconnect when no command is in flight.
    @discardableResult
    mutating func receiveAppliedState(
        _ applied: OdysseyClinicalAppliedState
    ) -> Bool {
        guard applied.isValid,
              state.connectionState == .connected
                || state.connectionState == .syncing
        else {
            return false
        }

        if let pendingMessageID = state.pendingMessageID {
            guard applied.sourceMessageID == pendingMessageID,
                  applied.sourceSequence == state.pendingSequence
            else {
                return false
            }
        }

        let nextConnection: OdysseyClinicalSessionConnectionState =
            applied.applicationState == .rejected ? .error : .connected
        let error: OdysseyClinicalSessionErrorPayload?
        if let reason = applied.failureReason {
            error = OdysseyClinicalSessionErrorPayload(
                reason: reason,
                relatedMessageID: applied.sourceMessageID,
                detail: bounded(applied.detail ?? "AVP could not apply the requested state")
            )
        } else {
            error = nil
        }

        state = replacing(
            connectionState: nextConnection,
            appliedState: .set(applied),
            pendingMessageID: .set(nil),
            pendingSequence: .set(nil),
            lastAppliedAt: .set(applied.appliedAt),
            lastError: .set(error)
        )
        return true
    }

    mutating func markStale(detail: String = "Vision Pro session is stale") {
        state = replacing(
            connectionState: .stale,
            pendingMessageID: .set(nil),
            pendingSequence: .set(nil),
            lastError: .set(OdysseyClinicalSessionErrorPayload(
                reason: .staleMessage,
                relatedMessageID: nil,
                detail: bounded(detail)
            ))
        )
    }

    private mutating func rejectConnection(
        reason: OdysseyClinicalSessionFailureReason,
        detail: String
    ) {
        state = replacing(
            connectionState: .error,
            pendingMessageID: .set(nil),
            pendingSequence: .set(nil),
            negotiatedCapabilities: [],
            peerDisplayName: .set(nil),
            lastError: .set(OdysseyClinicalSessionErrorPayload(
                reason: reason,
                relatedMessageID: nil,
                detail: bounded(detail)
            ))
        )
    }

    private func replacing(
        connectionState: OdysseyClinicalSessionConnectionState? = nil,
        desiredState: OdysseyClinicalDesiredState? = nil,
        appliedState: OdysseyClinicalFieldUpdate<OdysseyClinicalAppliedState?> = .keep,
        pendingMessageID: OdysseyClinicalFieldUpdate<UUID?> = .keep,
        pendingSequence: OdysseyClinicalFieldUpdate<UInt64?> = .keep,
        lastAcknowledgedAt: OdysseyClinicalFieldUpdate<Date?> = .keep,
        lastAppliedAt: OdysseyClinicalFieldUpdate<Date?> = .keep,
        negotiatedCapabilities: Set<OdysseyClinicalSessionCapability>? = nil,
        peerDisplayName: OdysseyClinicalFieldUpdate<String?> = .keep,
        lastError: OdysseyClinicalFieldUpdate<OdysseyClinicalSessionErrorPayload?> = .keep
    ) -> OdysseyClinicalSessionClientState {
        OdysseyClinicalSessionClientState(
            descriptor: state.descriptor,
            connectionState: connectionState ?? state.connectionState,
            desiredState: desiredState ?? state.desiredState,
            appliedState: appliedState.resolving(state.appliedState),
            pendingMessageID: pendingMessageID.resolving(state.pendingMessageID),
            pendingSequence: pendingSequence.resolving(state.pendingSequence),
            lastAcknowledgedAt:
                lastAcknowledgedAt.resolving(state.lastAcknowledgedAt),
            lastAppliedAt: lastAppliedAt.resolving(state.lastAppliedAt),
            negotiatedCapabilities:
                negotiatedCapabilities ?? state.negotiatedCapabilities,
            peerDisplayName: peerDisplayName.resolving(state.peerDisplayName),
            lastError: lastError.resolving(state.lastError)
        )
    }

    private func bounded(_ detail: String) -> String {
        String(detail.prefix(OdysseyClinicalSessionProtocol.maximumDetailLength))
    }
}

private extension OdysseyClinicalFieldUpdate {
    func resolving(_ current: Value) -> Value {
        switch self {
        case .keep:
            current
        case .set(let value):
            value
        }
    }
}
