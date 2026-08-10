import SwiftUI

// Claude-owned preview/mock support for the Odyssey session shell.
// Frontend only: performs no networking, opens no windows and never claims
// physical Apple Vision Pro behaviour. Every mock session is flagged with
// `isSimulatedSession = true` so no screen can imply a real device.

// MARK: - Fixtures

public extension OdysseyExperienceViewState {
    private static let markers = [
        OdysseyEducationalMarker(normalizedPosition: 0.46, label: "Mid-shaft")
    ]

    /// 1. Cold launch, nothing connected.
    static let previewDisconnected = OdysseyExperienceViewState(
        phase: .home,
        connection: .notConnected
    )

    /// 2. Actively searching/connecting.
    static let previewConnecting = OdysseyExperienceViewState(
        phase: .connecting,
        connection: .connecting,
        peerDisplayName: "Apple Vision Pro",
        isSimulatedSession: true
    )

    /// 3. Connected and ready to start.
    static let previewReady = OdysseyExperienceViewState(
        phase: .ready,
        connection: .connected,
        peerDisplayName: "Apple Vision Pro",
        isSimulatedSession: true,
        trackingHealth: .notStarted,
        assistantAvailability: .available
    )

    /// 4. Active session, everything confirmed.
    static let previewActiveSession = OdysseyExperienceViewState(
        phase: .activeSession,
        connection: .connected,
        peerDisplayName: "Apple Vision Pro",
        isSimulatedSession: true,
        trackingHealth: .tracking,
        appliedAnatomyVisible: true,
        desiredAnatomyVisible: true,
        appliedReveal: OdysseyRevealAmount(clamping: 0.6),
        desiredReveal: OdysseyRevealAmount(clamping: 0.6),
        appliedMarkers: markers,
        lastConfirmedAt: Date().addingTimeInterval(-4),
        assistantAvailability: .available
    )

    /// 5. Clinician intent not yet acknowledged.
    static let previewPendingAcknowledgment = OdysseyExperienceViewState(
        phase: .activeSession,
        connection: .connected,
        peerDisplayName: "Apple Vision Pro",
        isSimulatedSession: true,
        trackingHealth: .tracking,
        appliedAnatomyVisible: true,
        desiredAnatomyVisible: true,
        appliedReveal: OdysseyRevealAmount(clamping: 0.3),
        desiredReveal: OdysseyRevealAmount(clamping: 0.9),
        appliedMarkers: markers,
        hasPendingAcknowledgment: true,
        lastConfirmedAt: Date().addingTimeInterval(-9),
        assistantAvailability: .available
    )

    /// 6. Stale connection — displayed state is last confirmed only.
    static let previewStale = OdysseyExperienceViewState(
        phase: .reconnecting,
        connection: .stale,
        peerDisplayName: "Apple Vision Pro",
        isSimulatedSession: true,
        trackingHealth: .degraded,
        appliedAnatomyVisible: true,
        desiredAnatomyVisible: true,
        appliedReveal: OdysseyRevealAmount(clamping: 0.6),
        desiredReveal: OdysseyRevealAmount(clamping: 0.6),
        appliedMarkers: markers,
        lastConfirmedAt: Date().addingTimeInterval(-42),
        assistantAvailability: .available
    )

    /// 7. Recoverable error.
    static let previewError = OdysseyExperienceViewState(
        phase: .error,
        connection: .failed,
        peerDisplayName: "Apple Vision Pro",
        isSimulatedSession: true,
        trackingHealth: .notStarted,
        recoverableError: OdysseyRecoverableError(
            message: "Lost the connection to Apple Vision Pro."
        )
    )

    /// 8. Session ended, back at Home, resumable.
    static let previewSessionEndedHome = OdysseyExperienceViewState(
        phase: .home,
        connection: .connected,
        peerDisplayName: "Apple Vision Pro",
        isSimulatedSession: true,
        trackingHealth: .notStarted,
        lastConfirmedAt: Date().addingTimeInterval(-15),
        assistantAvailability: .available,
        canResumeSession: true
    )

    /// 9. Live wearer view unavailable (the only honest production value).
    static let previewWearerViewUnavailable = OdysseyExperienceViewState(
        phase: .activeSession,
        connection: .connected,
        peerDisplayName: "Apple Vision Pro",
        isSimulatedSession: true,
        trackingHealth: .tracking,
        appliedAnatomyVisible: true,
        desiredAnatomyVisible: true,
        appliedReveal: .surface,
        desiredReveal: .surface,
        lastConfirmedAt: Date().addingTimeInterval(-2),
        wearerView: .unavailable
    )
}

// MARK: - Interactive mock coordinator

/// Frontend-only stand-in for the production lifecycle/session coordinator.
/// It models the phase machine and the desired→applied acknowledgement delay
/// so the shell can be exercised before integration. It never opens or
/// dismisses windows — `returnHome()`/`endSession()` only change phase, which
/// is exactly what keeps Home recoverable in the real app.
@MainActor
public final class OdysseyPreviewCoordinator: ObservableObject, OdysseyExperienceControlling {
    public enum Scenario {
        case disconnected
        case ready
        case activeSession
        case stale
        case error
        case sessionEndedHome
    }

    @Published public private(set) var odysseyViewState: OdysseyExperienceViewState

    private let stepDelay: Double
    private var work: Task<Void, Never>?

    public init(scenario: Scenario = .disconnected, stepDelay: Double = 0.6) {
        self.stepDelay = stepDelay
        odysseyViewState = switch scenario {
        case .disconnected: .previewDisconnected
        case .ready: .previewReady
        case .activeSession: .previewActiveSession
        case .stale: .previewStale
        case .error: .previewError
        case .sessionEndedHome: .previewSessionEndedHome
        }
    }

    // MARK: Lifecycle intentions

    public func connect() {
        guard !odysseyViewState.phase.isTransitioning else { return }
        mutate {
            $0.phase = .connecting
            $0.connection = .connecting
            $0.recoverableError = nil
            $0.isSimulatedSession = true
            $0.peerDisplayName = "Apple Vision Pro"
        }
        after { [weak self] in
            self?.mutate {
                $0.phase = .ready
                $0.connection = .connected
                $0.assistantAvailability = .available
            }
        }
    }

    public func retryConnection() {
        connect()
    }

    public func startSession() {
        guard odysseyViewState.canStartExperience else { return }
        mutate {
            $0.phase = .startingSession
            $0.trackingHealth = .acquiring
            $0.recoverableError = nil
        }
        after { [weak self] in
            self?.mutate {
                $0.phase = .activeSession
                $0.trackingHealth = .tracking
                $0.appliedAnatomyVisible = true
                $0.desiredAnatomyVisible = true
                $0.lastConfirmedAt = Date()
                $0.canResumeSession = false
            }
        }
    }

    public func resumeSession() {
        mutate {
            $0.phase = .activeSession
            $0.canResumeSession = false
            $0.trackingHealth = .tracking
        }
    }

    /// Phase-only teardown. Window ordering belongs to the production
    /// coordinator; Home is never dismissed.
    public func endSession() {
        guard odysseyViewState.phase != .endingSession else { return }
        mutate {
            $0.phase = .endingSession
            $0.hasPendingAcknowledgment = false
        }
        after { [weak self] in
            self?.mutate {
                $0.phase = .home
                $0.trackingHealth = .notStarted
                $0.appliedAnatomyVisible = false
                $0.desiredAnatomyVisible = false
                $0.appliedMarkers = []
                $0.appliedReveal = .surface
                $0.desiredReveal = .surface
                $0.canResumeSession = false
            }
        }
    }

    public func returnHome() {
        mutate {
            $0.phase = .home
            $0.canResumeSession = $0.trackingHealth == .tracking
        }
    }

    public func openAssistant() {}
    public func openDiagnostics() {}

    // MARK: Guidance intentions

    public func setAnatomyVisible(_ isVisible: Bool) {
        guard odysseyViewState.canSendGuidance else { return }
        mutate {
            $0.desiredAnatomyVisible = isVisible
            $0.hasPendingAcknowledgment = true
        }
        acknowledge { $0.appliedAnatomyVisible = isVisible }
    }

    public func setRevealAmount(_ amount: Double) {
        guard odysseyViewState.canSendGuidance else { return }
        let clamped = OdysseyRevealAmount(clamping: amount)
        mutate {
            $0.desiredReveal = clamped
            $0.hasPendingAcknowledgment = true
        }
        acknowledge { $0.appliedReveal = clamped }
    }

    public func markFracture() {
        guard odysseyViewState.canSendGuidance else { return }
        mutate { $0.hasPendingAcknowledgment = true }
        acknowledge {
            $0.appliedMarkers.append(
                OdysseyEducationalMarker(normalizedPosition: 0.46)
            )
        }
    }

    public func undo() {
        guard odysseyViewState.canUndo else { return }
        mutate { $0.hasPendingAcknowledgment = true }
        acknowledge {
            if !$0.appliedMarkers.isEmpty { $0.appliedMarkers.removeLast() }
        }
    }

    public func clearGuidance() {
        guard odysseyViewState.canClearGuidance else { return }
        mutate { $0.hasPendingAcknowledgment = true }
        acknowledge { $0.appliedMarkers.removeAll() }
    }

    // MARK: Helpers

    private func mutate(_ change: (inout OdysseyExperienceViewState) -> Void) {
        var next = odysseyViewState
        change(&next)
        odysseyViewState = next
    }

    private func after(_ block: @escaping () -> Void) {
        let delay = stepDelay
        work?.cancel()
        work = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, self != nil else { return }
            block()
        }
    }

    private func acknowledge(_ apply: @escaping (inout OdysseyExperienceViewState) -> Void) {
        after { [weak self] in
            self?.mutate {
                apply(&$0)
                $0.hasPendingAcknowledgment = false
                $0.lastConfirmedAt = Date()
            }
        }
    }
}

// MARK: - Routed shells (recoverability demonstration)

/// Routes phase → screen for the headset. Home is the fixed root: every path
/// out of a session lands here, and no branch can produce "no screen".
public struct OdysseyAVPShell: View {
    public let state: OdysseyExperienceViewState
    public let actions: OdysseyExperienceActions

    public init(state: OdysseyExperienceViewState, actions: OdysseyExperienceActions) {
        self.state = state
        self.actions = actions
    }

    public var body: some View {
        NavigationStack {
            if state.phase.isSessionOnScreen {
                OdysseyAVPSessionScreen(state: state, actions: actions)
            } else {
                OdysseyAVPLandingScreen(state: state, actions: actions)
            }
        }
    }
}

/// Routes phase → screen for the clinician companion.
public struct OdysseyClinicianShell: View {
    public let state: OdysseyExperienceViewState
    public let actions: OdysseyExperienceActions

    public init(state: OdysseyExperienceViewState, actions: OdysseyExperienceActions) {
        self.state = state
        self.actions = actions
    }

    public var body: some View {
        NavigationStack {
            if state.phase.isSessionOnScreen {
                OdysseyClinicianSessionScreen(state: state, actions: actions)
            } else {
                OdysseyClinicianLandingScreen(state: state, actions: actions)
            }
        }
    }
}

/// Live mock host used by previews and the simulator harness.
public struct OdysseyPreviewHost: View {
    public enum Surface { case headset, clinician }

    @StateObject private var coordinator: OdysseyPreviewCoordinator
    private let surface: Surface

    public init(
        surface: Surface,
        scenario: OdysseyPreviewCoordinator.Scenario = .disconnected
    ) {
        self.surface = surface
        _coordinator = StateObject(
            wrappedValue: OdysseyPreviewCoordinator(scenario: scenario)
        )
    }

    public var body: some View {
        let actions = OdysseyExperienceActions.forwarding(to: coordinator)
        switch surface {
        case .headset:
            OdysseyAVPShell(state: coordinator.odysseyViewState, actions: actions)
        case .clinician:
            OdysseyClinicianShell(state: coordinator.odysseyViewState, actions: actions)
        }
    }
}

// MARK: - Previews

#Preview("Headset — Home, disconnected") {
    OdysseyAVPShell(state: .previewDisconnected, actions: .inert)
}

#Preview("Headset — connecting") {
    OdysseyAVPShell(state: .previewConnecting, actions: .inert)
}

#Preview("Headset — ready") {
    OdysseyAVPShell(state: .previewReady, actions: .inert)
}

#Preview("Headset — active session") {
    OdysseyAVPShell(state: .previewActiveSession, actions: .inert)
}

#Preview("Headset — session ended, resumable") {
    OdysseyAVPShell(state: .previewSessionEndedHome, actions: .inert)
}

#Preview("Headset — interactive") {
    OdysseyPreviewHost(surface: .headset)
}

#Preview("Clinician — landing, disconnected") {
    OdysseyClinicianShell(state: .previewDisconnected, actions: .inert)
}

#Preview("Clinician — ready to start") {
    OdysseyClinicianShell(state: .previewReady, actions: .inert)
}

#Preview("Clinician — active session") {
    OdysseyClinicianShell(state: .previewActiveSession, actions: .inert)
}

#Preview("Clinician — pending acknowledgment") {
    OdysseyClinicianShell(state: .previewPendingAcknowledgment, actions: .inert)
}

#Preview("Clinician — stale connection") {
    OdysseyClinicianShell(state: .previewStale, actions: .inert)
}

#Preview("Clinician — recoverable error") {
    OdysseyClinicianShell(state: .previewError, actions: .inert)
}

#Preview("Clinician — wearer view unavailable") {
    OdysseyClinicianShell(state: .previewWearerViewUnavailable, actions: .inert)
}

#Preview("Clinician — interactive") {
    OdysseyPreviewHost(surface: .clinician)
}
