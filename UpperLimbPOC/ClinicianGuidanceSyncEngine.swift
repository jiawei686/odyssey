import Foundation

enum ClinicianGuidanceSyncEffect: Equatable, Sendable {
    case send(ClinicianGuidanceMessage)
}

struct ClinicianGuidanceSyncEngine {
    let role: ClinicianGuidanceEndpointRole
    let localDisplayName: String?

    private(set) var transportConnected = false
    private(set) var handshakeComplete = false
    private(set) var desiredGuidanceState = ClinicianGuidanceState.initial
    private(set) var appliedGuidanceState: ClinicianGuidanceAppliedState?
    private(set) var pendingMessageID: UUID?
    private(set) var lastAcknowledgedAt: Date?
    private(set) var lastError: ClinicianGuidanceErrorPayload?
    private(set) var peerDisplayName: String?
    private(set) var connectionStatus: ClinicianGuidanceConnectionStatus = .disconnected
    private(set) var negotiatedCapabilities: Set<ClinicianGuidanceCapability> = []

    private var activeSessionID: UUID?
    private var outboundSequence: UInt64 = 0
    private var inboundGate: ClinicianGuidanceMessageGate?
    private var lastInboundAt: Date?
    private var lastHeartbeatSentAt: Date?
    private var lastReceivedSequence: UInt64?
    private var lastAppliedCommandSequence: UInt64?
    private var pendingSequence: UInt64?
    private var hasReceivedDesiredCommand = false
    private var awaitingResyncCommand = false
    private var mayAdoptSessionFromHandshake = false
    private var lastCommandMessageID: UUID?
    private var lastCommandSequence: UInt64?
    private var avpTrackingStatus: ClinicianGuidanceTrackingStatus = .unavailable
    private var avpParticipantSide: ClinicianParticipantSide = .unknown
    private var avpTrackingDetail = "Tracked forearm is unavailable"
    private let messageIDProvider: () -> UUID

    init(
        role: ClinicianGuidanceEndpointRole,
        sessionID: UUID = UUID(),
        localDisplayName: String? = nil,
        messageIDProvider: @escaping () -> UUID = UUID.init
    ) {
        self.role = role
        self.localDisplayName = localDisplayName
        self.messageIDProvider = messageIDProvider
        activeSessionID = role == .companion ? sessionID : nil
    }

    var clientState: ClinicianGuidanceClientState {
        ClinicianGuidanceClientState(
            connectionStatus: connectionStatus,
            desiredGuidanceState: desiredGuidanceState,
            appliedGuidanceState: appliedGuidanceState,
            pendingMessageID: pendingMessageID,
            lastAcknowledgedAt: lastAcknowledgedAt,
            lastError: lastError,
            peerDisplayName: peerDisplayName
        )
    }

    var avpRenderedGuidanceState: ClinicianGuidanceState? {
        guard role == .visionPro, hasReceivedDesiredCommand else { return nil }
        return appliedGuidanceState?.state
    }

    mutating func setTransportConnected(
        _ isConnected: Bool,
        now: Date
    ) -> [ClinicianGuidanceSyncEffect] {
        guard transportConnected != isConnected else { return [] }
        transportConnected = isConnected
        lastHeartbeatSentAt = nil

        guard isConnected else {
            handshakeComplete = false
            negotiatedCapabilities = []
            pendingMessageID = nil
            pendingSequence = nil
            lastInboundAt = nil
            connectionStatus = .disconnected
            if role == .visionPro {
                awaitingResyncCommand = true
                mayAdoptSessionFromHandshake = false
                appliedGuidanceState = unavailableAppliedState(
                    trackingStatus: .unavailable,
                    detail: "Companion disconnected; remote guidance is hidden"
                )
            }
            return []
        }

        connectionStatus = role == .companion ? .syncing : .connecting
        lastError = nil
        lastInboundAt = now
        awaitingResyncCommand = role == .visionPro
        mayAdoptSessionFromHandshake = role == .visionPro

        if role == .companion {
            // A reconnected or restarted AVP may restart its outbound sequence.
            // The companion owns the session ID and resets only its inbound gate.
            if let activeSessionID {
                inboundGate = ClinicianGuidanceMessageGate(sessionID: activeSessionID)
            }
            return sendHandshake(now: now)
        }
        return []
    }

    mutating func sendDesiredState(
        _ command: ClinicianGuidanceCommand,
        now: Date
    ) -> [ClinicianGuidanceSyncEffect] {
        guard role == .companion,
              clientState.canSendGuidanceCommands,
              command.isValid else { return [] }
        desiredGuidanceState = command.desiredState
        guard let message = makeMessage(
            payload: .desiredGuidance(command),
            now: now
        ) else { return [] }
        pendingMessageID = message.messageID
        pendingSequence = message.sequence
        connectionStatus = .syncing
        return [.send(message)]
    }

    mutating func receive(
        _ message: ClinicianGuidanceMessage,
        now: Date
    ) -> [ClinicianGuidanceSyncEffect] {
        guard transportConnected else { return [] }

        if role == .visionPro,
           mayAdoptSessionFromHandshake,
           message.payload.kind == .handshake,
           message.payload.handshake?.endpointRole == .companion,
           activeSessionID != message.sessionID {
            adoptCompanionSession(message.sessionID)
        }

        guard let activeSessionID,
              message.sessionID == activeSessionID else {
            return sendError(
                code: .malformedMessage,
                relatedMessageID: message.messageID,
                detail: "Message session does not match the negotiated companion session",
                now: now
            )
        }
        if inboundGate == nil {
            inboundGate = ClinicianGuidanceMessageGate(sessionID: activeSessionID)
        }
        guard var gate = inboundGate else { return [] }
        let gateResult = gate.accept(message, now: now)
        inboundGate = gate
        guard gateResult == .accepted else {
            guard case .rejected(let rejection) = gateResult else { return [] }
            return reject(rejection, message: message, now: now)
        }

        lastInboundAt = now
        lastReceivedSequence = message.sequence
        if role == .visionPro, message.payload.kind == .handshake {
            mayAdoptSessionFromHandshake = false
        }
        if connectionStatus == .stale {
            connectionStatus = pendingMessageID == nil ? .connected : .syncing
        }

        switch message.payload.kind {
        case .handshake:
            guard let handshake = message.payload.handshake else { return [] }
            return receiveHandshake(handshake, now: now)
        case .desiredGuidance:
            guard role == .visionPro,
                  handshakeComplete,
                  let command = message.payload.command else { return [] }
            return receiveDesiredCommand(command, source: message, now: now)
        case .appliedGuidance:
            guard role == .companion,
                  handshakeComplete,
                  let applied = message.payload.appliedState else { return [] }
            appliedGuidanceState = applied
            if pendingMessageID == nil {
                connectionStatus = .connected
            }
            return []
        case .acknowledgment:
            guard role == .companion,
                  handshakeComplete,
                  let acknowledgment = message.payload.acknowledgment else { return [] }
            receiveAcknowledgment(acknowledgment, now: now)
            return []
        case .heartbeat:
            guard handshakeComplete,
                  let heartbeat = message.payload.heartbeat,
                  heartbeat.endpointRole != role else { return [] }
            switch heartbeat.liveness {
            case .ready:
                if pendingMessageID == nil {
                    connectionStatus = .connected
                }
                if role == .visionPro,
                   hasReceivedDesiredCommand,
                   !awaitingResyncCommand {
                    let next = resolvedAVPAppliedState()
                    if next != appliedGuidanceState {
                        appliedGuidanceState = next
                        return sendAppliedState(next, now: now)
                    }
                }
            case .syncing:
                connectionStatus = .syncing
            case .stale:
                connectionStatus = .stale
            case .error:
                connectionStatus = .error
            }
            return []
        case .error:
            guard let error = message.payload.error else { return [] }
            lastError = error
            if error.relatedMessageID == pendingMessageID {
                pendingMessageID = nil
                pendingSequence = nil
            }
            connectionStatus = .error
            return []
        }
    }

    mutating func updateAVPTracking(
        status: ClinicianGuidanceTrackingStatus,
        participantSide: ClinicianParticipantSide,
        detail: String,
        now: Date
    ) -> [ClinicianGuidanceSyncEffect] {
        guard role == .visionPro else { return [] }
        avpTrackingStatus = status
        avpParticipantSide = participantSide
        avpTrackingDetail = String(detail.prefix(256))
        guard hasReceivedDesiredCommand, !awaitingResyncCommand else { return [] }

        let next = resolvedAVPAppliedState()
        guard next != appliedGuidanceState else { return [] }
        appliedGuidanceState = next
        guard transportConnected, handshakeComplete else { return [] }
        return sendAppliedState(next, now: now)
    }

    mutating func tick(now: Date) -> [ClinicianGuidanceSyncEffect] {
        guard transportConnected else { return [] }
        var effects: [ClinicianGuidanceSyncEffect] = []

        if let lastInboundAt,
           now.timeIntervalSince(lastInboundAt) > ClinicianGuidanceProtocol.staleAfterSeconds,
           connectionStatus != .stale {
            connectionStatus = .stale
            if role == .visionPro, hasReceivedDesiredCommand {
                appliedGuidanceState = unavailableAppliedState(
                    trackingStatus: .stale,
                    detail: "Companion heartbeat is stale; remote guidance is hidden"
                )
            }
        }

        guard handshakeComplete else { return effects }
        if lastHeartbeatSentAt == nil
            || now.timeIntervalSince(lastHeartbeatSentAt!)
                >= ClinicianGuidanceProtocol.heartbeatIntervalSeconds {
            lastHeartbeatSentAt = now
            if let heartbeat = makeMessage(
                payload: .heartbeat(
                    ClinicianGuidanceHeartbeat(
                        endpointRole: role,
                        liveness: localLiveness,
                        lastReceivedSequence: lastReceivedSequence,
                        lastAppliedCommandSequence: lastAppliedCommandSequence
                    )
                ),
                now: now
            ) {
                effects.append(.send(heartbeat))
            }
        }
        return effects
    }

    private var localLiveness: ClinicianGuidancePeerLiveness {
        switch connectionStatus {
        case .connected: .ready
        case .connecting, .syncing: .syncing
        case .stale: .stale
        case .disconnected, .error: .error
        }
    }

    private mutating func receiveHandshake(
        _ handshake: ClinicianGuidanceHandshake,
        now: Date
    ) -> [ClinicianGuidanceSyncEffect] {
        guard handshake.endpointRole != role else {
            return sendError(
                code: .malformedMessage,
                relatedMessageID: nil,
                detail: "Peer advertised the same endpoint role",
                now: now
            )
        }
        guard handshake.supportedProtocolVersions.contains(
            ClinicianGuidanceProtocol.currentVersion
        ) else {
            connectionStatus = .error
            return sendError(
                code: .unsupportedVersion,
                relatedMessageID: nil,
                detail: "Peer does not support protocol version 1",
                now: now
            )
        }

        let negotiated = Set(handshake.capabilities)
            .intersection(ClinicianGuidanceCapability.judgeMVP)
        guard negotiated == ClinicianGuidanceCapability.judgeMVP else {
            connectionStatus = .error
            return sendError(
                code: .unsupportedCapability,
                relatedMessageID: nil,
                detail: "Peer is missing required judge-build capabilities",
                now: now
            )
        }

        peerDisplayName = handshake.peerDisplayName
        negotiatedCapabilities = negotiated
        handshakeComplete = true
        lastError = nil
        connectionStatus = .connected

        if role == .visionPro {
            var effects = sendHandshake(now: now)
            let current = appliedGuidanceState ?? unavailableAppliedState(
                trackingStatus: avpTrackingStatus,
                detail: "Awaiting companion guidance resynchronization"
            )
            appliedGuidanceState = current
            effects.append(contentsOf: sendAppliedState(current, now: now))
            return effects
        }

        return sendResynchronizedDesiredState(now: now)
    }

    private mutating func receiveDesiredCommand(
        _ command: ClinicianGuidanceCommand,
        source message: ClinicianGuidanceMessage,
        now: Date
    ) -> [ClinicianGuidanceSyncEffect] {
        guard command.isValid else {
            return sendError(
                code: .malformedMessage,
                relatedMessageID: message.messageID,
                detail: "Desired guidance command is invalid",
                now: now
            )
        }
        desiredGuidanceState = command.desiredState
        hasReceivedDesiredCommand = true
        awaitingResyncCommand = false
        lastCommandMessageID = message.messageID
        lastCommandSequence = message.sequence
        lastAppliedCommandSequence = message.sequence

        let applied = resolvedAVPAppliedState()
        appliedGuidanceState = applied
        let disposition: ClinicianGuidanceAcknowledgmentDisposition =
            applied.applicationStatus == .applied
                ? .applied
                : .acceptedPendingTracking
        var effects = sendAcknowledgment(
            for: message,
            disposition: disposition,
            detail: applied.detail,
            now: now
        )
        effects.append(contentsOf: sendAppliedState(applied, now: now))
        return effects
    }

    private mutating func receiveAcknowledgment(
        _ acknowledgment: ClinicianGuidanceAcknowledgment,
        now: Date
    ) {
        guard acknowledgment.acknowledgedMessageID == pendingMessageID,
              acknowledgment.acknowledgedSequence == pendingSequence else { return }
        pendingMessageID = nil
        pendingSequence = nil
        lastAcknowledgedAt = now
        connectionStatus = .connected
    }

    private mutating func sendHandshake(now: Date) -> [ClinicianGuidanceSyncEffect] {
        guard let message = makeMessage(
            payload: .handshake(
                ClinicianGuidanceHandshake(
                    endpointRole: role,
                    supportedProtocolVersions: [ClinicianGuidanceProtocol.currentVersion],
                    capabilities: ClinicianGuidanceCapability.judgeMVPList,
                    peerDisplayName: localDisplayName
                )
            ),
            now: now
        ) else { return [] }
        return [.send(message)]
    }

    private mutating func sendResynchronizedDesiredState(
        now: Date
    ) -> [ClinicianGuidanceSyncEffect] {
        guard role == .companion,
              pendingMessageID == nil,
              let message = makeMessage(
                  payload: .desiredGuidance(.set(desiredGuidanceState)),
                  now: now
              ) else { return [] }
        pendingMessageID = message.messageID
        pendingSequence = message.sequence
        connectionStatus = .syncing
        return [.send(message)]
    }

    private mutating func sendAcknowledgment(
        for message: ClinicianGuidanceMessage,
        disposition: ClinicianGuidanceAcknowledgmentDisposition,
        detail: String?,
        now: Date
    ) -> [ClinicianGuidanceSyncEffect] {
        guard let acknowledgment = makeMessage(
            payload: .acknowledgment(
                ClinicianGuidanceAcknowledgment(
                    acknowledgedMessageID: message.messageID,
                    acknowledgedSequence: message.sequence,
                    disposition: disposition,
                    detail: detail
                )
            ),
            now: now
        ) else { return [] }
        return [.send(acknowledgment)]
    }

    private mutating func sendAppliedState(
        _ state: ClinicianGuidanceAppliedState,
        now: Date
    ) -> [ClinicianGuidanceSyncEffect] {
        guard let message = makeMessage(
            payload: .appliedGuidance(state),
            now: now
        ) else { return [] }
        return [.send(message)]
    }

    private mutating func sendError(
        code: ClinicianGuidanceErrorCode,
        relatedMessageID: UUID?,
        detail: String,
        now: Date
    ) -> [ClinicianGuidanceSyncEffect] {
        let error = ClinicianGuidanceErrorPayload(
            code: code,
            relatedMessageID: relatedMessageID,
            detail: String(detail.prefix(256))
        )
        lastError = error
        guard let message = makeMessage(payload: .error(error), now: now) else {
            return []
        }
        return [.send(message)]
    }

    private mutating func reject(
        _ rejection: ClinicianGuidanceMessageRejection,
        message: ClinicianGuidanceMessage,
        now: Date
    ) -> [ClinicianGuidanceSyncEffect] {
        let code: ClinicianGuidanceErrorCode
        switch rejection {
        case .unsupportedVersion:
            code = .unsupportedVersion
        case .stale, .futureTimestamp:
            code = .staleMessage
        case .replayedMessageID:
            code = .replayedMessage
        case .nonIncreasingSequence:
            code = .outOfOrderMessage
        case .sessionMismatch, .invalidPayload:
            code = .malformedMessage
        }
        return sendError(
            code: code,
            relatedMessageID: message.messageID,
            detail: "Rejected inbound message: \(rejection.rawValue)",
            now: now
        )
    }

    private mutating func makeMessage(
        payload: ClinicianGuidancePayload,
        now: Date
    ) -> ClinicianGuidanceMessage? {
        guard transportConnected, let activeSessionID else { return nil }
        outboundSequence += 1
        return ClinicianGuidanceMessage(
            sessionID: activeSessionID,
            messageID: messageIDProvider(),
            sequence: outboundSequence,
            sentAt: now,
            payload: payload
        )
    }

    private mutating func adoptCompanionSession(_ sessionID: UUID) {
        activeSessionID = sessionID
        outboundSequence = 0
        inboundGate = ClinicianGuidanceMessageGate(sessionID: sessionID)
        handshakeComplete = false
        negotiatedCapabilities = []
        hasReceivedDesiredCommand = false
        lastCommandMessageID = nil
        lastCommandSequence = nil
        lastAppliedCommandSequence = nil
        appliedGuidanceState = nil
    }

    private func resolvedAVPAppliedState() -> ClinicianGuidanceAppliedState {
        let requiresTracking = desiredGuidanceState.showBone
            || desiredGuidanceState.fracturePosition != nil
            || desiredGuidanceState.showIncisionGuide
        if transportConnected,
           handshakeComplete,
           !awaitingResyncCommand,
           (!requiresTracking || avpTrackingStatus == .live) {
            return ClinicianGuidanceAppliedState(
                state: desiredGuidanceState,
                participantSide: avpParticipantSide,
                trackingStatus: avpTrackingStatus,
                applicationStatus: .applied,
                sourceMessageID: lastCommandMessageID,
                sourceSequence: lastCommandSequence,
                detail: requiresTracking
                    ? "Guidance is attached to the live tracked forearm axis"
                    : "No visible guidance requires tracking"
            )
        }
        return unavailableAppliedState(
            trackingStatus: avpTrackingStatus,
            detail: avpTrackingDetail
        )
    }

    private func unavailableAppliedState(
        trackingStatus: ClinicianGuidanceTrackingStatus,
        detail: String
    ) -> ClinicianGuidanceAppliedState {
        ClinicianGuidanceAppliedState(
            state: ClinicianGuidanceState(
                showBone: false,
                fracturePosition: nil,
                showIncisionGuide: false
            ),
            participantSide: avpParticipantSide,
            trackingStatus: trackingStatus,
            applicationStatus: .notApplied,
            sourceMessageID: lastCommandMessageID,
            sourceSequence: lastCommandSequence,
            detail: String(detail.prefix(256))
        )
    }
}
