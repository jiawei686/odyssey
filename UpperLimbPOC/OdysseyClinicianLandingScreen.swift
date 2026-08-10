import SwiftUI

// Claude-owned clinician landing screen: Open → Connect → Guide.
// One dominant action at a time; Setup & Diagnostics stays secondary.

public struct OdysseyClinicianLandingScreen: View {
    public let state: OdysseyExperienceViewState
    public let actions: OdysseyExperienceActions

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        state: OdysseyExperienceViewState,
        actions: OdysseyExperienceActions
    ) {
        self.state = state
        self.actions = actions
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                identityCards
                connectionPanel

                if let error = state.recoverableError {
                    OdysseyErrorNotice(
                        error: error,
                        retry: error.isRetryable ? actions.retryConnection : nil
                    )
                }

                dominantAction
                diagnosticsLink
                OdysseyEducationalDisclosure()
            }
            .padding(20)
            .frame(maxWidth: contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Odyssey")
    }

    private var contentWidth: CGFloat {
        horizontalSizeClass == .regular ? 620 : .infinity
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(OdysseyCopy.appTitle)
                .font(.title.weight(.semibold))
            Text("Clinician companion")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var identityCards: some View {
        Group {
            if horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 12) {
                    patientCard
                    modelCard
                }
            } else {
                VStack(spacing: 12) {
                    patientCard
                    modelCard
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

    private var modelCard: some View {
        OdysseyIdentityCard(
            title: "Model",
            value: state.anatomy.displayName,
            detail: state.anatomy.detail,
            symbolName: "figure.arms.open"
        )
    }

    private var connectionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            OdysseyConnectionStatusRow(
                connection: state.connection,
                peerDisplayName: state.peerDisplayName,
                isSimulatedSession: state.isSimulatedSession,
                lastConfirmedAt: nil
            )

            if state.canResumeSession {
                Label(
                    "A session is still running on the headset.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
    }

    /// Exactly one dominant action, chosen by phase.
    @ViewBuilder
    private var dominantAction: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.canResumeSession {
                primaryButton(
                    title: "Resume Patient Session",
                    symbol: "arrow.clockwise.circle.fill",
                    hint: "Returns to the session already running on the headset.",
                    action: actions.resumeSession,
                    isEnabled: !state.phase.isTransitioning
                )
            } else if state.connection.isUsable {
                primaryButton(
                    title: "Start Patient Session",
                    symbol: "play.circle.fill",
                    hint: "Starts the \(state.anatomy.displayName) session on the headset.",
                    action: actions.startSession,
                    isEnabled: !state.phase.isTransitioning
                )
            } else if state.connection.offersRetry && state.connection != .notConnected {
                primaryButton(
                    title: "Reconnect to Vision Pro",
                    symbol: "arrow.triangle.2.circlepath",
                    hint: "Tries the connection again.",
                    action: actions.retryConnection,
                    isEnabled: !state.phase.isTransitioning
                )
            } else {
                primaryButton(
                    title: "Connect to Vision Pro",
                    symbol: "antenna.radiowaves.left.and.right",
                    hint: "Looks for the patient's Apple Vision Pro.",
                    action: actions.connect,
                    isEnabled: !state.phase.isTransitioning
                )
            }

            if state.phase.isTransitioning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(transitionDescription).foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func primaryButton(
        title: String,
        symbol: String,
        hint: String,
        action: @escaping () -> Void,
        isEnabled: Bool
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isEnabled)
        .accessibilityHint(hint)
    }

    private var transitionDescription: String {
        switch state.phase {
        case .connecting: "Looking for Apple Vision Pro…"
        case .startingSession: "Starting the session…"
        case .endingSession: "Ending the session…"
        case .reconnecting: "Reconnecting…"
        case .home, .ready, .activeSession, .error: ""
        }
    }

    private var diagnosticsLink: some View {
        Button(action: actions.openDiagnostics) {
            Label("Setup & Diagnostics", systemImage: "wrench.and.screwdriver")
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Opens calibration and technical tools.")
    }
}
