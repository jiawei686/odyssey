import ARKit
import SwiftUI

struct JointProbeView: View {
    @EnvironmentObject private var tracking: LandmarkTrackingService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var immersiveSpaceIsOpen = false
    @State private var probeOwnsTrackingSession = false
    @State private var launchError: String?

    private var selectedForearmResolution: AVPForearmOverlayResolution {
        tracking.probeSelectedHand == .left
            ? tracking.leftForearmResolution
            : tracking.rightForearmResolution
    }

    private var selectedTrackedJointCount: Int {
        tracking.probeSelectedHand == .left
            ? tracking.leftHandJointTransforms.count
            : tracking.rightHandJointTransforms.count
    }

    private var armDetected: Bool {
        tracking.handPhase == .running
            && selectedForearmResolution.state == .live
            && selectedForearmResolution.trackedPointCount == 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            stageStrip
            actionPanel

            if let launchError {
                Label(launchError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 12)

            Label(
                "Wearer-only educational overlay. The bones follow tracked hand joints; the forearm uses wrist and near-elbow endpoints and is not a validated anatomical registration.",
                systemImage: "info.circle.fill"
            )
            .font(.callout.weight(.semibold))
            .foregroundStyle(.orange)

            HStack {
                Button("Reset", systemImage: "arrow.counterclockwise") {
                    tracking.stop()
                    probeOwnsTrackingSession = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Close") {
                    Task {
                        tracking.stop()
                        await dismissImmersiveSpace()
                        dismiss()
                        dismissWindow(id: "JointProbe")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(32)
        .onDisappear {
            if probeOwnsTrackingSession {
                tracking.stop()
            }
            Task { await dismissImmersiveSpace() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Wearer Arm Overlay")
                .font(.largeTitle.bold())
            Text("Open, detect your arm, then show the tracked 3D bones.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var stageStrip: some View {
        HStack(spacing: 12) {
            stageBadge(number: 1, title: "Open", complete: immersiveSpaceIsOpen)
            stageBadge(number: 2, title: "Detect", complete: armDetected)
            stageBadge(
                number: 3,
                title: "3D bones",
                complete: tracking.probeBoneVisible && armDetected
            )
        }
    }

    private var actionPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button {
                Task { await openAndDetect() }
            } label: {
                Label(
                    tracking.handPhase == .running
                        ? (armDetected ? "Arm detected" : "Detecting your arm…")
                        : "Open & detect arm",
                    systemImage: armDetected
                        ? "checkmark.circle.fill"
                        : "hand.raised.fingers.spread"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .disabled(tracking.handPhase == .running)

            if tracking.handPhase == .running {
                HStack {
                    Label(
                        armDetected ? "Detected" : "Move one arm into view",
                        systemImage: armDetected
                            ? "checkmark.circle.fill"
                            : "viewfinder"
                    )
                    .foregroundStyle(armDetected ? .green : .orange)
                    Spacer()
                    Text(
                        "\(tracking.probeSelectedHand == .left ? "Left" : "Right") · \(selectedTrackedJointCount) joints"
                    )
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }

            Button {
                tracking.setProbeBoneVisible(!tracking.probeBoneVisible)
            } label: {
                Label(
                    tracking.probeBoneVisible
                        ? "Hide 3D bone overlay"
                        : "Show 3D bone overlay",
                    systemImage: tracking.probeBoneVisible
                        ? "eye.slash.fill"
                        : "move.3d"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(tracking.probeBoneVisible ? .orange : .cyan)
            .controlSize(.extraLarge)
            .disabled(!armDetected)

            Text(
                tracking.probeBoneVisible
                    ? "Opaque joint-driven bones are following the selected hand and forearm."
                    : "The cyan dots confirm detection. Show the bones when all three forearm points are live."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private func stageBadge(
        number: Int,
        title: String,
        complete: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: complete ? "checkmark.circle.fill" : "\(number).circle")
            Text(title)
                .fontWeight(.semibold)
        }
        .foregroundStyle(complete ? .green : .secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: Capsule())
    }

    @MainActor
    private func openAndDetect() async {
        guard await openProbeSpace() else { return }
        let wasIdle = tracking.handPhase == .idle
        await tracking.startHandJointProbe()
        probeOwnsTrackingSession = wasIdle && tracking.handPhase == .running
    }

    @MainActor
    private func openProbeSpace() async -> Bool {
        guard !immersiveSpaceIsOpen else { return true }
        launchError = nil
        switch await openImmersiveSpace(id: "JointProbeSpace") {
        case .opened:
            immersiveSpaceIsOpen = true
            return true
        case .userCancelled:
            launchError = "The mixed-reality view was cancelled."
            return false
        case .error:
            launchError = "The mixed-reality view could not open. Try again."
            return false
        @unknown default:
            launchError = "The mixed-reality view returned an unknown result."
            return false
        }
    }
}
