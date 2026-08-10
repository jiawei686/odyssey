import Foundation

@main
enum OdysseyClinicalSessionContractCheck {
    static func main() throws {
        try lockedCaseAndRevealBoundsAreExplicit()
        try allPayloadsRoundTrip()
        try capabilityNegotiationFailsClosed()
        try liveStaleAndRejectedStatesAreTruthful()
        try orderingReplayAndFreshnessAreEnforced()
        try adapterSeparatesDesiredFromAppliedTruth()
        try legacyClinicianGuidancePacketsRemainRoutable()
        print("Odyssey clinical-session contract checks passed")
    }

    private static func lockedCaseAndRevealBoundsAreExplicit() throws {
        let descriptor = OdysseyClinicalSessionDescriptor.odysseyRightForearmReference
        try require(descriptor.isValid, "locked Odyssey case must be valid")
        try require(descriptor.patient.displayName == "Odyssey", "patient name is locked")
        try require(
            descriptor.model.displayName == "Right Forearm VRT",
            "model name is locked"
        )
        try require(descriptor.model.laterality == .right, "laterality must be right")
        try require(
            descriptor.disclosure == OdysseyClinicalSessionProtocol.disclosure,
            "reference-anatomy disclosure must be exact"
        )
        try require(
            OdysseyClinicalRevealValue(clamping: -0.2) == .surface,
            "local reveal below zero must clamp to Surface"
        )
        try require(
            OdysseyClinicalRevealValue(clamping: 1.2) == .bone,
            "local reveal above one must clamp to Bone"
        )

        do {
            _ = try JSONDecoder().decode(
                OdysseyClinicalRevealValue.self,
                from: Data("1.01".utf8)
            )
            throw CheckFailure(message: "wire reveal above one must be rejected")
        } catch is DecodingError {
            // Local UI may clamp; the network contract fails closed.
        }
    }

    private static func allPayloadsRoundTrip() throws {
        let sessionID = fixedUUID("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let sourceID = fixedUUID("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
        let now = Date(timeIntervalSince1970: 1_786_344_000.125)
        let frame = OdysseyClinicalTrackingFrame(
            identifier: "right-forearm-frame-42",
            capturedAt: now.addingTimeInterval(-0.02),
            confidence: 0.94
        )
        let desired = OdysseyClinicalDesiredState.initial.settingReveal(0.72)
        let applied = OdysseyClinicalAppliedState(
            descriptor: .odysseyRightForearmReference,
            appliedReveal: desired.reveal,
            rendererRoute: .ctDerivedMeshFallback,
            trackingState: .live,
            presentation: .followArm,
            applicationState: .applied,
            sourceMessageID: sourceID,
            sourceSequence: 2,
            trackingFrame: frame,
            appliedAt: now,
            failureReason: nil,
            detail: "CT-derived twin follows the live right forearm"
        )
        try require(applied.isValid, "representative live state must be valid")

        let payloads: [OdysseyClinicalSessionPayload] = [
            .handshake(visionHandshake()),
            .desiredState(.set(desired)),
            .appliedState(applied),
            .acknowledgment(
                OdysseyClinicalAcknowledgment(
                    acknowledgedMessageID: sourceID,
                    acknowledgedSequence: 2,
                    disposition: .applied,
                    appliedFrameIdentifier: frame.identifier,
                    detail: nil
                )
            ),
            .heartbeat(
                OdysseyClinicalHeartbeat(
                    endpointRole: .visionPro,
                    liveness: .ready,
                    lastReceivedSequence: 2,
                    lastAppliedCommandSequence: 2,
                    lastAppliedFrameIdentifier: frame.identifier
                )
            ),
            .error(
                OdysseyClinicalSessionErrorPayload(
                    reason: .trackingSearching,
                    relatedMessageID: sourceID,
                    detail: "Right forearm tracking is searching"
                )
            )
        ]

        let codec = OdysseyClinicalSessionWireCodec()
        for (index, payload) in payloads.enumerated() {
            let message = OdysseyClinicalSessionMessage(
                sessionID: sessionID,
                sequence: UInt64(index + 1),
                sentAt: now,
                payload: payload
            )
            let data = try codec.encode(message)
            try require(
                try codec.decode(data) == message,
                "payload \(payload.kind) must round-trip"
            )
            try require(
                try codec.decodeIfOdysseyClinicalSession(data) == message,
                "identified Odyssey packet must be claimed by its codec"
            )
        }
    }

    private static func capabilityNegotiationFailsClosed() throws {
        let unknown = OdysseyClinicalSessionCapability(rawValue: "future-capability")
        var capabilities = OdysseyClinicalSessionCapability.requiredList
        capabilities.append(unknown)
        let handshake = OdysseyClinicalSessionHandshake(
            endpointRole: .visionPro,
            supportedProtocolVersions: [1, 2],
            capabilities: capabilities,
            descriptor: .odysseyRightForearmReference,
            availableRendererRoutes: [.spatialVRT, .ctDerivedMeshFallback],
            peerDisplayName: "Odyssey Vision Pro"
        )
        try require(handshake.isValid, "future capabilities must remain decodable")
        try require(
            handshake.hasRequiredCapabilities(
                supportedBy: OdysseyClinicalSessionCapability.required
            ),
            "required capabilities must negotiate despite an unknown addition"
        )

        var missing = OdysseyClinicalSessionCapability.requiredList
        missing.removeAll { $0 == .appliedReveal }
        let incomplete = OdysseyClinicalSessionHandshake(
            endpointRole: .visionPro,
            supportedProtocolVersions: [1],
            capabilities: missing,
            descriptor: .odysseyRightForearmReference,
            availableRendererRoutes: [.ctDerivedMeshFallback],
            peerDisplayName: nil
        )
        var adapter = OdysseyClinicalSessionAdapter()
        adapter.beginConnecting()
        try require(
            !adapter.acceptVisionHandshake(incomplete),
            "missing AVP-applied state capability must fail negotiation"
        )
        try require(
            adapter.state.connectionState == .error
                && adapter.state.lastError?.reason == .unsupportedCapability,
            "capability failure must remain visible and commands must stay disabled"
        )
        try require(
            adapter.prepareRevealCommand(0.4, messageID: UUID(), sequence: 1) == nil,
            "unsupported peer must not receive queued guidance"
        )
    }

    private static func liveStaleAndRejectedStatesAreTruthful() throws {
        let now = Date(timeIntervalSince1970: 500)
        let sourceID = UUID()
        let liveFrame = OdysseyClinicalTrackingFrame(
            identifier: "live-frame",
            capturedAt: now.addingTimeInterval(-0.1),
            confidence: 0.9
        )
        let live = appliedState(
            reveal: 0.6,
            sourceID: sourceID,
            sequence: 3,
            frame: liveFrame,
            appliedAt: now
        )
        try require(live.isValid, "fresh high-confidence live state must apply")

        let lowConfidence = appliedState(
            reveal: 0.6,
            sourceID: sourceID,
            sequence: 3,
            frame: OdysseyClinicalTrackingFrame(
                identifier: "weak-frame",
                capturedAt: now,
                confidence: 0.2
            ),
            appliedAt: now
        )
        try require(
            !lowConfidence.isValid,
            "insufficient confidence must not be represented as applied"
        )

        let oldFrame = OdysseyClinicalTrackingFrame(
            identifier: "old-frame",
            capturedAt: now.addingTimeInterval(-4),
            confidence: 0.95
        )
        let stalePretendingLive = appliedState(
            reveal: 0.6,
            sourceID: sourceID,
            sequence: 3,
            frame: oldFrame,
            appliedAt: now
        )
        try require(
            !stalePretendingLive.isValid,
            "stale frame must not remain a live applied state"
        )

        let heldStale = OdysseyClinicalAppliedState(
            descriptor: .odysseyRightForearmReference,
            appliedReveal: OdysseyClinicalRevealValue(validating: 0.6),
            rendererRoute: .ctDerivedMeshFallback,
            trackingState: .stale,
            presentation: .held,
            applicationState: .heldStale,
            sourceMessageID: sourceID,
            sourceSequence: 3,
            trackingFrame: oldFrame,
            appliedAt: now,
            failureReason: .trackingStale,
            detail: "Last safe pose is frozen and dimmed"
        )
        try require(
            heldStale.isValid,
            "stale state may preserve only an explicit held last-safe pose"
        )

        let rejected = OdysseyClinicalAppliedState(
            descriptor: .odysseyRightForearmReference,
            appliedReveal: nil,
            rendererRoute: .ctDerivedMeshFallback,
            trackingState: .searching,
            presentation: nil,
            applicationState: .rejected,
            sourceMessageID: sourceID,
            sourceSequence: 4,
            trackingFrame: nil,
            appliedAt: now,
            failureReason: .trackingSearching,
            detail: "No live right-forearm frame"
        )
        try require(rejected.isValid, "searching must reject rather than guess depth")
    }

    private static func orderingReplayAndFreshnessAreEnforced() throws {
        let sessionID = UUID()
        let now = Date(timeIntervalSince1970: 1_000)
        let unsupported = OdysseyClinicalSessionMessage(
            protocolVersion: 2,
            sessionID: sessionID,
            sequence: 1,
            sentAt: now,
            payload: heartbeatPayload()
        )
        var gate = OdysseyClinicalSessionMessageGate(sessionID: sessionID)
        try require(
            gate.accept(unsupported, now: now) == .rejected(.unsupportedVersion),
            "unsupported protocol version must fail closed"
        )
        let wrongSession = OdysseyClinicalSessionMessage(
            sessionID: UUID(),
            sequence: 1,
            sentAt: now,
            payload: heartbeatPayload()
        )
        try require(
            gate.accept(wrongSession, now: now) == .rejected(.sessionMismatch),
            "foreign session packet must fail closed"
        )
        let invalidIdentifier = OdysseyClinicalSessionMessage(
            protocolIdentifier: "not-odyssey",
            sessionID: sessionID,
            sequence: 1,
            sentAt: now,
            payload: heartbeatPayload()
        )
        try require(
            gate.accept(invalidIdentifier, now: now) == .rejected(.invalidPayload),
            "wrong wire-family identifier must fail closed"
        )

        let firstID = UUID()
        let first = heartbeatMessage(
            sessionID: sessionID,
            messageID: firstID,
            sequence: 1,
            sentAt: now
        )
        try require(gate.accept(first, now: now) == .accepted, "first packet must pass")

        let replay = heartbeatMessage(
            sessionID: sessionID,
            messageID: firstID,
            sequence: 2,
            sentAt: now
        )
        try require(
            gate.accept(replay, now: now) == .rejected(.replayedMessageID),
            "replayed IDs must fail closed"
        )

        let next = heartbeatMessage(
            sessionID: sessionID,
            messageID: UUID(),
            sequence: 3,
            sentAt: now
        )
        try require(gate.accept(next, now: now) == .accepted, "next sequence must pass")
        let oldSequence = heartbeatMessage(
            sessionID: sessionID,
            messageID: UUID(),
            sequence: 2,
            sentAt: now
        )
        try require(
            gate.accept(oldSequence, now: now) == .rejected(.nonIncreasingSequence),
            "out-of-order sequence must fail closed"
        )

        let stale = heartbeatMessage(
            sessionID: sessionID,
            messageID: UUID(),
            sequence: 4,
            sentAt: now.addingTimeInterval(-6)
        )
        try require(
            gate.accept(stale, now: now) == .rejected(.stale),
            "old session packet must fail closed"
        )
        let future = heartbeatMessage(
            sessionID: sessionID,
            messageID: UUID(),
            sequence: 5,
            sentAt: now.addingTimeInterval(2)
        )
        try require(
            gate.accept(future, now: now) == .rejected(.futureTimestamp),
            "excessive future skew must fail closed"
        )
    }

    private static func adapterSeparatesDesiredFromAppliedTruth() throws {
        var adapter = OdysseyClinicalSessionAdapter()
        try require(
            adapter.prepareRevealCommand(0.5, messageID: UUID(), sequence: 1) == nil,
            "disconnected commands must not be queued"
        )

        adapter.beginConnecting()
        try require(
            adapter.acceptVisionHandshake(visionHandshake()),
            "complete Vision handshake must connect"
        )
        let commandID = fixedUUID("CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")
        let command = adapter.prepareRevealCommand(
            0.75,
            messageID: commandID,
            sequence: 7
        )
        try require(command?.desiredState.reveal.value == 0.75, "desired reveal must update")
        try require(adapter.state.isPending, "one command must become pending")
        try require(
            adapter.state.appliedState == nil && adapter.state.confirmedReveal == nil,
            "desired intent must never synthesize applied success"
        )
        try require(
            adapter.prepareRevealCommand(0.8, messageID: UUID(), sequence: 8) == nil,
            "MVP permits only one in-flight command"
        )

        let now = Date(timeIntervalSince1970: 2_000)
        let pendingACK = OdysseyClinicalAcknowledgment(
            acknowledgedMessageID: commandID,
            acknowledgedSequence: 7,
            disposition: .acceptedPendingTracking,
            appliedFrameIdentifier: nil,
            detail: "Waiting for live right-forearm tracking"
        )
        try require(
            adapter.receiveAcknowledgment(pendingACK, receivedAt: now),
            "matching pending ACK must be recorded"
        )
        try require(
            adapter.state.isPending && adapter.state.confirmedReveal == nil,
            "pending-tracking ACK must not claim applied state"
        )
        let appliedACK = OdysseyClinicalAcknowledgment(
            acknowledgedMessageID: commandID,
            acknowledgedSequence: 7,
            disposition: .applied,
            appliedFrameIdentifier: "right-forearm-live-frame",
            detail: nil
        )
        try require(
            adapter.receiveAcknowledgment(appliedACK, receivedAt: now),
            "matching applied ACK must be recorded"
        )
        try require(
            adapter.state.isPending && adapter.state.confirmedReveal == nil,
            "even an applied ACK must wait for the AVP-applied snapshot"
        )

        let wrongSource = appliedState(
            reveal: 0.75,
            sourceID: UUID(),
            sequence: 7,
            frame: liveFrame(at: now),
            appliedAt: now
        )
        try require(
            !adapter.receiveAppliedState(wrongSource),
            "mismatched AVP source must not clear the pending command"
        )

        let applied = appliedState(
            reveal: 0.75,
            sourceID: commandID,
            sequence: 7,
            frame: liveFrame(at: now),
            appliedAt: now
        )
        try require(
            adapter.receiveAppliedState(applied),
            "matching AVP-applied snapshot must be accepted"
        )
        try require(
            adapter.state.confirmedReveal?.value == 0.75
                && adapter.state.isDesiredStateConfirmed,
            "only AVP-applied state may confirm the desired reveal"
        )

        adapter.markStale()
        try require(
            adapter.state.connectionState == .stale
                && adapter.state.confirmedReveal == nil
                && !adapter.state.canSendCommands,
            "stale session must hide current-success semantics and disable commands"
        )
        try require(
            adapter.prepareRevealCommand(0.2, messageID: UUID(), sequence: 8) == nil,
            "stale commands must not be queued offline"
        )
    }

    private static func legacyClinicianGuidancePacketsRemainRoutable() throws {
        try require(
            ClinicianGuidanceProtocol.currentVersion == 1,
            "separate clinical session must not version-bump clinician guidance"
        )
        let legacy = ClinicianGuidanceMessage(
            sessionID: UUID(),
            sequence: 1,
            sentAt: Date(timeIntervalSince1970: 3_000),
            payload: .desiredGuidance(.set(.initial))
        )
        let legacyData = try ClinicianGuidanceWireCodec.encode(legacy)
        let newCodec = OdysseyClinicalSessionWireCodec()
        try require(
            try newCodec.decodeIfOdysseyClinicalSession(legacyData) == nil,
            "new decoder must decline packets owned by the legacy wire family"
        )
        try require(
            try ClinicianGuidanceWireCodec.decode(legacyData) == legacy,
            "legacy clinician-guidance round trip must remain unchanged"
        )
    }

    private static func visionHandshake() -> OdysseyClinicalSessionHandshake {
        OdysseyClinicalSessionHandshake(
            endpointRole: .visionPro,
            supportedProtocolVersions: [OdysseyClinicalSessionProtocol.currentVersion],
            capabilities: OdysseyClinicalSessionCapability.requiredList,
            descriptor: .odysseyRightForearmReference,
            availableRendererRoutes: [.ctDerivedMeshFallback],
            peerDisplayName: "Odyssey Vision Pro"
        )
    }

    private static func liveFrame(at now: Date) -> OdysseyClinicalTrackingFrame {
        OdysseyClinicalTrackingFrame(
            identifier: "right-forearm-live-frame",
            capturedAt: now.addingTimeInterval(-0.05),
            confidence: 0.95
        )
    }

    private static func appliedState(
        reveal: Double,
        sourceID: UUID,
        sequence: UInt64,
        frame: OdysseyClinicalTrackingFrame,
        appliedAt: Date
    ) -> OdysseyClinicalAppliedState {
        OdysseyClinicalAppliedState(
            descriptor: .odysseyRightForearmReference,
            appliedReveal: OdysseyClinicalRevealValue(validating: reveal),
            rendererRoute: .ctDerivedMeshFallback,
            trackingState: .live,
            presentation: .followArm,
            applicationState: .applied,
            sourceMessageID: sourceID,
            sourceSequence: sequence,
            trackingFrame: frame,
            appliedAt: appliedAt,
            failureReason: nil,
            detail: "AVP-confirmed live state"
        )
    }

    private static func heartbeatMessage(
        sessionID: UUID,
        messageID: UUID,
        sequence: UInt64,
        sentAt: Date
    ) -> OdysseyClinicalSessionMessage {
        OdysseyClinicalSessionMessage(
            sessionID: sessionID,
            messageID: messageID,
            sequence: sequence,
            sentAt: sentAt,
            payload: heartbeatPayload()
        )
    }

    private static func heartbeatPayload() -> OdysseyClinicalSessionPayload {
        .heartbeat(
            OdysseyClinicalHeartbeat(
                endpointRole: .visionPro,
                liveness: .ready,
                lastReceivedSequence: nil,
                lastAppliedCommandSequence: nil,
                lastAppliedFrameIdentifier: nil
            )
        )
    }

    private static func fixedUUID(_ string: String) -> UUID {
        guard let value = UUID(uuidString: string) else {
            preconditionFailure("Invalid test UUID")
        }
        return value
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message: message) }
    }
}

private struct CheckFailure: Error {
    let message: String
}
