import SwiftUI

// Claude-owned companion presentation surface.
// Network ownership remains behind ClinicianGuidanceControlling.

/// Guidance controls for the clinician. Controls always display the
/// clinician's *desired* state; the diagram displays the AVP-confirmed
/// *applied* state. Emits `Section`s, so it must be embedded in a `Form`
/// or `List`.
struct ClinicianControlPanel: View {
    let state: ClinicianGuidanceClientState
    let actions: ClinicianGuidanceActionSet

    @State private var fractureSliderValue: Double = ClinicianForearmPosition.midpoint.value
    @State private var isEditingFractureSlider = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var controlsEnabled: Bool {
        state.canSendGuidanceCommands
    }

    var body: some View {
        Group {
            guidanceSection
            fractureSection
            clearSection
        }
        .onAppear(perform: syncSliderWithDesiredState)
        .onChange(of: state.desiredGuidanceState.fracturePosition) {
            syncSliderWithDesiredState()
        }
    }

    // MARK: - Guidance

    private var guidanceSection: some View {
        Section {
            if state.pendingMessageID != nil {
                HStack(spacing: 8) {
                    if reduceMotion {
                        Image(systemName: "hourglass")
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Waiting for Vision Pro to confirm…")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }

            Toggle("Show Bone", isOn: boneVisibleBinding)
                .disabled(!controlsEnabled)
                .accessibilityHint(
                    "Shows or hides the virtual forearm bone in the patient's view."
                )

            Toggle("Show Incision Guide", isOn: incisionGuideBinding)
                .disabled(!controlsEnabled)
                .accessibilityHint(
                    "Shows or hides the preset incision guide at the fracture position."
                )
        } header: {
            Text("Guidance")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "The incision guide is a preset educational marker, not a surgical plan. "
                        + "Turning it on without a fracture marker places the marker mid-shaft."
                )
                if let disabledExplanation {
                    Text(disabledExplanation)
                }
            }
        }
    }

    // MARK: - Fracture position

    private var fractureSection: some View {
        Section {
            Slider(
                value: $fractureSliderValue,
                in: 0...1,
                label: {
                    Text("Fracture Marker (Illustrative)")
                },
                minimumValueLabel: {
                    Text("Elbow")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                },
                maximumValueLabel: {
                    Text("Wrist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                },
                onEditingChanged: { editing in
                    isEditingFractureSlider = editing
                    if !editing {
                        // Contract rule: one send per interaction, on release.
                        actions.setFracturePosition(fractureSliderValue)
                    }
                }
            )
            .disabled(!controlsEnabled)
            .accessibilityValue(sliderAccessibilityValue)

            HStack {
                Text("Position")
                Spacer()
                Text(fractureValueDescription)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        } header: {
            Text("Fracture Marker (Illustrative)")
        } footer: {
            Text(
                "Illustrative — not a radiological finding. Measured from the elbow toward the wrist. "
                    + "The position is sent when you release the slider."
            )
        }
    }

    // MARK: - Clear

    private var clearSection: some View {
        Section {
            Button {
                actions.clearGuidance()
            } label: {
                Label("Clear Guidance", systemImage: "eraser")
            }
            .disabled(!controlsEnabled)
        } footer: {
            Text(
                "Immediately removes the fracture marker and incision guide "
                    + "from the patient's view. Bone visibility is unchanged."
            )
        }
    }

    // MARK: - Bindings and helpers

    private var boneVisibleBinding: Binding<Bool> {
        Binding(
            get: { state.desiredGuidanceState.showBone },
            set: { actions.setBoneVisible($0) }
        )
    }

    private var incisionGuideBinding: Binding<Bool> {
        Binding(
            get: { state.desiredGuidanceState.showIncisionGuide },
            set: { actions.setIncisionGuideVisible($0) }
        )
    }

    private func syncSliderWithDesiredState() {
        guard !isEditingFractureSlider else { return }
        if let desired = state.desiredGuidanceState.fracturePosition {
            fractureSliderValue = desired.value
        }
    }

    private var fractureValueDescription: String {
        if isEditingFractureSlider {
            return "\(ClinicianForearmZone.percentText(for: fractureSliderValue)) · "
                + ClinicianForearmZone.displayName(for: fractureSliderValue)
        }
        guard let desired = state.desiredGuidanceState.fracturePosition else {
            return "Not set"
        }
        return "\(ClinicianForearmZone.percentText(for: desired.value)) · "
            + ClinicianForearmZone.displayName(for: desired.value)
    }

    private var sliderAccessibilityValue: String {
        if state.desiredGuidanceState.fracturePosition == nil,
           !isEditingFractureSlider {
            return "Not set"
        }
        return "\(ClinicianForearmZone.percentText(for: fractureSliderValue)) "
            + "from the elbow, \(ClinicianForearmZone.name(for: fractureSliderValue))"
    }

    private var disabledExplanation: String? {
        guard !controlsEnabled else { return nil }
        if state.pendingMessageID != nil {
            return "Controls are paused until Vision Pro confirms the last change."
        }
        return "Controls are disabled while the connection is "
            + "\(state.connectionStatus.displayTitle.lowercased())."
    }
}

#Preview("Connected") {
    Form {
        ClinicianControlPanel(
            state: .previewConnected,
            actions: .previewInert
        )
    }
}

#Preview("Pending acknowledgment") {
    Form {
        ClinicianControlPanel(
            state: .previewSyncing,
            actions: .previewInert
        )
    }
}

#Preview("Disconnected") {
    Form {
        ClinicianControlPanel(
            state: .previewDisconnected,
            actions: .previewInert
        )
    }
}
