import Foundation

@main
enum ClinicianGuidanceSyncCheck {
    static func main() throws {
        try handshakeAppliesDesiredStateAndKeepsOneCommandInFlight()
        try unavailableTrackingAcknowledgesPendingThenPublishesLiveState()
        try capabilityNegotiationFailsClosedWithoutBlockingUnknownExtras()
        try negotiatedConnectionCannotSwapSessionsBeforeResync()
        try replayAndOutOfOrderCommandsFailClosed()
        try reconnectResendsTheLatestDesiredSnapshot()
        try stalePeerHidesAVPGuidance()
        print("Clinician-guidance synchronization checks passed")
    }

    private static func negotiatedConnectionCannotSwapSessionsBeforeResync() throws {
        let now = Date(timeIntervalSince1970: 2_750)
        var pair = try connectedPair(now: now, seed: 275)
        let replacementSessionID = UUID(
            uuidString: "00000000-0000-0000-0000-000000002799"
        )!
        let replacement = ClinicianGuidanceMessage(
            sessionID: replacementSessionID,
            messageID: UUID(uuidString: "00000000-0000-0000-0000-000000002798")!,
            sequence: 1,
            sentAt: now,
            payload: .handshake(
                ClinicianGuidanceHandshake(
                    endpointRole: .companion,
                    supportedProtocolVersions: [1],
                    capabilities: ClinicianGuidanceCapability.judgeMVPList,
                    peerDisplayName: "Replacement peer"
                )
            )
        )
        let rejected = pair.vision.receive(replacement, now: now)
        try require(
            try message(of: .error, in: rejected).payload.error?.code
                == .malformedMessage,
            "a negotiated connection must not replace its session before resync"
        )
        let originalResponse = pair.vision.receive(pair.pendingDesired, now: now)
        _ = try message(of: .acknowledgment, in: originalResponse)
    }

    private static func capabilityNegotiationFailsClosedWithoutBlockingUnknownExtras() throws {
        let now = Date(timeIntervalSince1970: 2_500)
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000002500")!
        var missingCapabilityVision = makeEngine(role: .visionPro, seed: 250)
        _ = missingCapabilityVision.setTransportConnected(true, now: now)
        let missing = ClinicianGuidanceMessage(
            sessionID: sessionID,
            messageID: UUID(uuidString: "00000000-0000-0000-0000-000000002501")!,
            sequence: 1,
            sentAt: now,
            payload: .handshake(
                ClinicianGuidanceHandshake(
                    endpointRole: .companion,
                    supportedProtocolVersions: [1],
                    capabilities: [.heartbeat],
                    peerDisplayName: "Incomplete peer"
                )
            )
        )
        let rejected = missingCapabilityVision.receive(missing, now: now)
        try require(
            try message(of: .error, in: rejected).payload.error?.code
                == .unsupportedCapability,
            "missing judge-build capabilities must fail closed"
        )
        try require(
            !missingCapabilityVision.handshakeComplete,
            "incomplete handshake must not enable guidance"
        )

        var futureAwareVision = makeEngine(role: .visionPro, seed: 260)
        _ = futureAwareVision.setTransportConnected(true, now: now)
        let unknown = ClinicianGuidanceCapability(rawValue: "future-capability")
        let complete = ClinicianGuidanceMessage(
            sessionID: sessionID,
            messageID: UUID(uuidString: "00000000-0000-0000-0000-000000002502")!,
            sequence: 1,
            sentAt: now,
            payload: .handshake(
                ClinicianGuidanceHandshake(
                    endpointRole: .companion,
                    supportedProtocolVersions: [1],
                    capabilities: ClinicianGuidanceCapability.judgeMVPList + [unknown],
                    peerDisplayName: "Future peer"
                )
            )
        )
        let accepted = futureAwareVision.receive(complete, now: now)
        try require(
            futureAwareVision.handshakeComplete,
            "unknown extra capabilities must not break compatible negotiation"
        )
        _ = try message(of: .handshake, in: accepted)
    }

    private static func handshakeAppliesDesiredStateAndKeepsOneCommandInFlight() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        var companion = makeEngine(role: .companion, seed: 10)
        var vision = makeEngine(role: .visionPro, seed: 100)
        _ = vision.setTransportConnected(true, now: now)
        let companionHandshake = try onlyMessage(
            companion.setTransportConnected(true, now: now)
        )
        let visionHandshakeEffects = vision.receive(companionHandshake, now: now)
        let visionHandshake = try message(
            of: .handshake,
            in: visionHandshakeEffects
        )
        let initialApplied = try message(
            of: .appliedGuidance,
            in: visionHandshakeEffects
        )
        let desiredEffects = companion.receive(visionHandshake, now: now)
        _ = companion.receive(initialApplied, now: now)
        let desired = try message(of: .desiredGuidance, in: desiredEffects)

        try require(
            companion.clientState.pendingMessageID == desired.messageID,
            "handshake must create exactly one resynchronization command"
        )
        try require(
            companion.sendDesiredState(
                .set(.initial.settingFracturePosition(0.8)),
                now: now
            ).isEmpty,
            "a second command must not queue while one is in flight"
        )

        _ = vision.updateAVPTracking(
            status: .live,
            participantSide: .left,
            detail: "live",
            now: now
        )
        let applicationEffects = vision.receive(desired, now: now)
        let acknowledgment = try message(
            of: .acknowledgment,
            in: applicationEffects
        )
        let applied = try message(
            of: .appliedGuidance,
            in: applicationEffects
        )
        _ = companion.receive(acknowledgment, now: now)
        _ = companion.receive(applied, now: now)

        try require(
            companion.clientState.pendingMessageID == nil,
            "matching ACK must clear the single in-flight command"
        )
        try require(
            companion.clientState.appliedGuidanceState?.state
                == companion.clientState.desiredGuidanceState,
            "AVP applied state must converge with companion intent"
        )
        try require(
            companion.clientState.participantSide == .left,
            "AVP must remain authoritative for participant side"
        )
    }

    private static func unavailableTrackingAcknowledgesPendingThenPublishesLiveState() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        var pair = try connectedPair(now: now, seed: 200)
        let desired = pair.pendingDesired
        let pendingEffects = pair.vision.receive(desired, now: now)
        let acknowledgment = try message(
            of: .acknowledgment,
            in: pendingEffects
        )
        try require(
            acknowledgment.payload.acknowledgment?.disposition
                == .acceptedPendingTracking,
            "valid intent must be accepted but not falsely reported applied without tracking"
        )
        let unavailable = try message(
            of: .appliedGuidance,
            in: pendingEffects
        )
        try require(
            unavailable.payload.appliedState?.state.showBone == false,
            "AVP must publish what is actually rendered while tracking is unavailable"
        )

        _ = pair.companion.receive(acknowledgment, now: now)
        _ = pair.companion.receive(unavailable, now: now)
        let liveEffects = pair.vision.updateAVPTracking(
            status: .live,
            participantSide: .right,
            detail: "live",
            now: now.addingTimeInterval(0.2)
        )
        let live = try message(of: .appliedGuidance, in: liveEffects)
        try require(
            live.payload.appliedState?.state == .initial,
            "accepted intent must apply automatically when tracking becomes live"
        )
        try require(
            live.payload.appliedState?.participantSide == .right,
            "live applied snapshot must carry AVP-authoritative laterality"
        )
    }

    private static func replayAndOutOfOrderCommandsFailClosed() throws {
        let now = Date(timeIntervalSince1970: 3_000)
        var pair = try connectedPair(now: now, seed: 300)
        let command = pair.pendingDesired
        _ = pair.vision.receive(command, now: now)
        let replayEffects = pair.vision.receive(
            command,
            now: now.addingTimeInterval(0.1)
        )
        let replayError = try message(of: .error, in: replayEffects)
        try require(
            replayError.payload.error?.code == .replayedMessage,
            "duplicate message IDs must fail closed"
        )

        let lowerSequence = ClinicianGuidanceMessage(
            sessionID: command.sessionID,
            messageID: UUID(uuidString: "00000000-0000-0000-0000-00000000F001")!,
            sequence: command.sequence - 1,
            sentAt: now,
            payload: .desiredGuidance(.set(.initial.settingBoneVisible(false)))
        )
        let orderEffects = pair.vision.receive(lowerSequence, now: now)
        let orderError = try message(of: .error, in: orderEffects)
        try require(
            orderError.payload.error?.code == .outOfOrderMessage,
            "non-increasing command sequences must fail closed"
        )
        try require(
            pair.vision.desiredGuidanceState == command.payload.command?.desiredState,
            "rejected messages must not mutate AVP desired state"
        )
    }

    private static func reconnectResendsTheLatestDesiredSnapshot() throws {
        let now = Date(timeIntervalSince1970: 4_000)
        var pair = try connectedPair(now: now, seed: 400)
        _ = pair.vision.updateAVPTracking(
            status: .live,
            participantSide: .left,
            detail: "live",
            now: now
        )
        let initialResponse = pair.vision.receive(pair.pendingDesired, now: now)
        _ = pair.companion.receive(
            try message(of: .acknowledgment, in: initialResponse),
            now: now
        )
        _ = pair.companion.receive(
            try message(of: .appliedGuidance, in: initialResponse),
            now: now
        )

        let updated = ClinicianGuidanceState.initial
            .settingFracturePosition(0.73)
            .settingIncisionGuideVisible(true)
        let updateMessage = try onlyMessage(
            pair.companion.sendDesiredState(.set(updated), now: now)
        )
        let updateResponse = pair.vision.receive(updateMessage, now: now)
        _ = pair.companion.receive(
            try message(of: .acknowledgment, in: updateResponse),
            now: now
        )

        _ = pair.companion.setTransportConnected(false, now: now)
        _ = pair.vision.setTransportConnected(false, now: now)
        _ = pair.vision.setTransportConnected(true, now: now)
        let reconnectHandshake = try onlyMessage(
            pair.companion.setTransportConnected(true, now: now)
        )
        let visionResponse = pair.vision.receive(reconnectHandshake, now: now)
        let companionResponse = pair.companion.receive(
            try message(of: .handshake, in: visionResponse),
            now: now
        )
        let resent = try message(of: .desiredGuidance, in: companionResponse)
        try require(
            resent.payload.command?.desiredState == updated,
            "reconnect must resend the latest desired snapshot, not the initial state"
        )
        try require(
            resent.sequence > updateMessage.sequence,
            "same-session reconnect must continue companion sequence monotonicity"
        )
        let reapplied = pair.vision.receive(resent, now: now)
        try require(
            try message(of: .appliedGuidance, in: reapplied)
                .payload.appliedState?.state == updated,
            "AVP must accept and reapply the reconnect snapshot"
        )
    }

    private static func stalePeerHidesAVPGuidance() throws {
        let now = Date(timeIntervalSince1970: 5_000)
        var pair = try connectedPair(now: now, seed: 500)
        _ = pair.vision.updateAVPTracking(
            status: .live,
            participantSide: .left,
            detail: "live",
            now: now
        )
        let initialResponse = pair.vision.receive(pair.pendingDesired, now: now)
        _ = pair.companion.receive(
            try message(of: .acknowledgment, in: initialResponse),
            now: now
        )
        _ = pair.companion.receive(
            try message(of: .appliedGuidance, in: initialResponse),
            now: now
        )
        let readyHeartbeat = try message(
            of: .heartbeat,
            in: pair.companion.tick(now: now.addingTimeInterval(1))
        )
        try require(
            pair.vision.avpRenderedGuidanceState?.showBone == true,
            "live synchronized AVP guidance must be visible"
        )
        _ = pair.vision.tick(
            now: now.addingTimeInterval(
                ClinicianGuidanceProtocol.staleAfterSeconds + 0.1
            )
        )
        try require(
            pair.vision.clientState.connectionStatus == .stale,
            "missing heartbeat must use the central stale threshold"
        )
        try require(
            pair.vision.avpRenderedGuidanceState?.showBone == false,
            "stale companion state must hide remotely controlled guidance"
        )
        let recoveryEffects = pair.vision.receive(
            readyHeartbeat,
            now: now.addingTimeInterval(
                ClinicianGuidanceProtocol.staleAfterSeconds + 0.1
            )
        )
        try require(
            pair.vision.avpRenderedGuidanceState?.showBone == true,
            "a fresh ready heartbeat must restore the last live applied state"
        )
        try require(
            (try message(of: .appliedGuidance, in: recoveryEffects))
                .payload.appliedState?.state.showBone == true,
            "stale recovery must publish a fresh applied snapshot"
        )
    }

    private static func connectedPair(
        now: Date,
        seed: Int
    ) throws -> (
        companion: ClinicianGuidanceSyncEngine,
        vision: ClinicianGuidanceSyncEngine,
        pendingDesired: ClinicianGuidanceMessage
    ) {
        var companion = makeEngine(role: .companion, seed: seed)
        var vision = makeEngine(role: .visionPro, seed: seed + 50)
        _ = vision.setTransportConnected(true, now: now)
        let companionHandshake = try onlyMessage(
            companion.setTransportConnected(true, now: now)
        )
        let visionResponse = vision.receive(companionHandshake, now: now)
        let desiredEffects = companion.receive(
            try message(of: .handshake, in: visionResponse),
            now: now
        )
        if let initialApplied = try? message(
            of: .appliedGuidance,
            in: visionResponse
        ) {
            _ = companion.receive(initialApplied, now: now)
        }
        return (
            companion,
            vision,
            try message(of: .desiredGuidance, in: desiredEffects)
        )
    }

    private static func makeEngine(
        role: ClinicianGuidanceEndpointRole,
        seed: Int
    ) -> ClinicianGuidanceSyncEngine {
        let sessionID = UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                seed
            )
        )!
        var messageCounter = seed * 100
        return ClinicianGuidanceSyncEngine(
            role: role,
            sessionID: sessionID,
            localDisplayName: role == .companion ? "Clinician iPad" : "Vision Pro",
            messageIDProvider: {
                messageCounter += 1
                return UUID(
                    uuidString: String(
                        format: "00000000-0000-0000-0000-%012d",
                        messageCounter
                    )
                )!
            }
        )
    }

    private static func onlyMessage(
        _ effects: [ClinicianGuidanceSyncEffect]
    ) throws -> ClinicianGuidanceMessage {
        let messages = effects.compactMap { effect -> ClinicianGuidanceMessage? in
            guard case .send(let message) = effect else { return nil }
            return message
        }
        try require(messages.count == 1, "expected exactly one outbound message")
        return messages[0]
    }

    private static func message(
        of kind: ClinicianGuidancePayloadKind,
        in effects: [ClinicianGuidanceSyncEffect]
    ) throws -> ClinicianGuidanceMessage {
        guard let message = effects.compactMap({ effect -> ClinicianGuidanceMessage? in
            guard case .send(let message) = effect,
                  message.payload.kind == kind else { return nil }
            return message
        }).first else {
            throw CheckFailure(message: "missing outbound \(kind.rawValue) message")
        }
        return message
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message: message) }
    }
}

private struct CheckFailure: Error {
    let message: String
}
