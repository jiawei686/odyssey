#if DEBUG
import SwiftUI

struct ClinicalTwinView: View {
    @EnvironmentObject private var tracking: LandmarkTrackingService
    @EnvironmentObject private var labState: ClinicalTwinLabState
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
                    controls
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
            Label("AnatomyTOOL · Blender USDZ", systemImage: "cube.transparent")
                .font(.headline)
                .foregroundStyle(.cyan)
            Text("Static reference first, then attach the twin beside the tracked right forearm.")
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

            if case .staticReady(let evidence) = labState.rendererPhase {
                Text(
                    "USDZ \(evidence.assetByteCount) bytes · "
                        + "Radius \(millimetres(evidence.radiusLengthMetres)) mm · "
                        + "Ulna \(millimetres(evidence.ulnaLengthMetres)) mm"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !immersiveSpaceIsOpen {
                Button {
                    Task { await openStaticTwin() }
                } label: {
                    Label("Start Right Forearm Session", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
            } else if labState.canAttachToRightForearm {
                Button {
                    Task { await attachToRightForearm() }
                } label: {
                    Label("Attach beside right forearm", systemImage: "hand.raised")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .controlSize(.extraLarge)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Skeletal model opacity")
                        .font(.headline)
                    Spacer()
                    Text("\(Int((labState.revealAnatomy * 100).rounded()))%")
                        .monospacedDigit()
                }
                Slider(value: $labState.revealAnatomy, in: 0 ... 1) {
                    Text("Skeletal model opacity")
                } minimumValueLabel: {
                    Text("Hidden").font(.caption)
                } maximumValueLabel: {
                    Text("Full").font(.caption)
                }
                .disabled(!immersiveSpaceIsOpen)
                .accessibilityValue(
                    "\(Int((labState.revealAnatomy * 100).rounded())) percent opacity"
                )
            }

            if let launchError {
                Label(launchError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Reset", systemImage: "arrow.counterclockwise") {
                    Task { await reset() }
                }
                .buttonStyle(.bordered)
                Spacer()
                Text("Right hand only")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "Illustrative anatomical model — not patient-specific imaging.",
                systemImage: "info.circle.fill"
            )
            .font(.callout.bold())
            .foregroundStyle(.orange)
            Text(
                "Generic AnatomyTOOL-derived skeletal anatomy exported from Blender. It is not CT-derived, patient-specific, or registered internal anatomy. The twin stays beside the tracked right forearm as an educational reference."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            Text("Tracking dots and procedural cylinders remain Diagnostics only; they are not anatomy in this session.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var statusTitle: String {
        if let presentation = labState.currentPresentation {
            return presentation.statusTitle
        }
        switch labState.rendererPhase {
        case .idle: return "Ready to open static reference"
        case .loading: return "Loading Blender skeletal twin…"
        case .staticReady: return "Static Blender skeletal twin ready"
        case .failed: return "Blender skeletal twin unavailable"
        }
    }

    private var statusDetail: String {
        if let presentation = labState.currentPresentation {
            return presentation.statusDetail
        }
        switch labState.rendererPhase {
        case .idle:
            return "The stable production demo is unchanged. This is an explicit DEBUG lab route."
        case .loading:
            return "Loading the bundled USDZ and verifying Radius_r and Ulna_r."
        case .staticReady:
            return "Static reference is visible. Confirm it before attaching to tracking."
        case .failed(let detail):
            return "Projection rejected: \(detail)"
        }
    }

    private var statusSymbol: String {
        switch labState.rendererPhase {
        case .idle: "play.circle"
        case .loading: "hourglass"
        case .staticReady: labState.trackingRequested ? "wave.3.right" : "cube"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func millimetres(_ metres: Float) -> String {
        String(format: "%.1f", metres * 1_000)
    }

    @MainActor
    private func openStaticTwin() async {
        launchError = nil
        switch await openImmersiveSpace(id: "ClinicalTwinSpace") {
        case .opened:
            immersiveSpaceIsOpen = true
        case .userCancelled:
            launchError = "The mixed-reality session was cancelled."
        case .error:
            launchError = "The mixed-reality session could not open."
        @unknown default:
            launchError = "The mixed-reality session returned an unknown result."
        }
    }

    @MainActor
    private func attachToRightForearm() async {
        let wasIdle = tracking.handPhase == .idle
        await labState.startRightForearmTracking(using: tracking)
        ownsTrackingSession = wasIdle && tracking.handPhase == .running
    }

    @MainActor
    private func reset() async {
        if ownsTrackingSession { tracking.stop() }
        ownsTrackingSession = false
        await dismissImmersiveSpace()
        immersiveSpaceIsOpen = false
        labState.reset()
    }
}
#endif
