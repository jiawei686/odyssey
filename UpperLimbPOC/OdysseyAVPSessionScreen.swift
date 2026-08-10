import SwiftUI

// Claude-owned patient-facing session surface for the Odyssey headset.
//
// The patient sees confirmed (applied) state only. Unacknowledged clinician
// intent appears at most as "updating…", never as a completed change.
// No development console, no calibration controls, no procedural dots
// presented as anatomy, and no dismissWindow anywhere in this file.

public struct OdysseyAVPSessionScreen: View {
    public let state: OdysseyExperienceViewState
    public let actions: OdysseyExperienceActions

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
                statusPanel

                if let error = state.recoverableError {
                    OdysseyErrorNotice(
                        error: error,
                        retry: error.isRetryable ? actions.retryConnection : nil
                    )
                }

                actionRow
                OdysseyEducationalDisclosure()
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(state.anatomy.displayName)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.anatomy.displayName)
                .font(.largeTitle.weight(.semibold))
            Text(state.patient.displayName)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            OdysseyTrackingStatusRow(tracking: state.trackingHealth)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Label(state.clinicianGuidanceSummary, systemImage: guidanceSymbol)
                    .font(.headline)

                Text(appliedSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Session status")
            .accessibilityValue("\(state.clinicianGuidanceSummary). \(appliedSummary)")
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(.regularMaterial))
    }

    private var guidanceSymbol: String {
        if state.hasPendingAcknowledgment { return "arrow.triangle.2.circlepath" }
        return state.isClinicianGuided ? "person.wave.2" : "person"
    }

    /// Describes only what the headset has actually applied.
    private var appliedSummary: String {
        guard state.appliedAnatomyVisible else {
            return "Anatomy is hidden."
        }
        var text = "Showing \(state.appliedReveal.layerName.lowercased())."
        if !state.appliedMarkers.isEmpty {
            let count = state.appliedMarkers.count
            text += " \(count) educational marker\(count == 1 ? "" : "s") placed."
        }
        return text
    }

    private var actionRow: some View {
        VStack(spacing: 12) {
            Button(action: actions.endSession) {
                Label("End Session", systemImage: "stop.circle.fill")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .disabled(state.phase == .endingSession)
            .accessibilityHint("Ends the experience and returns to the home screen.")

            if state.phase == .endingSession {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Ending the experience…").foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }

            if state.assistantAvailability.isAvailable {
                Button(action: actions.openAssistant) {
                    Label("Ask the Assistant", systemImage: "bubble.left.and.text.bubble.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityHint("Opens the optional voice assistant in a separate window.")
            }

            Button(action: actions.returnHome) {
                Label("Return Home", systemImage: "house")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityHint("Returns to the home screen and leaves the experience running.")
        }
    }
}
