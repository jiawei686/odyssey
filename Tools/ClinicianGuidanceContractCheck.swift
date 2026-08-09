import Foundation

@main
enum ClinicianGuidanceContractCheck {
    static func main() throws {
        try normalizedPositionBoundsAreExplicit()
        try boneVisibilityDoesNotEraseGuidance()
        try everyPayloadRoundTrips()
        try unknownCapabilitiesRemainNegotiable()
        try malformedAndUnknownMessagesFailClosed()
        try orderingReplayAndFreshnessAreEnforced()
        try presentationStateDisablesUnsafeCommands()
        print("Clinician-guidance contract checks passed")
    }

    private static func normalizedPositionBoundsAreExplicit() throws {
        try require(
            ClinicianForearmPosition(clamping: -0.3) == .proximal,
            "position below zero must clamp to the proximal endpoint"
        )
        try require(
            ClinicianForearmPosition(clamping: 1.8) == .distal,
            "position above one must clamp to the distal endpoint"
        )
        do {
            _ = try JSONDecoder().decode(
                ClinicianForearmPosition.self,
                from: Data("1.01".utf8)
            )
            throw CheckFailure(message: "out-of-bounds wire position must fail")
        } catch is DecodingError {
            // Expected: local UI clamps, but malformed wire values fail closed.
        }
    }

    private static func boneVisibilityDoesNotEraseGuidance() throws {
        let guided = ClinicianGuidanceState.initial
            .settingFracturePosition(0.72)
            .settingIncisionGuideVisible(true)
        let hidden = guided.settingBoneVisible(false)
        try require(!hidden.showBone, "bone visibility must update")
        try require(
            hidden.fracturePosition == guided.fracturePosition,
            "hiding bone must preserve fracture position"
        )
        try require(
            hidden.showIncisionGuide,
            "hiding bone must preserve the incision-guide intent"
        )

        let cleared = hidden.clearingGuidance()
        try require(!cleared.showBone, "clear must preserve bone visibility")
        try require(
            cleared.fracturePosition == nil && !cleared.showIncisionGuide,
            "clear must remove only fracture/incision guidance"
        )
        try require(
            ClinicianGuidanceCommand.clear(preservingBoneVisible: true).isValid,
            "clear must be an explicit, valid command"
        )
    }

    private static func everyPayloadRoundTrips() throws {
        let sessionID = UUID(uuidString: "9AD44F9A-C507-44EB-9757-7D30901729D2")!
        let now = Date(timeIntervalSince1970: 1_786_257_600.125)
        let desired = ClinicianGuidanceState.initial
            .settingFracturePosition(0.4)
            .settingIncisionGuideVisible(true)
        let sourceMessageID = UUID(uuidString: "A20E38B7-AF1B-4B40-9617-1B9C3B95858A")!
        let payloads: [ClinicianGuidancePayload] = [
            .handshake(
                ClinicianGuidanceHandshake(
                    endpointRole: .companion,
                    supportedProtocolVersions: [1],
                    capabilities: ClinicianGuidanceCapability.judgeMVPList,
                    peerDisplayName: "Clinician iPad"
                )
            ),
            .desiredGuidance(.set(desired)),
            .appliedGuidance(
                ClinicianGuidanceAppliedState(
                    state: desired,
                    participantSide: .right,
                    trackingStatus: .live,
                    applicationStatus: .applied,
                    sourceMessageID: sourceMessageID,
                    sourceSequence: 2,
                    detail: "Generic guidance is attached to the tracked forearm axis"
                )
            ),
            .acknowledgment(
                ClinicianGuidanceAcknowledgment(
                    acknowledgedMessageID: sourceMessageID,
                    acknowledgedSequence: 2,
                    disposition: .applied,
                    detail: nil
                )
            ),
            .heartbeat(
                ClinicianGuidanceHeartbeat(
                    endpointRole: .visionPro,
                    liveness: .ready,
                    lastReceivedSequence: 2,
                    lastAppliedCommandSequence: 2
                )
            ),
            .error(
                ClinicianGuidanceErrorPayload(
                    code: .trackingUnavailable,
                    relatedMessageID: sourceMessageID,
                    detail: "Hand tracking is temporarily unavailable"
                )
            )
        ]

        for (offset, payload) in payloads.enumerated() {
            let message = ClinicianGuidanceMessage(
                sessionID: sessionID,
                sequence: UInt64(offset + 1),
                sentAt: now,
                payload: payload
            )
            let encoded = try ClinicianGuidanceWireCodec.encode(message)
            let decoded = try ClinicianGuidanceWireCodec.decode(encoded)
            try require(decoded == message, "payload \(payload.kind) must round-trip")
        }
    }

    private static func unknownCapabilitiesRemainNegotiable() throws {
        let unknown = ClinicianGuidanceCapability(rawValue: "future-capability")
        let handshake = ClinicianGuidanceHandshake(
            endpointRole: .visionPro,
            supportedProtocolVersions: [1, 2],
            capabilities: [.heartbeat, unknown],
            peerDisplayName: nil
        )
        try require(handshake.isValid, "future capabilities must remain decodable")
        try require(
            handshake.unsupportedCapabilities(
                supported: ClinicianGuidanceCapability.judgeMVP
            ) == [unknown],
            "negotiation must report unsupported capabilities explicitly"
        )
    }

    private static func malformedAndUnknownMessagesFailClosed() throws {
        let sessionID = UUID()
        let now = Date(timeIntervalSince1970: 100)
        let unsupported = ClinicianGuidanceMessage(
            protocolVersion: 99,
            sessionID: sessionID,
            sequence: 1,
            sentAt: now,
            payload: .heartbeat(
                ClinicianGuidanceHeartbeat(
                    endpointRole: .companion,
                    liveness: .ready,
                    lastReceivedSequence: nil,
                    lastAppliedCommandSequence: nil
                )
            )
        )
        let packet = try ClinicianGuidanceWireCodec.encode(unsupported)
        let decoded = try ClinicianGuidanceWireCodec.decode(packet)
        var gate = ClinicianGuidanceMessageGate(sessionID: sessionID)
        try require(
            gate.accept(decoded, now: now) == .rejected(.unsupportedVersion),
            "unknown protocol versions must be rejected by negotiation/gating"
        )

        let malformed = """
        {
          "protocolVersion": 1,
          "sessionID": "\(sessionID.uuidString)",
          "messageID": "\(UUID().uuidString)",
          "sequence": 2,
          "sentAt": 100000,
          "payload": {
            "kind": "desiredGuidance",
            "command": {
              "action": "setGuidance",
              "desiredState": {
                "showBone": true,
                "fracturePosition": 1.2,
                "showIncisionGuide": false
              }
            }
          }
        }
        """
        let malformedWasRejected: Bool
        do {
            _ = try ClinicianGuidanceWireCodec.decode(Data(malformed.utf8))
            malformedWasRejected = false
        } catch {
            malformedWasRejected = true
        }
        try require(malformedWasRejected, "malformed guidance must fail closed")
    }

    private static func orderingReplayAndFreshnessAreEnforced() throws {
        let sessionID = UUID()
        let now = Date(timeIntervalSince1970: 500)
        let firstID = UUID()
        let first = message(
            sessionID: sessionID,
            messageID: firstID,
            sequence: 1,
            sentAt: now
        )
        var gate = ClinicianGuidanceMessageGate(sessionID: sessionID)
        try require(gate.accept(first, now: now) == .accepted, "first message must pass")

        let replay = message(
            sessionID: sessionID,
            messageID: firstID,
            sequence: 2,
            sentAt: now
        )
        try require(
            gate.accept(replay, now: now) == .rejected(.replayedMessageID),
            "replayed message IDs must be rejected"
        )

        let next = message(
            sessionID: sessionID,
            messageID: UUID(),
            sequence: 3,
            sentAt: now
        )
        try require(gate.accept(next, now: now) == .accepted, "higher sequence must pass")
        let outOfOrder = message(
            sessionID: sessionID,
            messageID: UUID(),
            sequence: 2,
            sentAt: now
        )
        try require(
            gate.accept(outOfOrder, now: now) == .rejected(.nonIncreasingSequence),
            "out-of-order messages must be rejected"
        )

        let stale = message(
            sessionID: sessionID,
            messageID: UUID(),
            sequence: 4,
            sentAt: now.addingTimeInterval(-6)
        )
        try require(
            gate.accept(stale, now: now) == .rejected(.stale),
            "stale messages must be rejected"
        )
    }

    private static func presentationStateDisablesUnsafeCommands() throws {
        let desired = ClinicianGuidanceState.initial
        let disconnected = ClinicianGuidanceClientState(
            connectionStatus: .disconnected,
            desiredGuidanceState: desired,
            appliedGuidanceState: nil,
            pendingMessageID: nil,
            lastAcknowledgedAt: nil,
            lastError: nil,
            peerDisplayName: nil
        )
        try require(
            !disconnected.canSendGuidanceCommands,
            "disconnected UI must not queue guidance"
        )

        let pending = ClinicianGuidanceClientState(
            connectionStatus: .syncing,
            desiredGuidanceState: desired,
            appliedGuidanceState: nil,
            pendingMessageID: UUID(),
            lastAcknowledgedAt: nil,
            lastError: nil,
            peerDisplayName: "Vision Pro"
        )
        try require(
            !pending.canSendGuidanceCommands,
            "single in-flight MVP must disable additional commands"
        )

        let connected = ClinicianGuidanceClientState(
            connectionStatus: .connected,
            desiredGuidanceState: desired,
            appliedGuidanceState: nil,
            pendingMessageID: nil,
            lastAcknowledgedAt: nil,
            lastError: nil,
            peerDisplayName: "Vision Pro"
        )
        try require(connected.canSendGuidanceCommands, "idle connected UI may send")
        try require(connected.participantSide == .unknown, "side starts unknown")
        try require(
            ClinicianGuidanceProtocol.staleAfterSeconds == 3,
            "stale threshold must have one central value"
        )
    }

    private static func message(
        sessionID: UUID,
        messageID: UUID,
        sequence: UInt64,
        sentAt: Date
    ) -> ClinicianGuidanceMessage {
        ClinicianGuidanceMessage(
            sessionID: sessionID,
            messageID: messageID,
            sequence: sequence,
            sentAt: sentAt,
            payload: .desiredGuidance(.set(.initial))
        )
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message: message) }
    }
}

private struct CheckFailure: Error {
    let message: String
}
