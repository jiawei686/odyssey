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
    @State private var didRunAutomatedDemo = false
    @State private var showPlannedRegions = false

    private let columns = [
        GridItem(.adaptive(minimum: 190, maximum: 240), spacing: 18)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction

                    Button {
                        Task { await openBoneOverlay() }
                    } label: {
                        Label("Open \(selectedRegion.name) overlay", systemImage: "vision.pro")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isOpening || !selectedRegion.isAvailable)

                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(BodyRegion.allCases.filter(\.isAvailable)) { region in
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

                    DisclosureGroup(
                        "Planned anatomy regions (\(BodyRegion.allCases.filter { !$0.isAvailable }.count))",
                        isExpanded: $showPlannedRegions
                    ) {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(BodyRegion.allCases.filter { !$0.isAvailable }) { region in
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
                        .padding(.top, 14)
                    }
                    .font(.headline)

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
        .task {
            await runAutomatedDemoIfRequested()
        }
        .onReceive(peer.$lastSnapshot.compactMap { $0 }) { snapshot in
            overlay.applyCalibration(snapshot)
        }
        .onChange(of: peer.isConnected) { _, isConnected in
            guard isConnected else { return }
            peer.send(overlay.snapshot)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose a skeletal region")
                .font(.largeTitle.bold())
            Text("Look at a card until it highlights, then pinch to select. The menu closes after the translucent bone overlay opens.")
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
                AnatomyBoneIcon(region: selectedRegion, color: .cyan)
                    .frame(width: 48, height: 48)
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
                                set: { overlay.setSectionPosition($0) }
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
        overlay.resetPlacement()
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

    @MainActor
    private func runAutomatedDemoIfRequested() async {
#if DEBUG
        guard !didRunAutomatedDemo,
              ProcessInfo.processInfo.arguments.contains("--automated-demo")
        else { return }

        didRunAutomatedDemo = true
        selectedRegion = .rightUpperLimb
        overlay.trackingEnabled = true
        overlay.opacity = 0.65
        overlay.tint = .amber
        overlay.sectionVisible = true
        overlay.setSectionPosition(0.75)
        overlay.sectionOpacity = 0.55

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await openBoneOverlay()
#endif
    }
}

struct TrackingStatusView: View {
    @EnvironmentObject private var overlay: OverlayState
    @EnvironmentObject private var peer: PeerSession
    @EnvironmentObject private var tracking: LandmarkTrackingService
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        HStack(alignment: .top, spacing: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: tracking.isTracking ? "scope" : "viewfinder")
                    .font(.headline)
                    .foregroundStyle(color)

                Label(alignmentSafetyText, systemImage: alignmentSafetyIcon)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(tracking.isTracking ? .green : .orange)

                Label(
                    peer.isConnected ? "Companion connected" : "Companion disconnected",
                    systemImage: peer.isConnected ? "vision.pro.fill" : "network.slash"
                )
                .font(.callout.weight(.semibold))
                .foregroundStyle(peer.isConnected ? .green : .orange)

                Text("When active landmark tracking is lost, the overlay keeps its last valid pose and fades. Unavailable devices use manual placement.")
                    .font(.callout)

                Text("Reference CT orientation/laterality is illustrative only — not patient-specific or for clinical use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label(
                    overlay.sectionSourceStatus.message,
                    systemImage: overlay.sectionSourceStatus == .syntheticFallback
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.circle"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    overlay.sectionSourceStatus == .syntheticFallback
                        ? .orange
                        : .secondary
                )

                Divider()

                Toggle(
                    "Follow ELBOW + WRIST markers",
                    isOn: Binding(
                        get: { overlay.trackingEnabled },
                        set: { value in
                            overlay.trackingEnabled = value
                        }
                    )
                )
                .toggleStyle(.switch)

                if case .failed = tracking.phase {
                    Button("Retry marker tracking", systemImage: "arrow.clockwise") {
                        Task { await tracking.retry() }
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    Label(
                        overlay.locked ? "Placement locked" : "Placement unlocked",
                        systemImage: overlay.locked ? "lock.fill" : "lock.open.fill"
                    )
                    .font(.callout.weight(.semibold))

                    Spacer()

                    Button(overlay.locked ? "Unlock placement" : "Lock placement") {
                        overlay.locked.toggle()
                        peer.send(overlay.snapshot)
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Imaging mode")
                        .font(.callout.weight(.semibold))

                    Picker(
                        "Imaging mode",
                        selection: Binding(
                            get: { overlay.sectionVisible ? 1 : 0 },
                            set: { value in
                                overlay.sectionVisible = value == 1
                                peer.send(overlay.snapshot)
                            }
                        )
                    ) {
                        Text("3D bone").tag(0)
                        Text("3D + axial").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Label(overlay.imagingModeName, systemImage: "square.3.layers.3d")
                    .font(.headline)

                Label(overlay.focusedBoneName, systemImage: "sparkles")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Text(overlay.focusedBoneDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Menu("Choose a bone from list", systemImage: "list.bullet") {
                    ForEach(anatomyChoices.indices, id: \.self) { index in
                        let choice = anatomyChoices[index]
                        Button(choice.label) {
                            overlay.focusBone(entityName: choice.entityName)
                        }
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Gaze-targeted interaction", systemImage: "eye")
                            .font(.callout.weight(.semibold))
                        Text("Look at a bone until it highlights; single-pinch to identify it. Double-pinch changes imaging mode, with the segmented control above as the reliable alternative.")
                        Text("Looking alone never activates an action. The app does not receive or record raw gaze coordinates.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if #available(visionOS 26.0, *) {
                    Text("Manual, unlocked mode: pinch and drag to move; use two hands to resize uniformly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("On this visionOS version, use the companion placement sliders. Direct pinch-drag and resize require visionOS 26 or later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let overlayLoadError = overlay.overlayLoadError {
                    Label(overlayLoadError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)

                    Button("Retry loading model", systemImage: "arrow.clockwise") {
                        overlay.requestOverlayReload()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Return to anatomy library", systemImage: "rectangle.portrait.and.arrow.forward") {
                    Task {
                        await dismissImmersiveSpace()
                        openWindow(id: "AnatomyLibrary")
                        dismissWindow(id: "TrackingStatus")
                    }
                }
                .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity)

            if overlay.sectionVisible {
                sectionLevelBar
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: overlay.sectionVisible)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private let anatomyChoices = [
        (label: "Radius", entityName: "Radius_r"),
        (label: "Ulna", entityName: "Ulna_r"),
        (label: "Scaphoid", entityName: "Scaphoid_r"),
        (label: "Lunate", entityName: "Lunate_r"),
        (label: "Capitate", entityName: "Capitate_r"),
        (label: "Metacarpals", entityName: "Metacarpal_r"),
        (label: "Finger phalanges", entityName: "Phalanx_r")
    ]

    private var alignmentSafetyText: String {
        if tracking.isTracking {
            return "LIVE — both markers detected"
        }
        if overlay.trackingEnabled, tracking.fit != nil {
            return "STALE — last pose; do not rely on alignment"
        }
        return "NOT REGISTERED — reference placement only"
    }

    private var alignmentSafetyIcon: String {
        tracking.isTracking ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
    }

    private var sectionLevelBar: some View {
        VStack(spacing: 8) {
            Text("Section level")
                .font(.headline)

            Text("WRIST")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { overlay.normalizedSlicePosition },
                        set: { position in
                            overlay.setSectionPosition(position)
                            peer.send(overlay.snapshot)
                        }
                    ),
                    in: 0...1
                )
                .controlSize(.large)
                .frame(width: 220)
                .rotationEffect(.degrees(-90))
                .frame(width: 64, height: 220)
                .contentShape(Rectangle())
                .accessibilityLabel("Elbow to wrist section level")
                .accessibilityValue(
                    "Level \(overlay.selectedSliceIndex + 1) of \(overlay.sliceCount)"
                )
                .accessibilityHint("Drag vertically, or use the increment and decrement actions, to move the section plane")

                VStack(spacing: 0) {
                    ForEach((0..<overlay.sliceCount).reversed(), id: \.self) { index in
                        HStack(spacing: 3) {
                            Capsule()
                                .fill(
                                    index == overlay.selectedSliceIndex
                                        ? Color.cyan
                                        : Color.secondary.opacity(0.35)
                                )
                                .frame(width: 9, height: 2)
                            Text("\(index + 1)")
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(
                                    index == overlay.selectedSliceIndex
                                        ? Color.primary
                                        : Color.secondary
                                )
                        }

                        if index > 0 {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(height: 204)
            }

            Text("ELBOW")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\(overlay.selectedSliceIndex + 1) / \(overlay.sliceCount)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()

            Text(overlay.normalizedSlicePosition, format: .number.precision(.fractionLength(2)))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(width: 120)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
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

                    AnatomyBoneIcon(region: region, color: .white)
                        .frame(width: 72, height: 82)

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

private struct AnatomyBoneIcon: View {
    let region: BodyRegion
    let color: Color

    var body: some View {
        Canvas { context, size in
            let style = StrokeStyle(
                lineWidth: max(2, size.width * 0.045),
                lineCap: .round,
                lineJoin: .round
            )
            for path in paths(in: size) {
                context.stroke(path, with: .color(color), style: style)
            }
        }
        .accessibilityHidden(true)
    }

    private func paths(in size: CGSize) -> [Path] {
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: size.width * x, y: size.height * y)
        }

        func ellipse(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> Path {
            Path(ellipseIn: CGRect(
                x: size.width * x,
                y: size.height * y,
                width: size.width * width,
                height: size.height * height
            ))
        }

        func line(_ points: [CGPoint]) -> Path {
            var path = Path()
            guard let first = points.first else { return path }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            return path
        }

        func spine(from start: Double, to end: Double, count: Int) -> [Path] {
            (0..<count).map { index in
                let fraction = count == 1 ? 0 : Double(index) / Double(count - 1)
                let y = start + ((end - start) * fraction)
                return ellipse(0.43, y, 0.14, 0.065)
            }
        }

        func pelvis() -> [Path] {
            var left = Path()
            left.move(to: point(0.47, 0.38))
            left.addCurve(
                to: point(0.16, 0.58),
                control1: point(0.34, 0.30),
                control2: point(0.15, 0.35)
            )
            left.addCurve(
                to: point(0.42, 0.78),
                control1: point(0.18, 0.74),
                control2: point(0.30, 0.80)
            )

            var right = Path()
            right.move(to: point(0.53, 0.38))
            right.addCurve(
                to: point(0.84, 0.58),
                control1: point(0.66, 0.30),
                control2: point(0.85, 0.35)
            )
            right.addCurve(
                to: point(0.58, 0.78),
                control1: point(0.82, 0.74),
                control2: point(0.70, 0.80)
            )

            return [
                left,
                right,
                line([point(0.50, 0.38), point(0.50, 0.72)]),
                ellipse(0.22, 0.55, 0.16, 0.16),
                ellipse(0.62, 0.55, 0.16, 0.16)
            ]
        }

        func upperLimb(isLeft: Bool) -> [Path] {
            let mirror: (Double) -> Double = { isLeft ? 1 - $0 : $0 }
            var result = [
                line([point(mirror(0.42), 0.10), point(mirror(0.38), 0.62)]),
                line([point(mirror(0.58), 0.10), point(mirror(0.62), 0.62)]),
                line([point(mirror(0.36), 0.64), point(mirror(0.64), 0.64)]),
                ellipse(mirror(0.43), 0.02, 0.14, 0.12)
            ]
            for index in 0..<5 {
                let x = 0.34 + (Double(index) * 0.08)
                result.append(line([
                    point(mirror(0.50), 0.67),
                    point(mirror(x), 0.91 - Double(abs(index - 2)) * 0.035)
                ]))
            }
            return result
        }

        func lowerLimb(isLeft: Bool) -> [Path] {
            let mirror: (Double) -> Double = { isLeft ? 1 - $0 : $0 }
            return [
                ellipse(mirror(0.40), 0.05, 0.20, 0.16),
                line([point(mirror(0.50), 0.18), point(mirror(0.46), 0.48)]),
                ellipse(mirror(0.41), 0.45, 0.12, 0.10),
                line([point(mirror(0.44), 0.54), point(mirror(0.39), 0.84)]),
                line([point(mirror(0.55), 0.54), point(mirror(0.51), 0.84)]),
                line([point(mirror(0.38), 0.86), point(mirror(0.66), 0.92)])
            ]
        }

        switch region {
        case .skull:
            var jaw = Path()
            jaw.move(to: point(0.30, 0.48))
            jaw.addCurve(
                to: point(0.70, 0.48),
                control1: point(0.32, 0.82),
                control2: point(0.68, 0.82)
            )
            return [
                ellipse(0.22, 0.08, 0.56, 0.56),
                ellipse(0.34, 0.30, 0.09, 0.09),
                ellipse(0.57, 0.30, 0.09, 0.09),
                jaw
            ]

        case .cervicalSpine:
            return spine(from: 0.14, to: 0.72, count: 7)

        case .chest:
            var paths = [line([point(0.50, 0.16), point(0.50, 0.86)])]
            for index in 0..<5 {
                let y = 0.24 + (Double(index) * 0.12)
                var ribs = Path()
                ribs.move(to: point(0.49, y))
                ribs.addCurve(
                    to: point(0.18, y + 0.08),
                    control1: point(0.37, y - 0.05),
                    control2: point(0.20, y - 0.02)
                )
                ribs.move(to: point(0.51, y))
                ribs.addCurve(
                    to: point(0.82, y + 0.08),
                    control1: point(0.63, y - 0.05),
                    control2: point(0.80, y - 0.02)
                )
                paths.append(ribs)
            }
            return paths

        case .lumbarSpine:
            return spine(from: 0.18, to: 0.62, count: 6) + pelvis()

        case .wholeSpine:
            var curve = Path()
            curve.move(to: point(0.50, 0.08))
            curve.addCurve(
                to: point(0.50, 0.92),
                control1: point(0.38, 0.34),
                control2: point(0.62, 0.64)
            )
            return [curve] + spine(from: 0.10, to: 0.84, count: 9)

        case .pelvis:
            return pelvis()

        case .leftHip:
            return pelvis() + [
                line([point(0.30, 0.67), point(0.22, 0.95)])
            ]

        case .rightHip:
            return pelvis() + [
                line([point(0.70, 0.67), point(0.78, 0.95)])
            ]

        case .leftUpperLimb:
            return upperLimb(isLeft: true)

        case .rightUpperLimb:
            return upperLimb(isLeft: false)

        case .leftLowerLimb:
            return lowerLimb(isLeft: true)

        case .rightLowerLimb:
            return lowerLimb(isLeft: false)
        }
    }
}
