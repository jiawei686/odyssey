import SwiftUI

// Claude-owned experimental frontend for anatomical-layer annotation.
// Consumes the frozen AnatomicalAnnotation* contract types only; child views
// never touch PeerSession. Feature-gated OFF in normal runtime.

// MARK: - Feature gate

/// Runtime gate for the experimental anatomical-layer UI. OFF unless the
/// contract default flips or the explicit launch argument is supplied
/// (simulator verification only). Production policy defaults are untouched.
enum AnatomicalLayerUIFeatureGate {
    static let launchArgument = "--enable-anatomical-layer-ui"

    static var isEnabled: Bool {
        AnatomicalLayerProjectionFeature.isEnabledByDefault
            || ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
}

// MARK: - View depth (what anatomical layer the patient would see)

enum AnatomicalViewDepth: String, CaseIterable, Identifiable {
    case surface
    case fat
    case muscle
    case bone

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .surface: "Surface"
        case .fat: "Fat"
        case .muscle: "Muscle"
        case .bone: "Bone"
        }
    }
}

// MARK: - Annotation targets (the 3D surface receiving the annotation)

extension AnatomicalLayerTarget {
    /// Layers a clinician may annotate. `floating` is deliberately excluded:
    /// projection rejects it and the UI never offers it.
    static let annotatableTargets: [Self] = [.skin, .subcutaneousFat, .muscle, .bone]

    var displayName: String {
        switch self {
        case .skin: "Skin"
        case .subcutaneousFat: "Fat"
        case .muscle: "Muscle"
        case .bone: "Bone"
        case .floating: "Unassigned"
        }
    }
}

// MARK: - Failure-reason translation

extension AnatomicalProjectionFailureReason {
    var displayMessage: String {
        switch self {
        case .featureDisabled:
            "Anatomical-layer annotation is turned off in this build."
        case .invalidRequest:
            "The annotation request was malformed, so nothing was placed."
        case .frameMismatch:
            "The view changed before the annotation arrived. Tap again on the current view."
        case .staleFrame:
            "The tapped view was too old to place safely. Tap again."
        case .trackingUnavailable:
            "Vision Pro tracking is unavailable, so nothing was placed."
        case .trackingNotLive:
            "Vision Pro tracking is not live, so nothing was placed."
        case .insufficientTrackingConfidence:
            "Tracking confidence is too low to place an annotation safely."
        case .invalidRay:
            "The tap could not be converted into a valid line of sight."
        case .unsupportedTargetLayer:
            "The selected target layer cannot receive annotations."
        case .surfaceUnavailable:
            "The selected anatomical surface is unavailable right now."
        case .missedSurface:
            "The tap did not land on the selected anatomical layer."
        case .insufficientProjectionConfidence:
            "The placement was not confident enough to show. Nothing was placed."
        }
    }
}

// MARK: - Frontend state and actions (mockable adapter boundary)

struct AnatomicalDisplayedFrame: Equatable {
    let reference: AnatomicalAnnotationFrameReference
    /// Pixel dimensions of the displayed frame, used for aspect-fit layout
    /// and normalized-coordinate conversion.
    let pixelSize: CGSize
    /// Truthful description of where this frame came from.
    let sourceDescription: String
}

enum AnatomicalAnnotationPhase: Equatable {
    case idle
    case pending(AnatomicalAnnotationRequest)
    case applied(AnatomicalAnnotationProjectionResult)
    case rejected(AnatomicalAnnotationProjectionResult)

    var isPending: Bool {
        if case .pending = self { return true }
        return false
    }
}

struct AnatomicalAnnotationViewState: Equatable {
    let displayedFrame: AnatomicalDisplayedFrame?
    let phase: AnatomicalAnnotationPhase
}

struct AnatomicalAnnotationActionSet {
    let submitAnnotation: (AnatomicalAnnotationRequest) -> Void
    let clearAnnotation: () -> Void
}

@MainActor
protocol AnatomicalAnnotationControlling: AnyObject {
    var annotationViewState: AnatomicalAnnotationViewState { get }

    func submitAnnotation(_ request: AnatomicalAnnotationRequest)
    func clearAnnotation()
}

extension AnatomicalAnnotationActionSet {
    @MainActor
    static func forwarding(
        to controller: AnatomicalAnnotationControlling
    ) -> AnatomicalAnnotationActionSet {
        AnatomicalAnnotationActionSet(
            submitAnnotation: { [weak controller] request in
                controller?.submitAnnotation(request)
            },
            clearAnnotation: { [weak controller] in
                controller?.clearAnnotation()
            }
        )
    }

    static let inert = AnatomicalAnnotationActionSet(
        submitAnnotation: { _ in },
        clearAnnotation: {}
    )
}

// MARK: - Screen

enum AnatomicalAnnotationTool: String, CaseIterable, Identifiable {
    case point
    case circle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .point: "Point"
        case .circle: "Circle"
        }
    }
}

/// Experimental clinician screen for placing one point or one circle on a
/// selected anatomical target layer. The canvas marker for a pending request
/// is explicitly tentative; a snapped placement is only reported after an
/// applied projection result arrives.
struct AnatomicalLayerAnnotationScreen<DebugContent: View>: View {
    let state: AnatomicalAnnotationViewState
    let actions: AnatomicalAnnotationActionSet
    @ViewBuilder var debugContent: () -> DebugContent

    @State private var viewDepth: AnatomicalViewDepth = .surface
    @State private var annotateTarget: AnatomicalLayerTarget = .skin
    @State private var tool: AnatomicalAnnotationTool = .point
    @State private var circleRadius: Double = 0.08
    @State private var outsideImageMessageVisible = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        state: AnatomicalAnnotationViewState,
        actions: AnatomicalAnnotationActionSet,
        @ViewBuilder debugContent: @escaping () -> DebugContent
    ) {
        self.state = state
        self.actions = actions
        self.debugContent = debugContent
    }

    var body: some View {
        Form {
            statusSection
            canvasSection
            controlsSection
            resultSection
            debugContent()
            disclosureSection
        }
        .navigationTitle("Anatomical Layers")
        .sensoryFeedback(.success, trigger: appliedTrigger)
        .sensoryFeedback(.error, trigger: rejectedTrigger)
        .onChange(of: state.phase) { _, newPhase in
            announce(newPhase)
        }
    }

    // MARK: Sections

    private var statusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "Experimental — not verified on any physical device",
                    systemImage: "flask"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

                if let frame = state.displayedFrame {
                    Label(frame.sourceDescription, systemImage: "photo.badge.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Label(
                        "Live Apple Vision Pro view unavailable.",
                        systemImage: "video.slash"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var canvasSection: some View {
        Section {
            AnatomicalAnnotationCanvas(
                frame: state.displayedFrame,
                viewDepth: viewDepth,
                phase: state.phase,
                onTap: handleTap,
                onOutsideImageTouch: handleOutsideImageTouch
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 260, maxHeight: 420)
            .padding(.vertical, 4)

            if outsideImageMessageVisible {
                Label(
                    "That tap was outside the anatomical view and was ignored.",
                    systemImage: "hand.raised"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
        } header: {
            Text("Anatomical View")
        } footer: {
            Text(AnatomicalLayerProjectionFeature.disclosure)
                .font(.footnote.weight(.semibold))
        }
    }

    private var controlsSection: some View {
        Section {
            Picker("View Depth", selection: $viewDepth) {
                ForEach(AnatomicalViewDepth.allCases) { depth in
                    Text(depth.displayName).tag(depth)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("View depth: anatomical layer the patient would see")

            Picker("Annotate On", selection: $annotateTarget) {
                ForEach(AnatomicalLayerTarget.annotatableTargets, id: \.rawValue) { target in
                    Text(target.displayName).tag(target)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Annotate on: anatomical surface receiving the annotation")

            Picker("Tool", selection: $tool) {
                ForEach(AnatomicalAnnotationTool.allCases) { tool in
                    Text(tool.displayName).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Annotation tool")

            if tool == .circle {
                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: $circleRadius, in: 0.02...0.30) {
                        Text("Circle size")
                    } minimumValueLabel: {
                        Image(systemName: "circle")
                            .font(.caption2)
                    } maximumValueLabel: {
                        Image(systemName: "circle")
                            .font(.body)
                    }
                    .accessibilityValue(
                        "\(Int((circleRadius * 100).rounded())) percent of the view width"
                    )

                    Text("Circle size: \(Int((circleRadius * 100).rounded()))% of view width")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                submit(at: AnatomicalNormalizedScreenPoint(x: 0.5, y: 0.5))
            } label: {
                Label("Place at Center", systemImage: "plus.viewfinder")
            }
            .disabled(!canSubmit)
            .accessibilityHint(
                "Places the selected tool at the center of the anatomical view. Alternative to tapping the view."
            )
        } header: {
            Text("Controls")
        } footer: {
            Text(
                "View Depth changes this preview only in this build; it does not "
                    + "change any headset view. Annotate On selects the 3D surface "
                    + "that receives the annotation."
            )
        }
    }

    private var resultSection: some View {
        Section {
            switch state.phase {
            case .idle:
                Text(
                    state.displayedFrame == nil
                        ? "Annotation is unavailable without a displayed view."
                        : "No annotation. Tap the view or use Place at Center."
                )
                .foregroundStyle(.secondary)

            case .pending:
                HStack(spacing: 8) {
                    if reduceMotion {
                        Image(systemName: "hourglass")
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Waiting for the projection result…")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

            case .applied(let result):
                appliedSummary(result)

            case .rejected(let result):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Not placed", systemImage: "xmark.octagon.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    Text(
                        result.failureReason?.displayMessage
                            ?? "The annotation was rejected."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            Button(role: .destructive) {
                actions.clearAnnotation()
            } label: {
                Label("Clear Annotation", systemImage: "eraser")
            }
            .disabled(state.phase == .idle)
        } header: {
            Text("Annotation Status")
        }
    }

    @ViewBuilder
    private func appliedSummary(_ result: AnatomicalAnnotationProjectionResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                "Applied to \(result.targetLayer.displayName)",
                systemImage: "checkmark.circle.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.green)

            Text("Projection confidence \(Int((result.projectionConfidence * 100).rounded()))%")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let placement = result.placement {
                Text(placementDescription(placement))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var disclosureSection: some View {
        Section {
        } footer: {
            Text(
                "Experimental anatomical-layer annotation. Feature is off by "
                    + "default. No physical Apple Vision Pro behavior has been verified."
            )
        }
    }

    // MARK: Interaction

    private var canSubmit: Bool {
        state.displayedFrame != nil && !state.phase.isPending
    }

    private func handleTap(_ point: AnatomicalNormalizedScreenPoint) {
        outsideImageMessageVisible = false
        submit(at: point)
    }

    private func handleOutsideImageTouch() {
        outsideImageMessageVisible = true
        AccessibilityNotification.Announcement(
            "Tap ignored: outside the anatomical view."
        ).post()
    }

    private func submit(at point: AnatomicalNormalizedScreenPoint) {
        guard canSubmit, let frame = state.displayedFrame else { return }
        let geometry: AnatomicalAnnotationGeometry =
            switch tool {
            case .point:
                .point(at: point)
            case .circle:
                .circle(center: point, normalizedRadius: circleRadius)
            }
        let request = AnatomicalAnnotationRequest(
            annotationIdentifier: UUID(),
            frame: frame.reference,
            targetLayer: annotateTarget,
            geometry: geometry
        )
        actions.submitAnnotation(request)
    }

    private func placementDescription(
        _ placement: AnatomicalAnnotationLocalPlacement
    ) -> String {
        func millimetres(_ value: Double) -> String {
            "\(Int((value * 1000).rounded()))"
        }
        var text = "Forearm-local x \(millimetres(placement.forearmLocalPosition.x)), "
            + "y \(millimetres(placement.forearmLocalPosition.y)), "
            + "z \(millimetres(placement.forearmLocalPosition.z)) mm"
        if let radius = placement.forearmLocalRadiusMetres {
            text += " · radius \(millimetres(radius)) mm"
        }
        return text
    }

    private var appliedTrigger: UUID? {
        if case .applied(let result) = state.phase { return result.annotationIdentifier }
        return nil
    }

    private var rejectedTrigger: UUID? {
        if case .rejected(let result) = state.phase { return result.annotationIdentifier }
        return nil
    }

    private func announce(_ phase: AnatomicalAnnotationPhase) {
        switch phase {
        case .idle, .pending:
            break
        case .applied(let result):
            AccessibilityNotification.Announcement(
                "Annotation applied to \(result.targetLayer.displayName)."
            ).post()
        case .rejected(let result):
            AccessibilityNotification.Announcement(
                result.failureReason?.displayMessage ?? "Annotation rejected."
            ).post()
        }
    }
}

extension AnatomicalLayerAnnotationScreen where DebugContent == EmptyView {
    init(
        state: AnatomicalAnnotationViewState,
        actions: AnatomicalAnnotationActionSet
    ) {
        self.init(state: state, actions: actions, debugContent: { EmptyView() })
    }
}

// MARK: - Canvas

/// Aspect-fit canvas for the displayed frame. Touches are converted to
/// normalized image coordinates (top-left origin); touches in the letterbox
/// or outside the image are rejected, never clamped.
struct AnatomicalAnnotationCanvas: View {
    let frame: AnatomicalDisplayedFrame?
    let viewDepth: AnatomicalViewDepth
    let phase: AnatomicalAnnotationPhase
    let onTap: (AnatomicalNormalizedScreenPoint) -> Void
    let onOutsideImageTouch: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let container = geometry.size

            if let frame {
                let imageRect = Self.aspectFitRect(
                    content: frame.pixelSize,
                    in: container
                )

                ZStack {
                    Color(.systemGray6)

                    Canvas { context, _ in
                        drawSyntheticAnatomy(in: context, imageRect: imageRect)
                        drawMarker(in: context, imageRect: imageRect)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            handleTouch(at: value.location, imageRect: imageRect)
                        }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Anatomical view")
                .accessibilityValue(accessibilitySummary)
                .accessibilityHint(
                    "Shows an illustrative anatomical model. Use the Place at Center button to annotate without tapping."
                )
            } else {
                ContentUnavailableView {
                    Label("Live Apple Vision Pro view unavailable.", systemImage: "video.slash")
                } description: {
                    Text("Annotation requires a displayed view bound to a frame.")
                }
            }
        }
    }

    // MARK: Coordinate conversion

    static func aspectFitRect(content: CGSize, in container: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0,
              container.width > 0, container.height > 0
        else {
            return .zero
        }
        let scale = min(
            container.width / content.width,
            container.height / content.height
        )
        let size = CGSize(
            width: content.width * scale,
            height: content.height * scale
        )
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    static func normalizedPoint(
        for location: CGPoint,
        in imageRect: CGRect
    ) -> AnatomicalNormalizedScreenPoint? {
        guard imageRect.width > 0, imageRect.height > 0 else { return nil }
        let point = AnatomicalNormalizedScreenPoint(
            x: (location.x - imageRect.minX) / imageRect.width,
            y: (location.y - imageRect.minY) / imageRect.height
        )
        return point.isValid ? point : nil
    }

    private func handleTouch(at location: CGPoint, imageRect: CGRect) {
        guard let point = Self.normalizedPoint(for: location, in: imageRect) else {
            onOutsideImageTouch()
            return
        }
        onTap(point)
    }

    private func screenPoint(
        for normalized: AnatomicalNormalizedScreenPoint,
        in imageRect: CGRect
    ) -> CGPoint {
        CGPoint(
            x: imageRect.minX + normalized.x * imageRect.width,
            y: imageRect.minY + normalized.y * imageRect.height
        )
    }

    // MARK: Synthetic anatomy drawing

    /// Draws the deterministic generic forearm model through the same
    /// normalized mapping the orthographic ray provider uses, so drawn layers
    /// line up with projectable surfaces. Illustrative only.
    private func drawSyntheticAnatomy(in context: GraphicsContext, imageRect: CGRect) {
        context.fill(
            Path(roundedRect: imageRect, cornerRadius: 6),
            with: .color(Color(.systemGray5))
        )

        // Model spans: orthographic window 0.12 m wide; skin radius 0.05 m,
        // fat 0.044 m, muscle 0.037 m, bones at ±0.014 m (r 0.009/0.008 m).
        func band(halfWidthMetres: Double, centerXMetres: Double = 0) -> CGRect {
            let normalizedCenter = 0.5 + centerXMetres / 0.12
            let normalizedHalfWidth = halfWidthMetres / 0.12
            let x = imageRect.minX + (normalizedCenter - normalizedHalfWidth) * imageRect.width
            let width = normalizedHalfWidth * 2 * imageRect.width
            return CGRect(x: x, y: imageRect.minY, width: width, height: imageRect.height)
        }

        func fillBand(_ rect: CGRect, _ color: Color) {
            context.fill(
                Path(roundedRect: rect, cornerRadius: rect.width * 0.45),
                with: .color(color)
            )
        }

        let skin = band(halfWidthMetres: 0.050)
        let fat = band(halfWidthMetres: 0.044)
        let muscle = band(halfWidthMetres: 0.037)

        fillBand(skin, Color(red: 0.91, green: 0.72, blue: 0.60))

        if viewDepth != .surface {
            fillBand(fat, Color(red: 0.96, green: 0.85, blue: 0.45))
        }
        if viewDepth == .muscle || viewDepth == .bone {
            fillBand(muscle, Color(red: 0.79, green: 0.32, blue: 0.30))
        }
        if viewDepth == .bone {
            // Fixed light tone so bone reads as bone in light and dark mode.
            let boneColor = Color(white: 0.93)
            fillBand(band(halfWidthMetres: 0.009, centerXMetres: -0.014), boneColor)
            fillBand(band(halfWidthMetres: 0.008, centerXMetres: 0.014), boneColor)
        }

        context.stroke(
            Path(roundedRect: skin, cornerRadius: skin.width * 0.45),
            with: .color(Color(.systemGray)),
            lineWidth: 1
        )
    }

    // MARK: Marker drawing

    private func drawMarker(in context: GraphicsContext, imageRect: CGRect) {
        switch phase {
        case .idle:
            break

        case .pending(let request):
            drawGeometry(
                request.geometry,
                in: context,
                imageRect: imageRect,
                color: .orange,
                dashed: true
            )

        case .applied(let result):
            drawGeometry(
                result.sourceGeometry,
                in: context,
                imageRect: imageRect,
                color: .cyan,
                dashed: false
            )

        case .rejected(let result):
            let center = screenPoint(for: result.sourceGeometry.center, in: imageRect)
            var cross = Path()
            cross.move(to: CGPoint(x: center.x - 7, y: center.y - 7))
            cross.addLine(to: CGPoint(x: center.x + 7, y: center.y + 7))
            cross.move(to: CGPoint(x: center.x + 7, y: center.y - 7))
            cross.addLine(to: CGPoint(x: center.x - 7, y: center.y + 7))
            context.stroke(
                cross,
                with: .color(.red),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
        }
    }

    private func drawGeometry(
        _ geometry: AnatomicalAnnotationGeometry,
        in context: GraphicsContext,
        imageRect: CGRect,
        color: Color,
        dashed: Bool
    ) {
        let center = screenPoint(for: geometry.center, in: imageRect)
        let style = StrokeStyle(
            lineWidth: 2.5,
            lineCap: .round,
            dash: dashed ? [5, 4] : []
        )

        switch geometry.kind {
        case .point:
            if dashed {
                context.stroke(
                    Path(ellipseIn: CGRect(
                        x: center.x - 8, y: center.y - 8, width: 16, height: 16
                    )),
                    with: .color(color),
                    style: style
                )
            } else {
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: center.x - 6, y: center.y - 6, width: 12, height: 12
                    )),
                    with: .color(color)
                )
                context.stroke(
                    Path(ellipseIn: CGRect(
                        x: center.x - 10, y: center.y - 10, width: 20, height: 20
                    )),
                    with: .color(color),
                    lineWidth: 1.5
                )
            }

        case .circle:
            let radius = (geometry.normalizedRadius ?? 0) * imageRect.width
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )),
                with: .color(color),
                style: style
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - 3, y: center.y - 3, width: 6, height: 6
                )),
                with: .color(color)
            )
        }
    }

    private var accessibilitySummary: String {
        var parts = ["Illustrative anatomical model, \(viewDepth.displayName) depth"]
        switch phase {
        case .idle:
            parts.append("No annotation")
        case .pending:
            parts.append("Annotation pending projection")
        case .applied(let result):
            parts.append("Annotation applied to \(result.targetLayer.displayName)")
        case .rejected:
            parts.append("Annotation rejected")
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - DEBUG preview session and experimental host

#if DEBUG
/// Frontend-only mock session. Resolves requests against the deterministic
/// DEBUG projector and generic nested forearm model, so applied and rejected
/// results are genuine algorithm outputs — never a simulated physical AVP.
@MainActor
final class AnatomicalAnnotationPreviewSession: ObservableObject, AnatomicalAnnotationControlling {
    enum FrameMode: String, CaseIterable, Identifiable {
        case unavailable
        case synthetic

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .unavailable: "Unavailable"
            case .synthetic: "Synthetic frame"
            }
        }
    }

    enum ForcedOutcome: Hashable, Identifiable {
        case automatic
        case reject(AnatomicalProjectionFailureReason)

        var id: String {
            switch self {
            case .automatic: "automatic"
            case .reject(let reason): reason.rawValue
            }
        }

        var displayName: String {
            switch self {
            case .automatic: "Auto (project on model)"
            case .reject(let reason): "Reject: \(reason.rawValue)"
            }
        }

        /// Local list because the contract enum is deliberately not
        /// CaseIterable. Every typed failure reason is represented.
        static let allChoices: [Self] = [.automatic] + rejectionReasons.map { .reject($0) }

        private static let rejectionReasons: [AnatomicalProjectionFailureReason] = [
            .featureDisabled, .invalidRequest, .frameMismatch, .staleFrame,
            .trackingUnavailable, .trackingNotLive, .insufficientTrackingConfidence,
            .invalidRay, .unsupportedTargetLayer, .surfaceUnavailable,
            .missedSurface, .insufficientProjectionConfidence
        ]
    }

    @Published private(set) var annotationViewState: AnatomicalAnnotationViewState

    @Published var frameMode: FrameMode = .unavailable {
        didSet { refreshFrame() }
    }
    @Published var freezeFrame = false
    @Published var forcedOutcome: ForcedOutcome = .automatic

    private let resultDelaySeconds: Double
    private var frameCounter = 0
    private var frameLoopTask: Task<Void, Never>?
    private var resolutionTask: Task<Void, Never>?

    /// Preview-only policy: identical thresholds to production, feature
    /// enabled so the DEBUG projector can run. Production policy is untouched.
    private let previewPolicy = AnatomicalProjectionPolicy(
        featureEnabled: true,
        minimumTrackingConfidence: 0.8,
        minimumProjectionConfidence: 0.8,
        maximumFrameAgeSeconds: 0.25
    )

    private let rayProvider = AnatomicalOrthographicScreenRayProvider(
        horizontalSpanMetres: 0.12,
        verticalSpanMetres: 0.28,
        cameraDepthMetres: 0.12,
        confidence: 1
    )

    init(
        frameMode: FrameMode = .unavailable,
        resultDelaySeconds: Double = 0.5
    ) {
        self.resultDelaySeconds = resultDelaySeconds
        annotationViewState = AnatomicalAnnotationViewState(
            displayedFrame: nil,
            phase: .idle
        )
        self.frameMode = frameMode
        refreshFrame()
        startFrameLoop()
    }

    // MARK: AnatomicalAnnotationControlling

    func submitAnnotation(_ request: AnatomicalAnnotationRequest) {
        guard !annotationViewState.phase.isPending,
              annotationViewState.displayedFrame != nil
        else { return }

        annotationViewState = AnatomicalAnnotationViewState(
            displayedFrame: annotationViewState.displayedFrame,
            phase: .pending(request)
        )

        let delay = resultDelaySeconds
        resolutionTask?.cancel()
        resolutionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.resolve(request)
        }
    }

    func clearAnnotation() {
        resolutionTask?.cancel()
        annotationViewState = AnatomicalAnnotationViewState(
            displayedFrame: annotationViewState.displayedFrame,
            phase: .idle
        )
    }

    // MARK: Resolution

    private func resolve(_ request: AnatomicalAnnotationRequest) {
        guard case .pending(let pending) = annotationViewState.phase,
              pending.annotationIdentifier == request.annotationIdentifier
        else { return }

        let result: AnatomicalAnnotationProjectionResult
        switch forcedOutcome {
        case .reject(let reason):
            result = AnatomicalAnnotationProjectionResult(
                annotationIdentifier: request.annotationIdentifier,
                frame: request.frame,
                targetLayer: request.targetLayer,
                sourceGeometry: request.geometry,
                state: .rejected,
                projectionConfidence: 0,
                failureReason: reason,
                placement: nil
            )

        case .automatic:
            // The mock evaluates at a simulated receipt time just after
            // capture. If the frame was frozen, the request is genuinely
            // older than the freshness policy and fails as staleFrame.
            let receiptTime = freezeFrame
                ? Date()
                : request.frame.capturedAt.addingTimeInterval(0.05)
            result = AnatomicalSurfaceProjector(policy: previewPolicy).project(
                request,
                context: AnatomicalProjectionContext(
                    currentFrame: request.frame,
                    trackingState: .live,
                    trackingConfidence: 1
                ),
                rayProvider: rayProvider,
                surfaces: GenericNestedForearmSurfaceModel.preview,
                now: receiptTime
            )
        }

        annotationViewState = AnatomicalAnnotationViewState(
            displayedFrame: annotationViewState.displayedFrame,
            phase: result.state == .applied ? .applied(result) : .rejected(result)
        )
    }

    // MARK: Frame lifecycle

    private func startFrameLoop() {
        frameLoopTask?.cancel()
        frameLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                self?.advanceFrameIfNeeded()
            }
        }
    }

    private func advanceFrameIfNeeded() {
        guard frameMode == .synthetic, !freezeFrame else { return }
        refreshFrame()
    }

    private func refreshFrame() {
        switch frameMode {
        case .unavailable:
            annotationViewState = AnatomicalAnnotationViewState(
                displayedFrame: nil,
                phase: .idle
            )
        case .synthetic:
            frameCounter += 1
            let frame = AnatomicalDisplayedFrame(
                reference: AnatomicalAnnotationFrameReference(
                    identifier: "synthetic-\(frameCounter)",
                    capturedAt: Date()
                ),
                pixelSize: CGSize(width: 120, height: 280),
                sourceDescription: "Synthetic test frame — not a live Apple Vision Pro view"
            )
            annotationViewState = AnatomicalAnnotationViewState(
                displayedFrame: frame,
                phase: annotationViewState.phase
            )
        }
    }
}

/// DEBUG-only host wiring the experimental screen to the preview session,
/// plus simulation controls for exercising rejected flows.
struct AnatomicalLayerExperimentalHost: View {
    @StateObject private var session = AnatomicalAnnotationPreviewSession()

    var body: some View {
        AnatomicalLayerAnnotationScreen(
            state: session.annotationViewState,
            actions: .forwarding(to: session)
        ) {
            Section {
                Picker("Frame source", selection: $session.frameMode) {
                    ForEach(AnatomicalAnnotationPreviewSession.FrameMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Toggle("Freeze frame (forces stale rejection)", isOn: $session.freezeFrame)

                Picker("Outcome", selection: $session.forcedOutcome) {
                    ForEach(AnatomicalAnnotationPreviewSession.ForcedOutcome.allChoices) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
            } header: {
                Text("Simulation (Debug Build Only)")
            } footer: {
                Text(
                    "These controls drive the frontend mock. They do not "
                        + "communicate with any device."
                )
            }
        }
    }
}

// MARK: - Previews

#Preview("Unavailable") {
    NavigationStack {
        AnatomicalLayerAnnotationScreen(
            state: AnatomicalAnnotationViewState(displayedFrame: nil, phase: .idle),
            actions: .inert
        )
    }
}

#Preview("Interactive host") {
    NavigationStack {
        AnatomicalLayerExperimentalHost()
    }
}

#Preview("Rejected — missed surface") {
    let frame = AnatomicalDisplayedFrame(
        reference: AnatomicalAnnotationFrameReference(
            identifier: "preview-frame",
            capturedAt: Date()
        ),
        pixelSize: CGSize(width: 120, height: 280),
        sourceDescription: "Synthetic test frame — not a live Apple Vision Pro view"
    )
    let request = AnatomicalAnnotationRequest(
        annotationIdentifier: UUID(),
        frame: frame.reference,
        targetLayer: .bone,
        geometry: .point(at: AnatomicalNormalizedScreenPoint(x: 0.08, y: 0.4))
    )
    return NavigationStack {
        AnatomicalLayerAnnotationScreen(
            state: AnatomicalAnnotationViewState(
                displayedFrame: frame,
                phase: .rejected(
                    AnatomicalAnnotationProjectionResult(
                        annotationIdentifier: request.annotationIdentifier,
                        frame: frame.reference,
                        targetLayer: .bone,
                        sourceGeometry: request.geometry,
                        state: .rejected,
                        projectionConfidence: 0,
                        failureReason: .missedSurface,
                        placement: nil
                    )
                )
            ),
            actions: .inert
        )
    }
}
#endif
