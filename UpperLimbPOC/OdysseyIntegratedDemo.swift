#if DEBUG
import Foundation
import OSLog

enum OdysseyIntegratedDemoFeatureGate {
    static let launchArgument = "--odyssey-integrated-demo"

    static var isEnabled: Bool {
#if ODYSSEY_INTEGRATED_DEMO
        true
#else
        ProcessInfo.processInfo.arguments.contains(launchArgument)
#endif
    }
}

#if os(visionOS)
@MainActor
final class OdysseyAVPCoordinator: ObservableObject, OdysseyExperienceControlling {
    @Published private(set) var odysseyViewState = OdysseyExperienceViewState(
        assistantAvailability: .available,
        wearerView: .unavailable
    )
    @Published private(set) var showsDiagnostics = false

    private let peer: PeerSession
    private let session: OdysseyClinicalSessionService
    private let tracking: LandmarkTrackingService
    private let clinicalTwin: ClinicalTwinLabState
    private var refreshTask: Task<Void, Never>?
    private var openTwin: (() async -> Bool)?
    private var dismissImmersive: (() async -> Void)?
    private var presentAssistant: (() -> Void)?

    private let logger = Logger(
        subsystem: "com.marcel.UpperLimbPOC",
        category: "OdysseyAVP"
    )

    init(
        peer: PeerSession,
        session: OdysseyClinicalSessionService,
        tracking: LandmarkTrackingService,
        clinicalTwin: ClinicalTwinLabState
    ) {
        self.peer = peer
        self.session = session
        self.tracking = tracking
        self.clinicalTwin = clinicalTwin
        session.configureAVPRevealApplication { [weak clinicalTwin] value in
            clinicalTwin?.revealAnatomy = value
        }
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                do { try await Task.sleep(for: .milliseconds(200)) }
                catch { return }
            }
        }
    }

    func configureLifecycle(
        openTwin: @escaping () async -> Bool,
        dismissImmersive: @escaping () async -> Void,
        presentAssistant: @escaping () -> Void
    ) {
        self.openTwin = openTwin
        self.dismissImmersive = dismissImmersive
        self.presentAssistant = presentAssistant
    }

    func connect() {
        peer.start()
        refresh()
    }

    func retryConnection() {
        session.retryConnection()
        refresh()
    }

    func startSession() {
        guard odysseyViewState.canStartExperience else { return }
        odysseyViewState.phase = .startingSession
        Task { @MainActor [weak self] in
            guard let self, let openTwin else { return }
            let opened = await openTwin()
            if opened {
                self.odysseyViewState.phase = .activeSession
                self.odysseyViewState.desiredAnatomyVisible = true
                self.logger.notice("lifecycle=active renderer=ctDerivedMeshFallback")
            } else {
                self.odysseyViewState.phase = .error
                self.odysseyViewState.recoverableError = OdysseyRecoverableError(
                    message: "The CT-derived immersive twin could not open."
                )
            }
        }
    }

    func resumeSession() {
        guard odysseyViewState.canResumeSession else { return }
        odysseyViewState.phase = .activeSession
    }

    func endSession() {
        odysseyViewState.phase = .endingSession
        // Restore a usable root before dismissing immersive content.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.odysseyViewState.phase = .home
            self.showsDiagnostics = false
            self.tracking.stop()
            if let dismissImmersive { await dismissImmersive() }
            self.clinicalTwin.reset()
            self.session.resetForEndedSession()
            self.odysseyViewState = OdysseyExperienceViewState(
                connection: self.connectionState,
                peerDisplayName: self.session.isNegotiated ? "Clinician Companion" : nil,
                assistantAvailability: .available,
                wearerView: .unavailable
            )
            self.logger.notice("lifecycle=home immersive=dismissed")
        }
    }

    func returnHome() {
        odysseyViewState.canResumeSession = odysseyViewState.phase.isSessionOnScreen
        odysseyViewState.phase = .home
        showsDiagnostics = false
    }

    func openAssistant() {
        presentAssistant?()
    }

    func openDiagnostics() {
        showsDiagnostics = true
    }

    func closeDiagnostics() {
        showsDiagnostics = false
    }

    func setAnatomyVisible(_ isVisible: Bool) {
        // Deliberately unsupported in the integrated v1 contract. The CT twin
        // stays visible while its immersive session is active.
        logger.notice("action=show-anatomy rejected=capability-unavailable")
    }

    func setRevealAmount(_ amount: Double) {
        // The AVP is applied-state authority; local patient controls are not
        // exposed by this shell. Companion requests arrive via the service.
    }

    func markFracture() {}
    func undo() {}
    func clearGuidance() {}

    private func refresh() {
        if odysseyViewState.phase == .activeSession {
            attachTrackingWhenRendererIsReady()
        }

        let rendererReady: Bool
        switch clinicalTwin.rendererPhase {
        case .staticReady:
            rendererReady = true
        case .idle, .loading, .failed:
            rendererReady = false
        }
        let frameID = "right-\(tracking.handTrackingGeneration)-\(tracking.rightHandAnchorUpdateCount)"
        session.updateAVPEnvironment(
            rendererReady: rendererReady,
            resolution: tracking.rightForearmResolution,
            frameIdentifier: frameID
        )

        odysseyViewState.connection = connectionState
        odysseyViewState.peerDisplayName = session.isNegotiated
            ? "Clinician Companion"
            : nil
        odysseyViewState.trackingHealth = trackingHealth
        odysseyViewState.appliedAnatomyVisible = rendererReady
            && odysseyViewState.phase.isSessionOnScreen
        odysseyViewState.desiredAnatomyVisible = odysseyViewState.appliedAnatomyVisible
        odysseyViewState.appliedReveal = OdysseyRevealAmount(
            clamping: clinicalTwin.revealAnatomy
        )
        odysseyViewState.desiredReveal = odysseyViewState.appliedReveal
        odysseyViewState.hasPendingAcknowledgment = false
        odysseyViewState.lastConfirmedAt = session.avpAppliedState?.appliedAt
        odysseyViewState.supportsRevealControl = session.isNegotiated
        odysseyViewState.supportsAnatomyVisibilityControl = false
        odysseyViewState.supportsMarking = false
    }

    private func attachTrackingWhenRendererIsReady() {
        guard case .staticReady = clinicalTwin.rendererPhase,
              !clinicalTwin.trackingRequested else { return }
        clinicalTwin.requestRightForearmTracking()
        Task { @MainActor [weak tracking] in
            await tracking?.startHandJointProbe()
        }
    }

    private var connectionState: OdysseyConnectionState {
        if peer.isConnected {
            return session.isNegotiated ? .connected : .connecting
        }
        if peer.status == "Not started" || peer.status == "Stopped" {
            return .notConnected
        }
        if peer.status.localizedCaseInsensitiveContains("failed") {
            return .failed
        }
        return .searching
    }

    private var trackingHealth: OdysseyTrackingHealth {
        if let presentation = clinicalTwin.currentPresentation {
            switch presentation.mode {
            case .following: return .tracking
            case .staleFrozen: return .degraded
            case .staticReference:
                return clinicalTwin.trackingRequested ? .acquiring : .notStarted
            }
        }
        switch tracking.rightForearmResolution.state {
        case .live: return .tracking
        case .stale, .partial: return .degraded
        case .searching: return clinicalTwin.trackingRequested ? .acquiring : .notStarted
        case .failed: return .lost
        }
    }
}
#endif

#if os(iOS)
@MainActor
final class OdysseyCompanionCoordinator: ObservableObject, OdysseyExperienceControlling {
    @Published private(set) var odysseyViewState = OdysseyExperienceViewState()
    @Published private(set) var showsDiagnostics = false

    private let peer: PeerSession
    private let session: OdysseyClinicalSessionService
    private var refreshTask: Task<Void, Never>?

    init(peer: PeerSession, session: OdysseyClinicalSessionService) {
        self.peer = peer
        self.session = session
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                do { try await Task.sleep(for: .milliseconds(200)) }
                catch { return }
            }
        }
    }

    func connect() {
        odysseyViewState.phase = .connecting
        peer.start()
    }

    func retryConnection() {
        odysseyViewState.phase = .reconnecting
        session.retryConnection()
    }

    func startSession() {
        guard session.odysseyClinicalSessionState.connectionState == .connected else {
            odysseyViewState.recoverableError = OdysseyRecoverableError(
                message: "Connect to the real Apple Vision Pro before starting."
            )
            return
        }
        odysseyViewState.phase = .activeSession
    }

    func resumeSession() { odysseyViewState.phase = .activeSession }

    func endSession() {
        odysseyViewState.phase = .endingSession
        odysseyViewState.phase = .home
        odysseyViewState.canResumeSession = false
    }

    func returnHome() {
        odysseyViewState.canResumeSession = odysseyViewState.phase.isSessionOnScreen
        odysseyViewState.phase = .home
        showsDiagnostics = false
    }

    func openAssistant() {}
    func openDiagnostics() { showsDiagnostics = true }
    func closeDiagnostics() { showsDiagnostics = false }
    func setAnatomyVisible(_ isVisible: Bool) {}
    func setRevealAmount(_ amount: Double) { session.setReveal(amount) }
    func markFracture() {}
    func undo() {}
    func clearGuidance() {}

    private func refresh() {
        let client = session.odysseyClinicalSessionState
        odysseyViewState.connection = map(client.connectionState)
        odysseyViewState.peerDisplayName = client.peerDisplayName
        odysseyViewState.isSimulatedSession = false
        odysseyViewState.desiredAnatomyVisible = true
        odysseyViewState.appliedAnatomyVisible = client.appliedState != nil
        odysseyViewState.desiredReveal = OdysseyRevealAmount(
            clamping: client.desiredState.reveal.value
        )
        if let reveal = client.appliedState?.appliedReveal?.value {
            odysseyViewState.appliedReveal = OdysseyRevealAmount(clamping: reveal)
        }
        odysseyViewState.trackingHealth = map(client.trackingState)
        odysseyViewState.hasPendingAcknowledgment = client.isPending
        odysseyViewState.lastConfirmedAt = client.lastAppliedAt
        odysseyViewState.wearerView = .unavailable
        odysseyViewState.supportsRevealControl = client.negotiatedCapabilities
            .contains(.desiredReveal)
        odysseyViewState.supportsAnatomyVisibilityControl = false
        odysseyViewState.supportsMarking = false
        if let error = client.lastError {
            odysseyViewState.recoverableError = OdysseyRecoverableError(
                message: error.detail,
                isRetryable: error.isRecoverable
            )
        } else {
            odysseyViewState.recoverableError = nil
        }
        if odysseyViewState.phase == .connecting,
           client.connectionState == .connected {
            odysseyViewState.phase = .ready
        }
        if odysseyViewState.phase == .reconnecting,
           client.connectionState == .connected {
            odysseyViewState.phase = .activeSession
        }
    }

    private func map(
        _ connection: OdysseyClinicalSessionConnectionState
    ) -> OdysseyConnectionState {
        switch connection {
        case .disconnected: .notConnected
        case .connecting: .connecting
        case .connected, .syncing: .connected
        case .stale: .stale
        case .error: .failed
        }
    }

    private func map(_ tracking: OdysseyTwinTrackingState) -> OdysseyTrackingHealth {
        switch tracking {
        case .searching: .acquiring
        case .live: .tracking
        case .stale: .degraded
        case .failed: .lost
        }
    }
}
#endif
#endif
