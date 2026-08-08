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

    private var expectedJointCount: Int {
        HandSkeleton.JointName.allCases.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                capabilityBoundary
                liveSignal
                controls
                if let report = tracking.probeReport {
                    reportView(report)
                }
                interpretation
            }
            .padding(28)
        }
        .task {
            await openProbeSpace()
        }
        .onDisappear {
            if probeOwnsTrackingSession {
                tracking.stop()
            }
            Task { await dismissImmersiveSpace() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AVP Joint Capability Probe")
                        .font(.largeTitle.bold())
                    Text("A physical-device research test for the hand-joint data standard visionOS actually exposes.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") {
                    Task {
                        await dismissImmersiveSpace()
                        dismiss()
                        dismissWindow(id: "JointProbe")
                    }
                }
                .buttonStyle(.bordered)
            }

            Label(
                tracking.handPhase.message,
                systemImage: tracking.handPhase == .running
                    ? "waveform.path.ecg"
                    : "hand.raised"
            )
            .font(.headline)
            .foregroundStyle(tracking.handPhase == .running ? .green : .orange)

            if let launchError {
                Text(launchError)
                    .foregroundStyle(.red)
            }
        }
    }

    private var capabilityBoundary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "Native result: wearer's hands only",
                systemImage: "hand.raised.fingers.spread"
            )
            .foregroundStyle(.green)

            Label(
                "Whole-body ARKit: unavailable in standard visionOS",
                systemImage: "figure.stand.line.dotted.figure.stand"
            )
            .foregroundStyle(.orange)

            Label(
                "LiDAR scene mesh has no joint labels",
                systemImage: "square.3.layers.3d"
            )
            .foregroundStyle(.orange)

            Text("Detecting the joints of another person would require approved enterprise main-camera access plus a validated Vision/Core ML pose provider, or an external camera source.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var liveSignal: some View {
        HStack(spacing: 16) {
            handCard(
                title: "Left hand",
                color: .cyan,
                trackedCount: tracking.leftHandJointTransforms.count
            )
            handCard(
                title: "Right hand",
                color: .orange,
                trackedCount: tracking.rightHandJointTransforms.count
            )
        }
    }

    private func handCard(
        title: String,
        color: Color,
        trackedCount: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text("\(trackedCount) / \(expectedJointCount)")
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
            Text("currently tracked joints")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button("Start tracking", systemImage: "play.fill") {
                    Task {
                        let wasIdle = tracking.handPhase == .idle
                        await tracking.startHandJointProbe()
                        probeOwnsTrackingSession = wasIdle && tracking.handPhase == .running
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(tracking.handPhase == .running)

                Button("Run 30-second continuity test", systemImage: "timer") {
                    tracking.beginProbeMeasurement()
                }
                .buttonStyle(.borderedProminent)
                .disabled(tracking.handPhase != .running || tracking.isProbeRecording)

                Button("Stop & summarize", systemImage: "stop.fill") {
                    tracking.finishProbeMeasurement()
                }
                .buttonStyle(.bordered)
                .disabled(!tracking.isProbeRecording)

                Button("Reset", systemImage: "arrow.counterclockwise") {
                    tracking.resetProbeMeasurement()
                }
                .buttonStyle(.bordered)
            }

            if tracking.isProbeRecording {
                ProgressView(
                    value: Double(30 - tracking.probeSecondsRemaining),
                    total: 30
                ) {
                    Text("Recording continuity")
                } currentValueLabel: {
                    Text("\(tracking.probeSecondsRemaining)s remaining")
                        .monospacedDigit()
                }
            }
        }
    }

    private func reportView(_ report: JointProbeReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(verdictTitle(report.verdict), systemImage: verdictIcon(report.verdict))
                .font(.title2.bold())
                .foregroundStyle(verdictColor(report.verdict))

            Text("Duration \(report.durationSeconds, format: .number.precision(.fractionLength(1))) seconds")
                .monospacedDigit()

            HStack(spacing: 16) {
                summaryCard("Left", report.left)
                summaryCard("Right", report.right)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func summaryCard(
        _ title: String,
        _ summary: JointProbeHandSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
            Text("\(summary.sampleCount) updates")
            Text("Mean joints \(summary.averageTrackedJointCount, format: .number.precision(.fractionLength(1)))")
            Text("Critical continuity \(summary.criticalContinuity, format: .percent.precision(.fractionLength(1)))")
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var interpretation: some View {
        Label(
            "A continuity pass proves repeated named hand-joint observations. It does not prove anatomical accuracy, elbow detection, hidden-bone position, or full-body tracking.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.callout.weight(.semibold))
        .foregroundStyle(.orange)
    }

    private func openProbeSpace() async {
        guard !immersiveSpaceIsOpen else { return }
        switch await openImmersiveSpace(id: "JointProbeSpace") {
        case .opened:
            immersiveSpaceIsOpen = true
        case .userCancelled:
            launchError = "The mixed-reality joint view was cancelled."
        case .error:
            launchError = "Could not open the mixed-reality joint view."
        @unknown default:
            launchError = "The mixed-reality joint view returned an unknown result."
        }
    }

    private func verdictTitle(_ verdict: JointProbeVerdict) -> String {
        switch verdict {
        case .continuityPass: "CONTINUITY PASS"
        case .continuityNeedsWork: "CONTINUITY NEEDS WORK"
        case .insufficientDuration: "RUN TOO SHORT"
        case .noSignal: "NO HAND SIGNAL"
        }
    }

    private func verdictIcon(_ verdict: JointProbeVerdict) -> String {
        verdict == .continuityPass ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private func verdictColor(_ verdict: JointProbeVerdict) -> Color {
        verdict == .continuityPass ? .green : .orange
    }
}
