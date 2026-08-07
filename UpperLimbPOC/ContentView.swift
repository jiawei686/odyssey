import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var overlay: OverlayState
    @EnvironmentObject private var peer: PeerSession
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var selectedRegion: BodyRegion = .rightUpperLimb
    @State private var isOpening = false
    @State private var launchError: String?

    private let columns = [
        GridItem(.adaptive(minimum: 190, maximum: 240), spacing: 18)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction

                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(BodyRegion.allCases) { region in
                            RegionCard(
                                region: region,
                                isSelected: selectedRegion == region
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedRegion = region
                                }
                            }
                        }
                    }

                    selectionPanel
                }
                .padding(28)
            }
            .navigationTitle("Radiographic Anatomy")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Label(
                        peer.isConnected ? "Companion connected" : "Searching for companion",
                        systemImage: peer.isConnected ? "vision.pro.fill" : "network"
                    )
                    .foregroundStyle(peer.isConnected ? .green : .secondary)
                }
            }
        }
        .onAppear(perform: peer.start)
        .onReceive(peer.$lastSnapshot.compactMap { $0 }) { snapshot in
            overlay.applyCalibration(snapshot)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose a skeletal region")
                .font(.largeTitle.bold())
            Text("Look at a card and pinch to select it. The menu closes after the translucent bone overlay opens.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Label(
                "Educational prototype — not for diagnosis or procedural guidance",
                systemImage: "cross.case.fill"
            )
            .font(.callout.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.top, 4)
        }
    }

    private var selectionPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 20) {
                Image(systemName: selectedRegion.systemImage)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.cyan)
                    .frame(width: 66, height: 66)
                    .background(.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 5) {
                    Text(selectedRegion.name)
                        .font(.title2.bold())
                    Text(selectedRegion.isAvailable
                         ? "Reference forearm-and-hand model ready for two-landmark tracking."
                         : "This regional model is listed in the library and is being prepared.")
                        .foregroundStyle(.secondary)
                    if selectedRegion.isAvailable {
                        Toggle("Follow ELBOW + WRIST markers", isOn: $overlay.trackingEnabled)
                            .toggleStyle(.switch)
                            .font(.callout.weight(.semibold))
                    }
                    if let launchError {
                        Text(launchError)
                            .foregroundStyle(.red)
                    }
                }

                Spacer()

                Button {
                    Task { await openBoneOverlay() }
                } label: {
                    if isOpening {
                        ProgressView()
                            .frame(minWidth: 150)
                    } else {
                        Label("Open overlay", systemImage: "vision.pro")
                            .frame(minWidth: 150)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isOpening || !selectedRegion.isAvailable)
            }

            if selectedRegion.isAvailable {
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Toggle(
                            "Reference sectional-imaging plane",
                            isOn: $overlay.sectionVisible
                        )
                        .font(.headline)

                        Spacer()

                        Text("Slice \(overlay.selectedSliceIndex + 1) of \(overlay.sliceCount)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Elbow")
                        Slider(
                            value: Binding(
                                get: { overlay.normalizedSlicePosition },
                                set: overlay.setSectionPosition
                            ),
                            in: 0...1
                        )
                        Text("Wrist")

                        Text("Opacity")
                            .padding(.leading, 14)
                        Slider(value: $overlay.sectionOpacity, in: 0.15...1.0)
                            .frame(maxWidth: 180)
                    }
                    .disabled(!overlay.sectionVisible)

                    Label(
                        "NLM public-domain reference CT — cross-subject approximation, not patient-specific or clinical",
                        systemImage: "square.stack.3d.up"
                    )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)

                    Text("Axial orientation and laterality are illustrative only; the prototype does not register A/P or R/L orientation.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    @MainActor
    private func openBoneOverlay() async {
        guard !isOpening else { return }
        isOpening = true
        launchError = nil

        overlay.selectedRegion = selectedRegion
        overlay.makeVisible()
        peer.send(overlay.snapshot)

        let result = await openImmersiveSpace(id: "BoneOverlay")
        isOpening = false

        if result == .opened {
            openWindow(id: "TrackingStatus")
            dismissWindow(id: "AnatomyLibrary")
        } else {
            launchError = "The immersive space could not open. Please try again."
        }
    }
}

struct TrackingStatusView: View {
    @EnvironmentObject private var overlay: OverlayState
    @EnvironmentObject private var tracking: LandmarkTrackingService

    private var message: String {
        overlay.trackingEnabled
            ? tracking.phase.message
            : "Manual placement — landmark tracking is off"
    }

    private var color: Color {
        if !overlay.trackingEnabled { return .blue }
        if tracking.isTracking { return .green }

        switch tracking.phase {
        case .authorizationDenied, .unsupported, .invalidDistance, .failed:
            return .red
        case .simulatorUnavailable:
            return .blue
        default:
            return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: tracking.isTracking ? "scope" : "viewfinder")
                .font(.headline)
                .foregroundStyle(color)

            Text("When active landmark tracking is lost, the overlay keeps its last valid pose and fades. Unavailable devices use manual placement.")
                .font(.callout)

            Text("Reference CT orientation/laterality is illustrative only — not patient-specific or for clinical use.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

private struct RegionCard: View {
    let region: BodyRegion
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    LinearGradient(
                        colors: [.cyan.opacity(0.26), .blue.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: region.systemImage)
                        .font(.system(size: 62, weight: .thin))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)

                    if region.isAvailable {
                        Text("MODEL READY")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.green, in: Capsule())
                            .padding(10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(height: 125)

                VStack(alignment: .leading, spacing: 5) {
                    Text(region.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(region.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? .cyan : .white.opacity(0.12), lineWidth: isSelected ? 3 : 1)
            }
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(region.name), \(region.isAvailable ? "model ready" : "model being prepared")")
    }
}
