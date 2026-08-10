import SwiftUI

// Claude-owned clinician session surface.
//
// Controls show *desired* state; the viewer shows *applied* state; any gap is
// shown as "Applying…". When the connection is stale the displayed state is
// labelled "Last confirmed", new marking is disabled and reconnect is offered.

public struct OdysseyClinicianSessionScreen: View {
    public let state: OdysseyExperienceViewState
    public let actions: OdysseyExperienceActions

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(
        state: OdysseyExperienceViewState,
        actions: OdysseyExperienceActions
    ) {
        self.state = state
        self.actions = actions
    }

    public var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                ScrollView {
                    VStack(spacing: 18) {
                        statusPanel
                        viewer.frame(height: 300)
                        controls
                        endSessionButton
                    }
                    .padding(16)
                }
            } else {
                HStack(alignment: .top, spacing: 20) {
                    viewer
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    ScrollView {
                        VStack(spacing: 18) {
                            statusPanel
                            controls
                            endSessionButton
                        }
                    }
                    .frame(maxWidth: 420)
                }
                .padding(20)
            }
        }
        .navigationTitle(state.anatomy.displayName)
        // Sparing haptic, on acknowledgement only. Companion surface is iOS;
        // the equivalent API is not available on the visionOS deployment target.
#if os(iOS)
        .sensoryFeedback(.success, trigger: state.lastConfirmedAt)
#endif
    }

    // MARK: Status

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            OdysseyConnectionStatusRow(
                connection: state.connection,
                peerDisplayName: state.peerDisplayName,
                isSimulatedSession: state.isSimulatedSession,
                lastConfirmedAt: state.lastConfirmedAt
            )

            OdysseyTrackingStatusRow(tracking: state.trackingHealth)

            OdysseyApplyingIndicator(
                isApplying: state.isApplying,
                showsLastConfirmedOnly: state.showsLastConfirmedOnly
            )

            if state.connection.offersRetry {
                Button(action: actions.retryConnection) {
                    Label("Reconnect", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let error = state.recoverableError {
                Label(error.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
    }

    // MARK: Viewer

    private var viewer: some View {
        OdysseyReferenceAnatomyView(
            reveal: state.appliedReveal,
            isAnatomyVisible: state.appliedAnatomyVisible,
            markers: state.appliedMarkers,
            wearerView: state.wearerView,
            showsLastConfirmedOnly: state.showsLastConfirmedOnly
        )
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Show Anatomy", isOn: anatomyVisibleBinding)
                .disabled(!state.canSetAnatomyVisibility)
                .accessibilityHint("Shows or hides the reference anatomy in the patient's view.")

            OdysseyRevealControl(
                desired: state.desiredReveal,
                applied: state.appliedReveal,
                isEnabled: state.canSetReveal,
                onCommit: actions.setRevealAmount
            )

            Divider()

            VStack(spacing: 10) {
                Button(action: actions.markFracture) {
                    Label("Mark Fracture", systemImage: "mappin.and.ellipse")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!state.canMark)
                .accessibilityHint(
                    "Places an illustrative educational marker on the reference anatomy."
                )

                HStack(spacing: 10) {
                    Button(action: actions.undo) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!state.canUndo)

                    Button(role: .destructive, action: actions.clearGuidance) {
                        Label("Clear", systemImage: "eraser")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!state.canClearGuidance)
                }
            }

            if let disabledExplanation {
                Text(disabledExplanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if state.assistantAvailability.isAvailable {
                Button(action: actions.openAssistant) {
                    Label("Voice Assistant", systemImage: "bubble.left.and.text.bubble.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Text(
                "Markers are illustrative educational annotations — not a "
                    + "radiological finding or a surgical plan."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
    }

    private var anatomyVisibleBinding: Binding<Bool> {
        Binding(
            get: { state.desiredAnatomyVisible },
            set: { actions.setAnatomyVisible($0) }
        )
    }

    private var disabledExplanation: String? {
        guard !state.canSendGuidance else {
            if !state.supportsMarking {
                return "Surface-to-Bone reveal is available. On-model marking is unavailable until the AVP negotiates projection and annotation support."
            }
            return nil
        }
        if state.hasPendingAcknowledgment {
            return "Controls are paused until Vision Pro confirms the last change."
        }
        switch state.connection {
        case .stale:
            return "Connection is stale. The view above is the last confirmed state; reconnect to guide again."
        case .failed, .notConnected:
            return "Not connected to Vision Pro. Reconnect to guide the session."
        case .searching, .connecting:
            return "Waiting for the Vision Pro connection."
        case .connected:
            return state.phase == .activeSession ? nil : "Start the session to guide the patient."
        }
    }

    // MARK: End

    private var endSessionButton: some View {
        VStack(spacing: 8) {
            Button(action: actions.endSession) {
                Label("End Session", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(state.phase == .endingSession)
            .accessibilityHint("Ends the session and returns to the patient screen.")

            if state.phase == .endingSession {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Ending the session…").foregroundStyle(.secondary)
                }
                .font(.footnote)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
