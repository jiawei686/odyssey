import Foundation
import OSLog

@MainActor
final class OdysseyClinicalSessionService: ObservableObject,
    OdysseyClinicalSessionControlling,
    PeerSessionOdysseyClinicalSessionDelegate {
    enum Role {
        case companion
        case visionPro
    }

    @Published private(set) var odysseyClinicalSessionState =
        OdysseyClinicalSessionClientState.disconnected
    @Published private(set) var avpAppliedState: OdysseyClinicalAppliedState?
    @Published private(set) var isNegotiated = false

    private struct PendingApplication {
        let messageID: UUID
        let sequence: UInt64
        let reveal: OdysseyClinicalRevealValue
    }

    private let role: Role
    private let peer: PeerSession
    private let localDisplayName: String
    private var adapter = OdysseyClinicalSessionAdapter()
    private var sessionID: UUID?
    private var receiveGate: OdysseyClinicalSessionMessageGate?
    private var nextSequence: UInt64 = 1
    private var lastPeerMessageAt: Date?
    private var lastHeartbeatAt: Date?
    private var loopTask: Task<Void, Never>?

    private var rendererReady = false
    private var trackingState: OdysseyTwinTrackingState = .searching
    private var currentFrame: OdysseyClinicalTrackingFrame?
    private var lastSafeFrame: OdysseyClinicalTrackingFrame?
    private var pendingApplication: PendingApplication?
    private var lastApplied: OdysseyClinicalAppliedState?
    private var applyReveal: ((Double) -> Void)?

    private let logger = Logger(
        subsystem: "com.marcel.UpperLimbPOC",
        category: "OdysseySession"
    )

    init(role: Role, peer: PeerSession, localDisplayName: String) {
        self.role = role
        self.peer = peer
        self.localDisplayName = localDisplayName
        peer.setOdysseyClinicalSessionDelegate(self)
    }

    func configureAVPRevealApplication(_ apply: @escaping (Double) -> Void) {
        guard role == .visionPro else { return }
        applyReveal = apply
    }

    func setReveal(_ normalizedReveal: Double) {
        guard role == .companion,
              let sessionID,
              let command = adapter.prepareRevealCommand(
                normalizedReveal,
                messageID: UUID(),
                sequence: nextSequence
              )
        else { return }

        let message = makeMessage(sessionID: sessionID, payload: .desiredState(command))
        publishAdapterState()
        peer.send(message)
        logger.notice("action=reveal state=desired sequence=\(message.sequence)")
    }

    func retryConnection() {
        peer.restart()
    }

#if os(visionOS)
    func updateAVPEnvironment(
        rendererReady: Bool,
        resolution: AVPForearmOverlayResolution,
        frameIdentifier: String,
        now: Date = Date()
    ) {
        guard role == .visionPro else { return }
        self.rendererReady = rendererReady
        switch resolution.state {
        case .live:
            trackingState = .live
            let frame = OdysseyClinicalTrackingFrame(
                identifier: frameIdentifier,
                capturedAt: now,
                confidence: 1
            )
            currentFrame = frame
            lastSafeFrame = frame
            applyPendingIfSafe(now: now)
        case .stale:
            trackingState = .stale
            currentFrame = nil
            publishHeldStaleIfNeeded(now: now)
        case .searching, .partial:
            trackingState = .searching
            currentFrame = nil
        case .failed:
            trackingState = .failed
            currentFrame = nil
        }
    }
#endif

    func resetForEndedSession() {
        pendingApplication = nil
        rendererReady = false
        trackingState = .searching
        currentFrame = nil
        lastSafeFrame = nil
        lastApplied = nil
        avpAppliedState = nil
    }

    func peerSession(
        _ peer: PeerSession,
        odysseyConnectionChanged isConnected: Bool
    ) {
        if isConnected {
            startLoop()
            if role == .companion {
                beginCompanionHandshake()
            }
        } else {
            loopTask?.cancel()
            loopTask = nil
            sessionID = nil
            isNegotiated = false
            receiveGate = nil
            nextSequence = 1
            lastPeerMessageAt = nil
            if role == .companion {
                adapter.disconnect()
                publishAdapterState()
            }
        }
    }

    func peerSession(
        _ peer: PeerSession,
        received message: OdysseyClinicalSessionMessage
    ) {
        let now = Date()
        guard accept(message, now: now) else { return }
        lastPeerMessageAt = now

        switch role {
        case .companion:
            receiveOnCompanion(message, now: now)
        case .visionPro:
            receiveOnVisionPro(message, now: now)
        }
    }

    private func beginCompanionHandshake() {
        let id = UUID()
        sessionID = id
        receiveGate = OdysseyClinicalSessionMessageGate(sessionID: id)
        nextSequence = 1
        adapter.beginConnecting()
        publishAdapterState()
        sendHandshake(sessionID: id, endpointRole: .clinicianCompanion)
    }

    private func accept(
        _ message: OdysseyClinicalSessionMessage,
        now: Date
    ) -> Bool {
        if sessionID == nil, role == .visionPro,
           message.payload.kind == .handshake,
           message.payload.handshake?.endpointRole == .clinicianCompanion {
            sessionID = message.sessionID
            receiveGate = OdysseyClinicalSessionMessageGate(sessionID: message.sessionID)
            nextSequence = 1
        }
        guard message.sessionID == sessionID, var receiveGate else {
            logger.error("receive=rejected reason=session-mismatch")
            return false
        }
        guard receiveGate.accept(message, now: now) == .accepted else {
            logger.error("receive=rejected reason=freshness-or-replay")
            return false
        }
        self.receiveGate = receiveGate
        return true
    }

    private func receiveOnCompanion(
        _ message: OdysseyClinicalSessionMessage,
        now: Date
    ) {
        switch message.payload.kind {
        case .handshake:
            if let handshake = message.payload.handshake {
                isNegotiated = adapter.acceptVisionHandshake(handshake)
            }
        case .acknowledgment:
            if let acknowledgment = message.payload.acknowledgment {
                _ = adapter.receiveAcknowledgment(acknowledgment, receivedAt: now)
            }
        case .appliedState:
            if let applied = message.payload.appliedState {
                _ = adapter.receiveAppliedState(applied)
            }
        case .error:
            if let error = message.payload.error {
                adapter.markStale(detail: error.detail)
            }
        case .heartbeat, .desiredState:
            break
        }
        publishAdapterState()
    }

    private func receiveOnVisionPro(
        _ message: OdysseyClinicalSessionMessage,
        now: Date
    ) {
        switch message.payload.kind {
        case .handshake:
            guard let handshake = message.payload.handshake,
                  handshake.endpointRole == .clinicianCompanion,
                  handshake.isValid,
                  handshake.hasRequiredCapabilities(
                    supportedBy: OdysseyClinicalSessionCapability.required
                  ),
                  let sessionID
            else { return }
            isNegotiated = true
            sendHandshake(sessionID: sessionID, endpointRole: .visionPro)
        case .desiredState:
            guard let command = message.payload.desiredCommand else { return }
            pendingApplication = PendingApplication(
                messageID: message.messageID,
                sequence: message.sequence,
                reveal: command.desiredState.reveal
            )
            if rendererReady, trackingState == .live,
               currentFrame?.hasSufficientConfidence == true {
                applyPendingIfSafe(now: now)
            } else {
                sendAcknowledgment(
                    for: message,
                    disposition: .acceptedPendingTracking,
                    frameIdentifier: nil,
                    detail: "Waiting for a live right-forearm frame"
                )
            }
        case .heartbeat, .acknowledgment, .appliedState, .error:
            break
        }
    }

    private func applyPendingIfSafe(now: Date) {
        guard rendererReady,
              trackingState == .live,
              let frame = currentFrame,
              frame.hasSufficientConfidence,
              frame.isFresh(at: now),
              let pendingApplication,
              let applyReveal,
              let sessionID
        else { return }

        applyReveal(pendingApplication.reveal.value)
        let acknowledgment = OdysseyClinicalAcknowledgment(
            acknowledgedMessageID: pendingApplication.messageID,
            acknowledgedSequence: pendingApplication.sequence,
            disposition: .applied,
            appliedFrameIdentifier: frame.identifier,
            detail: "Applied to the live CT-derived right-forearm twin"
        )
        send(sessionID: sessionID, payload: .acknowledgment(acknowledgment), now: now)

        let applied = OdysseyClinicalAppliedState(
            descriptor: .odysseyRightForearmReference,
            appliedReveal: pendingApplication.reveal,
            rendererRoute: .ctDerivedMeshFallback,
            trackingState: .live,
            presentation: .followArm,
            applicationState: .applied,
            sourceMessageID: pendingApplication.messageID,
            sourceSequence: pendingApplication.sequence,
            trackingFrame: frame,
            appliedAt: now,
            failureReason: nil,
            detail: "AVP-confirmed CT-derived mesh reveal"
        )
        send(sessionID: sessionID, payload: .appliedState(applied), now: now)
        lastApplied = applied
        avpAppliedState = applied
        self.pendingApplication = nil
        logger.notice("action=reveal state=applied frame=\(frame.identifier, privacy: .public)")
    }

    private func publishHeldStaleIfNeeded(now: Date) {
        guard let sessionID,
              let lastApplied,
              lastApplied.applicationState == .applied,
              let frame = lastSafeFrame,
              let sourceMessageID = lastApplied.sourceMessageID,
              let sourceSequence = lastApplied.sourceSequence,
              let reveal = lastApplied.appliedReveal,
              let route = lastApplied.rendererRoute
        else { return }
        let held = OdysseyClinicalAppliedState(
            descriptor: .odysseyRightForearmReference,
            appliedReveal: reveal,
            rendererRoute: route,
            trackingState: .stale,
            presentation: .held,
            applicationState: .heldStale,
            sourceMessageID: sourceMessageID,
            sourceSequence: sourceSequence,
            trackingFrame: frame,
            appliedAt: now,
            failureReason: .trackingStale,
            detail: "Tracking stale; AVP is holding the last safe pose"
        )
        guard held.isValid else { return }
        send(sessionID: sessionID, payload: .appliedState(held), now: now)
        self.lastApplied = held
        avpAppliedState = held
    }

    private func sendHandshake(
        sessionID: UUID,
        endpointRole: OdysseyClinicalSessionEndpointRole
    ) {
        let routes: [OdysseyTwinRendererRoute] = endpointRole == .visionPro
            ? [.ctDerivedMeshFallback]
            : []
        let handshake = OdysseyClinicalSessionHandshake(
            endpointRole: endpointRole,
            supportedProtocolVersions: [OdysseyClinicalSessionProtocol.currentVersion],
            capabilities: OdysseyClinicalSessionCapability.requiredList,
            descriptor: .odysseyRightForearmReference,
            availableRendererRoutes: routes,
            peerDisplayName: localDisplayName
        )
        send(sessionID: sessionID, payload: .handshake(handshake), now: Date())
    }

    private func sendAcknowledgment(
        for message: OdysseyClinicalSessionMessage,
        disposition: OdysseyClinicalAcknowledgmentDisposition,
        frameIdentifier: String?,
        detail: String?
    ) {
        guard let sessionID else { return }
        let acknowledgment = OdysseyClinicalAcknowledgment(
            acknowledgedMessageID: message.messageID,
            acknowledgedSequence: message.sequence,
            disposition: disposition,
            appliedFrameIdentifier: frameIdentifier,
            detail: detail
        )
        send(sessionID: sessionID, payload: .acknowledgment(acknowledgment), now: Date())
    }

    private func makeMessage(
        sessionID: UUID,
        payload: OdysseyClinicalSessionPayload,
        now: Date = Date()
    ) -> OdysseyClinicalSessionMessage {
        defer { nextSequence += 1 }
        return OdysseyClinicalSessionMessage(
            sessionID: sessionID,
            sequence: nextSequence,
            sentAt: now,
            payload: payload
        )
    }

    private func send(
        sessionID: UUID,
        payload: OdysseyClinicalSessionPayload,
        now: Date
    ) {
        peer.send(makeMessage(sessionID: sessionID, payload: payload, now: now))
    }

    private func startLoop() {
        guard loopTask == nil else { return }
        loopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) }
                catch { return }
                self?.tick(now: Date())
            }
        }
    }

    private func tick(now: Date) {
        if role == .companion,
           let lastPeerMessageAt,
           now.timeIntervalSince(lastPeerMessageAt)
            > OdysseyClinicalSessionProtocol.staleAfterSeconds,
           odysseyClinicalSessionState.connectionState != .stale {
            adapter.markStale()
            publishAdapterState()
        }
        guard let sessionID,
              lastHeartbeatAt.map({ now.timeIntervalSince($0) >= 1 }) ?? true
        else { return }
        lastHeartbeatAt = now
        let heartbeat = OdysseyClinicalHeartbeat(
            endpointRole: role == .companion ? .clinicianCompanion : .visionPro,
            liveness: trackingState == .stale ? .stale : .ready,
            lastReceivedSequence: receiveGate?.lastAcceptedSequence,
            lastAppliedCommandSequence: lastApplied?.sourceSequence,
            lastAppliedFrameIdentifier: lastApplied?.trackingFrame?.identifier
        )
        send(sessionID: sessionID, payload: .heartbeat(heartbeat), now: now)
    }

    private func publishAdapterState() {
        if odysseyClinicalSessionState != adapter.state {
            odysseyClinicalSessionState = adapter.state
        }
    }
}
