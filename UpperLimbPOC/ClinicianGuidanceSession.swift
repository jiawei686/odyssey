import Foundation

@MainActor
protocol PeerSessionClinicianGuidanceDelegate: AnyObject {
    func peerSession(
        _ peer: PeerSession,
        connectionChanged isConnected: Bool
    )
    func peerSession(
        _ peer: PeerSession,
        received message: ClinicianGuidanceMessage
    )
}

@MainActor
final class ClinicianGuidanceSession: ObservableObject,
    ClinicianGuidanceControlling,
    PeerSessionClinicianGuidanceDelegate {
    @Published private(set) var clinicianGuidanceState: ClinicianGuidanceClientState
    @Published private(set) var avpRenderedGuidanceState: ClinicianGuidanceState?

    private let peer: PeerSession
    private var engine: ClinicianGuidanceSyncEngine
    private var heartbeatTask: Task<Void, Never>?

    var actionSet: ClinicianGuidanceActionSet {
        ClinicianGuidanceActionSet(
            setBoneVisible: { [weak self] in self?.setBoneVisible($0) },
            setFracturePosition: { [weak self] in self?.setFracturePosition($0) },
            setIncisionGuideVisible: { [weak self] in
                self?.setIncisionGuideVisible($0)
            },
            clearGuidance: { [weak self] in self?.clearGuidance() },
            retry: { [weak self] in self?.retryConnection() }
        )
    }

    init(
        role: ClinicianGuidanceEndpointRole,
        peer: PeerSession,
        localDisplayName: String
    ) {
        self.peer = peer
        engine = ClinicianGuidanceSyncEngine(
            role: role,
            localDisplayName: localDisplayName
        )
        clinicianGuidanceState = engine.clientState
        avpRenderedGuidanceState = engine.avpRenderedGuidanceState
        peer.setClinicianGuidanceDelegate(self)
    }

    func setBoneVisible(_ isVisible: Bool) {
        send(
            .set(
                clinicianGuidanceState.desiredGuidanceState
                    .settingBoneVisible(isVisible)
            )
        )
    }

    func setFracturePosition(_ normalizedPosition: Double) {
        guard normalizedPosition.isFinite else { return }
        send(
            .set(
                clinicianGuidanceState.desiredGuidanceState
                    .settingFracturePosition(normalizedPosition)
            )
        )
    }

    func setIncisionGuideVisible(_ isVisible: Bool) {
        send(
            .set(
                clinicianGuidanceState.desiredGuidanceState
                    .settingIncisionGuideVisible(isVisible)
            )
        )
    }

    func clearGuidance() {
        send(
            .clear(
                preservingBoneVisible:
                    clinicianGuidanceState.desiredGuidanceState.showBone
            )
        )
    }

    func retryConnection() {
        peer.restart()
    }

    func updateAVPTracking(
        status: ClinicianGuidanceTrackingStatus,
        participantSide: ClinicianParticipantSide,
        detail: String
    ) {
        apply(
            engine.updateAVPTracking(
                status: status,
                participantSide: participantSide,
                detail: detail,
                now: Date()
            )
        )
    }

    func peerSession(
        _ peer: PeerSession,
        connectionChanged isConnected: Bool
    ) {
        apply(engine.setTransportConnected(isConnected, now: Date()))
        if isConnected {
            startHeartbeatLoop()
        } else {
            heartbeatTask?.cancel()
            heartbeatTask = nil
        }
    }

    func peerSession(
        _ peer: PeerSession,
        received message: ClinicianGuidanceMessage
    ) {
        apply(engine.receive(message, now: Date()))
    }

    private func send(_ command: ClinicianGuidanceCommand) {
        apply(engine.sendDesiredState(command, now: Date()))
    }

    private func apply(_ effects: [ClinicianGuidanceSyncEffect]) {
        let nextClientState = engine.clientState
        if nextClientState != clinicianGuidanceState {
            clinicianGuidanceState = nextClientState
        }
        let nextRenderedState = engine.avpRenderedGuidanceState
        if nextRenderedState != avpRenderedGuidanceState {
            avpRenderedGuidanceState = nextRenderedState
        }
        for effect in effects {
            switch effect {
            case .send(let message):
                peer.send(message)
            }
        }
    }

    private func startHeartbeatLoop() {
        guard heartbeatTask == nil else { return }
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
                guard let self else { return }
                self.apply(self.engine.tick(now: Date()))
            }
        }
    }
}
