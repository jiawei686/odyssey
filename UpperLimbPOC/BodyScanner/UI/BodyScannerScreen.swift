import SwiftUI

struct BodyScannerScreen: View {
    @StateObject private var model = BodyScannerCameraModel()
    @State private var participantConsent = false
    @State private var scannerStarted = false

    var body: some View {
        GeometryReader { geometry in
            Group {
                if !scannerStarted {
                    consentView
                } else if geometry.size.width <= geometry.size.height {
                    rotateView
                } else {
                    scannerView(size: geometry.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
        }
        .navigationTitle("OpenCV Arm Scanner")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear(perform: model.stop)
    }

    private var consentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "figure.arms.open")
                    .font(.system(size: 48))
                    .foregroundStyle(.cyan)

                Text("Scan both arms")
                    .font(.largeTitle.bold())

                Text("The rear iPhone camera runs pinned OpenCV models on-device to estimate visible shoulder, elbow, and wrist landmarks. Finger inference is the next gated milestone.")

                disclosurePanel

                Toggle(
                    "The participant has consented to this educational scan",
                    isOn: $participantConsent
                )
                .accessibilityIdentifier(BodyScannerAccessibilityID.consent)

                Button("Start camera") {
                    scannerStarted = true
                    model.start()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!participantConsent)
                .accessibilityIdentifier(BodyScannerAccessibilityID.continueButton)
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .foregroundStyle(.white)
        .accessibilityIdentifier(BodyScannerAccessibilityID.intro)
    }

    private var rotateView: some View {
        VStack(spacing: 18) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 54))
            Text("Rotate iPhone to landscape")
                .font(.title2.bold())
            Text("Place it about 2 metres in front of one consenting participant.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .foregroundStyle(.white)
        .accessibilityIdentifier(BodyScannerAccessibilityID.rotate)
    }

    private func scannerView(size: CGSize) -> some View {
        HStack(spacing: 0) {
            ZStack {
                if model.frozenObservations == nil {
                    BodyScannerCameraPreview(model: model)
                        .accessibilityIdentifier(BodyScannerAccessibilityID.preview)
                } else {
                    Color(white: 0.08)
                        .overlay(alignment: .bottomLeading) {
                            Text("Frozen skeleton • camera image not retained")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .padding(16)
                        }
                }

                skeletonOverlay(size: size)
                    .opacity(model.phase.displayOpacity)
                    .accessibilityHidden(true)

                VStack {
                    HStack {
                        phaseBadge
                        Spacer()
                    }
                    Spacer()
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            statusPanel
                .frame(width: min(350, size.width * 0.34))
        }
    }

    private func skeletonOverlay(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let projection = BodyScannerPreviewProjection(
                sensorWidth: model.frameSize.width,
                sensorHeight: model.frameSize.height,
                viewWidth: canvasSize.width,
                viewHeight: canvasSize.height
            )
            for laterality in [UpperLimbLaterality.left, .right] {
                let sideJoints = Dictionary(
                    uniqueKeysWithValues: model.joints
                        .filter { $0.laterality == laterality }
                        .map { ($0.joint, $0) }
                )
                drawSegment(
                    from: sideJoints[.shoulder],
                    to: sideJoints[.elbow],
                    laterality: laterality,
                    projection: projection,
                    context: &context
                )
                drawSegment(
                    from: sideJoints[.elbow],
                    to: sideJoints[.wrist],
                    laterality: laterality,
                    projection: projection,
                    context: &context
                )
                for joint in sideJoints.values {
                    drawPoint(
                        joint,
                        laterality: laterality,
                        projection: projection,
                        context: &context
                    )
                }
            }
        }
        .accessibilityIdentifier(BodyScannerAccessibilityID.overlay)
    }

    private func drawSegment(
        from start: BodyScannerLiveJoint?,
        to end: BodyScannerLiveJoint?,
        laterality: UpperLimbLaterality,
        projection: BodyScannerPreviewProjection,
        context: inout GraphicsContext
    ) {
        guard let start, let end else { return }
        let a = projection.project(normalizedX: start.normalizedX, normalizedY: start.normalizedY)
        let b = projection.project(normalizedX: end.normalizedX, normalizedY: end.normalizedY)
        var path = Path()
        path.move(to: CGPoint(x: a.x, y: a.y))
        path.addLine(to: CGPoint(x: b.x, y: b.y))
        context.stroke(
            path,
            with: .color(colour(for: laterality)),
            style: StrokeStyle(
                lineWidth: 5,
                lineCap: .round,
                dash: laterality == .right ? [10, 7] : []
            )
        )
    }

    private func drawPoint(
        _ joint: BodyScannerLiveJoint,
        laterality: UpperLimbLaterality,
        projection: BodyScannerPreviewProjection,
        context: inout GraphicsContext
    ) {
        let point = projection.project(
            normalizedX: joint.normalizedX,
            normalizedY: joint.normalizedY
        )
        let rect = CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)
        if laterality == .left {
            var triangle = Path()
            triangle.move(to: CGPoint(x: rect.midX, y: rect.minY))
            triangle.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            triangle.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            triangle.closeSubpath()
            context.fill(triangle, with: .color(colour(for: laterality)))
        } else {
            context.fill(Path(rect), with: .color(colour(for: laterality)))
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(BodyScannerPresentation.disclosure)
                .font(.caption.bold())
                .foregroundStyle(.orange)

            Text(guidance.instruction)
                .font(.title3.bold())
                .accessibilityIdentifier(BodyScannerAccessibilityID.guidance)

            Text(model.status)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(BodyScannerAccessibilityID.status)

            Text(model.diagnostics)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(model.counts.summary)
                .font(.caption.monospacedDigit())
                .accessibilityIdentifier(BodyScannerAccessibilityID.counts)

            Divider()

            Label("Participant left", systemImage: "triangle.fill")
                .foregroundStyle(.orange)
            Label("Participant right", systemImage: "square.fill")
                .foregroundStyle(.cyan)

            Text("Finger model pending — no finger points are claimed in this build.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            if let frozen = model.frozenObservations {
                Text("Frozen structured observation: \(frozen.count) arm points")
                    .font(.headline)
                    .accessibilityIdentifier(BodyScannerAccessibilityID.frozenSummary)
                Button("Reset scan", action: model.reset)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(BodyScannerAccessibilityID.reset)
            } else {
                Button("Freeze arm joints", action: model.freeze)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canFreeze)
                    .accessibilityIdentifier(BodyScannerAccessibilityID.freeze)
                Text(canFreeze ? "Qualified for at least 1 second and 10 frames." : "Freeze requires all six arm points to remain qualified.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(BodyScannerPresentation.landmarkTruth)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(BodyScannerPresentation.privacy)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .foregroundStyle(.white)
        .background(.black.opacity(0.88))
    }

    private var phaseBadge: some View {
        Text(model.phase.label)
            .font(.caption.bold().monospaced())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(.white)
            .background(phaseColour, in: Capsule())
            .accessibilityIdentifier(BodyScannerAccessibilityID.status)
    }

    private var guidance: BodyScannerGuidanceCondition {
        switch model.phase {
        case .searching: .noParticipant
        case .partial: .bodyClipped
        case .stabilizing: .stabilizing
        case .qualified, .frozen: .ready
        case .stale, .failed: .noParticipant
        }
    }

    private var canFreeze: Bool {
        if case .qualified = model.phase { return true }
        return false
    }

    private var phaseColour: Color {
        switch model.phase {
        case .qualified, .frozen: .green
        case .partial, .stabilizing: .orange
        case .failed: .red
        case .searching, .stale: .gray
        }
    }

    private func colour(for laterality: UpperLimbLaterality) -> Color {
        laterality == .left ? .orange : .cyan
    }

    private var disclosurePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(BodyScannerPresentation.disclosure)
                .font(.headline)
                .foregroundStyle(.orange)
            Text(BodyScannerPresentation.landmarkTruth)
            Text(BodyScannerPresentation.privacy)
            Text("Do not use for diagnosis, treatment, navigation, or participant-specific anatomy.")
        }
        .font(.footnote)
        .padding(16)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}
