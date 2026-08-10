import SwiftUI

// Claude-owned patient-facing Home for the Odyssey headset experience.
//
// RECOVERABILITY CONTRACT
// This screen is the persistent root. It must never be dismissed by the app,
// and nothing in this file opens, dismisses or orders windows. Start/Resume/
// Return Home are intentions sent to the coordinator, which owns immersive
// lifecycle ordering so a window always remains.

public struct OdysseyAVPLandingScreen: View {
    public let state: OdysseyExperienceViewState
    public let actions: OdysseyExperienceActions

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(
        state: OdysseyExperienceViewState,
        actions: OdysseyExperienceActions
    ) {
        self.state = state
        self.actions = actions
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                identityCards
                connectionSection

                if let error = state.recoverableError {
                    OdysseyErrorNotice(
                        error: error,
                        retry: error.isRetryable ? actions.retryConnection : nil
                    )
                }

                primaryAction
                secondaryActions
                OdysseyEducationalDisclosure()
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(OdysseyCopy.appTitle)
    }

    // MARK: Sections

    /// The window chrome already carries the app title, so the header adds
    /// orientation rather than repeating it.
    private var header: some View {
        Text("A calm, guided look inside the reference anatomy.")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Side by side only when the window is genuinely wide; otherwise the
    /// card text hyphenates mid-word.
    private var identityCards: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize || horizontalSizeClass == .compact {
                VStack(spacing: 12) {
                    patientCard
                    experienceCard
                }
            } else {
                HStack(spacing: 12) {
                    patientCard
                    experienceCard
                }
            }
        }
    }

    private var patientCard: some View {
        OdysseyIdentityCard(
            title: "Patient",
            value: state.patient.displayName,
            detail: state.patient.detail,
            symbolName: "person.crop.circle"
        )
    }

    private var experienceCard: some View {
        OdysseyIdentityCard(
            title: "Experience",
            value: state.anatomy.displayName,
            detail: state.anatomy.detail,
            symbolName: "figure.arms.open"
        )
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            OdysseyConnectionStatusRow(
                connection: state.connection,
                peerDisplayName: state.peerDisplayName,
                isSimulatedSession: state.isSimulatedSession,
                lastConfirmedAt: nil
            )

            Text(guidanceModeExplanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
    }

    /// The patient is never blocked by a missing clinician device.
    private var guidanceModeExplanation: String {
        if state.isClinicianGuided {
            return "Your clinician's device is connected. They can guide this session."
        }
        return "No clinician device connected. You can still start a self-guided demonstration."
    }

    private var primaryAction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: state.canResumeSession ? actions.resumeSession : actions.startSession) {
                Label(
                    state.canResumeSession ? "Resume Experience" : "Start Experience",
                    systemImage: state.canResumeSession ? "arrow.clockwise.circle.fill" : "play.circle.fill"
                )
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .disabled(!state.canStartExperience)
            .accessibilityHint(
                state.canResumeSession
                    ? "Returns to the experience that is still running."
                    : "Begins the \(state.anatomy.displayName) experience."
            )

            if state.phase.isTransitioning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(transitionDescription)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var transitionDescription: String {
        switch state.phase {
        case .connecting: "Connecting to the clinician device…"
        case .startingSession: "Preparing the experience…"
        case .endingSession: "Ending the experience…"
        case .reconnecting: "Reconnecting…"
        case .home, .ready, .activeSession, .error: ""
        }
    }

    private var secondaryActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.connection.offersRetry {
                Button(action: actions.connect) {
                    Label(
                        state.connection == .notConnected
                            ? "Connect to Clinician Device"
                            : "Reconnect to Clinician Device",
                        systemImage: "antenna.radiowaves.left.and.right"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(state.phase.isTransitioning)
            }

            Button(action: actions.openDiagnostics) {
                Label("Setup & Diagnostics", systemImage: "wrench.and.screwdriver")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityHint("Opens technical setup information in a separate window.")
        }
    }
}
