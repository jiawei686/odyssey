import SwiftUI

// Claude-owned preview/mock support surface.
// Use ClinicianGuidanceClientState and ClinicianGuidanceActionSet; do not
// construct or import PeerSession in child views.

// MARK: - Action-set helpers

extension ClinicianGuidanceActionSet {
    /// Forwards every action to a `ClinicianGuidanceControlling` session.
    /// Codex points this at the production `ClinicianGuidanceSession` during
    /// integration; the preview session below uses the same path.
    @MainActor
    static func forwarding(
        to controller: ClinicianGuidanceControlling
    ) -> ClinicianGuidanceActionSet {
        ClinicianGuidanceActionSet(
            setBoneVisible: { [weak controller] isVisible in
                controller?.setBoneVisible(isVisible)
            },
            setFracturePosition: { [weak controller] position in
                controller?.setFracturePosition(position)
            },
            setIncisionGuideVisible: { [weak controller] isVisible in
                controller?.setIncisionGuideVisible(isVisible)
            },
            clearGuidance: { [weak controller] in
                controller?.clearGuidance()
            },
            retry: { [weak controller] in
                controller?.retryConnection()
            }
        )
    }

    /// No-op actions for static SwiftUI previews.
    @MainActor
    static let previewInert = ClinicianGuidanceActionSet(
        setBoneVisible: { _ in },
        setFracturePosition: { _ in },
        setIncisionGuideVisible: { _ in },
        clearGuidance: {},
        retry: nil
    )
}

// MARK: - Fixture states

extension ClinicianGuidanceAppliedState {
    static func previewApplied(
        _ state: ClinicianGuidanceState,
        participantSide: ClinicianParticipantSide = .right,
        trackingStatus: ClinicianGuidanceTrackingStatus = .live,
        applicationStatus: ClinicianGuidanceApplicationStatus = .applied
    ) -> Self {
        Self(
            state: state,
            participantSide: participantSide,
            trackingStatus: trackingStatus,
            applicationStatus: applicationStatus,
            sourceMessageID: UUID(),
            sourceSequence: 1,
            detail: nil
        )
    }
}

extension ClinicianGuidanceClientState {
    private static let previewGuidance = ClinicianGuidanceState(
        showBone: true,
        fracturePosition: ClinicianForearmPosition(clamping: 0.42),
        showIncisionGuide: true
    )

    static let previewConnected = ClinicianGuidanceClientState(
        connectionStatus: .connected,
        desiredGuidanceState: previewGuidance,
        appliedGuidanceState: .previewApplied(previewGuidance),
        pendingMessageID: nil,
        lastAcknowledgedAt: Date().addingTimeInterval(-3),
        lastError: nil,
        peerDisplayName: "Apple Vision Pro"
    )

    static let previewSyncing = ClinicianGuidanceClientState(
        connectionStatus: .syncing,
        desiredGuidanceState: previewGuidance.settingFracturePosition(0.7),
        appliedGuidanceState: .previewApplied(previewGuidance),
        pendingMessageID: UUID(),
        lastAcknowledgedAt: Date().addingTimeInterval(-8),
        lastError: nil,
        peerDisplayName: "Apple Vision Pro"
    )

    static let previewStale = ClinicianGuidanceClientState(
        connectionStatus: .stale,
        desiredGuidanceState: previewGuidance,
        appliedGuidanceState: .previewApplied(
            previewGuidance,
            trackingStatus: .stale
        ),
        pendingMessageID: nil,
        lastAcknowledgedAt: Date().addingTimeInterval(-40),
        lastError: nil,
        peerDisplayName: "Apple Vision Pro"
    )

    static let previewDisconnected = ClinicianGuidanceClientState(
        connectionStatus: .disconnected,
        desiredGuidanceState: .initial,
        appliedGuidanceState: nil,
        pendingMessageID: nil,
        lastAcknowledgedAt: nil,
        lastError: nil,
        peerDisplayName: nil
    )

    static let previewError = ClinicianGuidanceClientState(
        connectionStatus: .error,
        desiredGuidanceState: previewGuidance,
        appliedGuidanceState: .previewApplied(previewGuidance),
        pendingMessageID: nil,
        lastAcknowledgedAt: Date().addingTimeInterval(-25),
        lastError: ClinicianGuidanceErrorPayload(
            code: .transportUnavailable,
            relatedMessageID: nil,
            detail: "Preview transport loss"
        ),
        peerDisplayName: "Apple Vision Pro"
    )
}

// MARK: - Interactive preview session

/// Frontend-only stand-in for the production `ClinicianGuidanceSession`.
/// It simulates the acknowledge round-trip so the desired/pending/applied
/// flow can be exercised in previews and simulator runs before integration.
/// It performs no networking and never claims physical AVP behavior.
@MainActor
final class ClinicianGuidancePreviewSession: ObservableObject, ClinicianGuidanceControlling {
    enum Scenario {
        case connectedReady
        case staleConnection
        case disconnected
        case recoverableError
    }

    @Published private(set) var clinicianGuidanceState: ClinicianGuidanceClientState

    private let acknowledgmentDelaySeconds: Double
    private var nextSequence: UInt64 = 1
    private var acknowledgmentTask: Task<Void, Never>?

    init(
        scenario: Scenario = .connectedReady,
        acknowledgmentDelaySeconds: Double = 0.6
    ) {
        self.acknowledgmentDelaySeconds = acknowledgmentDelaySeconds
        clinicianGuidanceState = switch scenario {
        case .connectedReady: .previewConnected
        case .staleConnection: .previewStale
        case .disconnected: .previewDisconnected
        case .recoverableError: .previewError
        }
    }

    // MARK: ClinicianGuidanceControlling

    func setBoneVisible(_ isVisible: Bool) {
        submit(
            clinicianGuidanceState.desiredGuidanceState
                .settingBoneVisible(isVisible)
        )
    }

    func setFracturePosition(_ normalizedPosition: Double) {
        submit(
            clinicianGuidanceState.desiredGuidanceState
                .settingFracturePosition(normalizedPosition)
        )
    }

    func setIncisionGuideVisible(_ isVisible: Bool) {
        submit(
            clinicianGuidanceState.desiredGuidanceState
                .settingIncisionGuideVisible(isVisible)
        )
    }

    func clearGuidance() {
        submit(
            clinicianGuidanceState.desiredGuidanceState.clearingGuidance()
        )
    }

    func retryConnection() {
        let current = clinicianGuidanceState
        guard current.connectionStatus.offersRetry else { return }
        clinicianGuidanceState = ClinicianGuidanceClientState(
            connectionStatus: .connected,
            desiredGuidanceState: current.desiredGuidanceState,
            appliedGuidanceState: current.appliedGuidanceState,
            pendingMessageID: nil,
            lastAcknowledgedAt: current.lastAcknowledgedAt,
            lastError: nil,
            peerDisplayName: current.peerDisplayName ?? "Apple Vision Pro"
        )
    }

    // MARK: Simulated round-trip

    private func submit(_ desired: ClinicianGuidanceState) {
        let current = clinicianGuidanceState
        guard current.canSendGuidanceCommands else { return }

        let messageID = UUID()
        clinicianGuidanceState = ClinicianGuidanceClientState(
            connectionStatus: .syncing,
            desiredGuidanceState: desired,
            appliedGuidanceState: current.appliedGuidanceState,
            pendingMessageID: messageID,
            lastAcknowledgedAt: current.lastAcknowledgedAt,
            lastError: nil,
            peerDisplayName: current.peerDisplayName
        )

        let delay = acknowledgmentDelaySeconds
        acknowledgmentTask?.cancel()
        acknowledgmentTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.acknowledge(messageID: messageID, desired: desired)
        }
    }

    private func acknowledge(
        messageID: UUID,
        desired: ClinicianGuidanceState
    ) {
        let current = clinicianGuidanceState
        guard current.pendingMessageID == messageID else { return }

        let sequence = nextSequence
        nextSequence += 1

        clinicianGuidanceState = ClinicianGuidanceClientState(
            connectionStatus: .connected,
            desiredGuidanceState: desired,
            appliedGuidanceState: ClinicianGuidanceAppliedState(
                state: desired,
                participantSide: current.appliedGuidanceState?.participantSide ?? .right,
                trackingStatus: .live,
                applicationStatus: .applied,
                sourceMessageID: messageID,
                sourceSequence: sequence,
                detail: nil
            ),
            pendingMessageID: nil,
            lastAcknowledgedAt: Date(),
            lastError: nil,
            peerDisplayName: current.peerDisplayName
        )
    }
}
