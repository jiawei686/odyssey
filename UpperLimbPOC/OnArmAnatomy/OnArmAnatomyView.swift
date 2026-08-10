#if DEBUG
import SwiftUI

struct OnArmAnatomyView: View {
    @EnvironmentObject private var tracking: LandmarkTrackingService
    @EnvironmentObject private var labState: OnArmAnatomyLabState
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @State private var immersiveSpaceIsOpen = false
    @State private var ownsTrackingSession = false
    @State private var launchError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    statusCard
                    routeControls
                    trackingControl
                    diagnostics
                    disclosure
                }
                .padding(30)
            }
            .navigationTitle("Odyssey Clinical Education")
        }
        .onDisappear {
            if ownsTrackingSession { tracking.stop() }
            Task { await dismissImmersiveSpace() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Odyssey · Right Forearm")
                .font(.largeTitle.bold())
            Label("On-Arm Anatomy Lab · AnatomyTOOL USDZ", systemImage: "move.3d")
                .font(.headline)
                .foregroundStyle(.cyan)
            Text("Static full anatomy first; then radius and ulna best-fit directly to the tracked right forearm.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(statusTitle, systemImage: statusSymbol)
                .font(.title2.bold())
            Text(statusDetail)
                .foregroundStyle(.secondary)
            if case .ready(let evidence) = labState.assetPhase {
                Text(
                    "USDZ \(evidence.assetByteCount) bytes · "
                        + "Radius \(millimetres(evidence.radiusExtentsMetres.z)) mm · "
                        + "Ulna \(millimetres(evidence.ulnaExtentsMetres.z)) mm"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var routeControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("1. Prove the real USDZ is visible")
                .font(.headline)
            ForEach(OnArmAnatomyVisibilityMode.allCases) { mode in
                Button {
                    Task { await openStaticAsset(mode: mode) }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(
                            mode.label,
                            systemImage: mode == .normalOverlay
                                ? "hand.raised"
                                : "hand.raised.slash"
                        )
                        Text(mode.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .tint(mode == .normalOverlay ? .blue : .orange)
                .disabled(immersiveSpaceIsOpen)
            }
            if immersiveSpaceIsOpen {
                Label(
                    "Open route: \(labState.selectedVisibilityMode.label)",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            }
        }
        .padding(22)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder
    private var trackingControl: some View {
        if immersiveSpaceIsOpen {
            VStack(alignment: .leading, spacing: 12) {
                Text("2. Align named forearm bones")
                    .font(.headline)
                Button {
                    Task { await startRightForearmTracking() }
                } label: {
                    Label("Align Radius & Ulna to Right Forearm", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .disabled(!labState.canStartTracking)

                Text("Hand and finger meshes are hidden after alignment. Programmatic finger articulation is deferred until the forearm gate passes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private var diagnostics: some View {
        DisclosureGroup("Diagnostics calibration") {
            VStack(alignment: .leading, spacing: 12) {
                calibrationSlider(
                    "Scale",
                    value: $labState.calibration.scaleMultiplier,
                    range: 0.8 ... 1.2,
                    display: "×"
                )
                calibrationSlider(
                    "Axial",
                    value: $labState.calibration.axialMetres,
                    range: -0.05 ... 0.05,
                    display: "m"
                )
                calibrationSlider(
                    "Lateral",
                    value: $labState.calibration.lateralMetres,
                    range: -0.03 ... 0.03,
                    display: "m"
                )
                calibrationSlider(
                    "Depth",
                    value: $labState.calibration.depthMetres,
                    range: -0.03 ... 0.03,
                    display: "m"
                )
                calibrationSlider(
                    "Roll",
                    value: $labState.calibration.rollDegrees,
                    range: -45 ... 45,
                    display: "°"
                )
                Button("Reset calibration", systemImage: "arrow.counterclockwise") {
                    labState.calibration = OnArmAnatomyCalibration()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 12)
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "Reference anatomy alignment — not patient-specific imaging.",
                systemImage: "info.circle.fill"
            )
            .font(.callout.bold())
            .foregroundStyle(.orange)
            Text("This generic educational AnatomyTOOL model is not CT registration and cannot be called exact. Hand tracking supplies an approximate right-forearm axis and wrist roll; body shape, bone position, pivots, and system compositing remain unverified.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Tracking dots and procedural cylinders remain Diagnostics only; they are not used by this anatomy route.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let launchError {
                Label(launchError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            Button("Close and reset lab", systemImage: "xmark.circle") {
                Task { await reset() }
            }
            .buttonStyle(.bordered)
        }
    }

    private func calibrationSlider(
        _ label: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value.wrappedValue, specifier: "%.3f") \(display)")
                    .monospacedDigit()
            }
            Slider(value: value, in: range) { Text(label) }
        }
    }

    private var statusTitle: String {
        if let presentation = labState.currentPresentation {
            return presentation.statusTitle
        }
        return switch labState.assetPhase {
        case .idle: "Ready for static USDZ gate"
        case .loading: "Loading real anatomy USDZ…"
        case .ready: "Static USDZ ready"
        case .failed: "Anatomy USDZ unavailable"
        }
    }

    private var statusDetail: String {
        if let presentation = labState.currentPresentation {
            return presentation.statusDetail
        }
        return switch labState.assetPhase {
        case .idle:
            "This explicit DEBUG lab route does not alter the validated release experience."
        case .loading:
            "Verifying Radius_r, Ulna_r, metre bounds, and opaque material visibility."
        case .ready:
            "Confirm the full static asset appears in front of you before starting tracking."
        case .failed(let detail):
            "Asset gate failed: \(detail)"
        }
    }

    private var statusSymbol: String {
        switch labState.assetPhase {
        case .idle: "play.circle"
        case .loading: "hourglass"
        case .ready: labState.trackingRequested ? "scope" : "cube"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    @MainActor
    private func openStaticAsset(mode: OnArmAnatomyVisibilityMode) async {
        launchError = nil
        labState.prepareForOpening(mode)
        switch await openImmersiveSpace(id: mode.immersiveSpaceID) {
        case .opened:
            immersiveSpaceIsOpen = true
        case .userCancelled:
            launchError = "The mixed-reality lab was cancelled."
            labState.reset()
        case .error:
            launchError = "The mixed-reality lab could not open."
            labState.reset()
        @unknown default:
            launchError = "The mixed-reality lab returned an unknown result."
            labState.reset()
        }
    }

    @MainActor
    private func startRightForearmTracking() async {
        labState.requestRightForearmTracking()
        let wasIdle = tracking.handPhase == .idle
        await tracking.startHandJointProbe()
        ownsTrackingSession = wasIdle && tracking.handPhase == .running
    }

    @MainActor
    private func reset() async {
        if ownsTrackingSession { tracking.stop() }
        ownsTrackingSession = false
        if immersiveSpaceIsOpen { await dismissImmersiveSpace() }
        immersiveSpaceIsOpen = false
        labState.reset()
    }

    private func millimetres(_ metres: Float) -> String {
        String(format: "%.1f", metres * 1_000)
    }
}
#endif
