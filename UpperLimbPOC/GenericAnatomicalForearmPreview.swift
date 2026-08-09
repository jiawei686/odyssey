#if DEBUG
import SwiftUI

struct GenericAnatomicalForearmPreviewModel: Sendable {
    struct Node: Identifiable, Sendable {
        let id: String
        let coordinateRootIdentifier: String
        let label: String
        let targetLayer: AnatomicalLayerTarget
    }

    let coordinateRootIdentifier = GenericNestedForearmSurfaceModel.coordinateRootIdentifier
    let nodes: [Node]
    let snappedPoint: AnatomicalAnnotationProjectionResult
    let snappedCircle: AnatomicalAnnotationProjectionResult

    init() {
        nodes = [
            Node(id: "skin-shell", coordinateRootIdentifier: coordinateRootIdentifier, label: "Skin shell", targetLayer: .skin),
            Node(id: "fat-shell", coordinateRootIdentifier: coordinateRootIdentifier, label: "Fat shell", targetLayer: .subcutaneousFat),
            Node(id: "muscle-volume", coordinateRootIdentifier: coordinateRootIdentifier, label: "Muscle volume", targetLayer: .muscle),
            Node(id: "radius", coordinateRootIdentifier: coordinateRootIdentifier, label: "Radius", targetLayer: .bone),
            Node(id: "ulna", coordinateRootIdentifier: coordinateRootIdentifier, label: "Ulna", targetLayer: .bone)
        ]

        let frame = AnatomicalAnnotationFrameReference(
            identifier: "preview-frame",
            capturedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
        let context = AnatomicalProjectionContext(
            currentFrame: frame,
            trackingState: .live,
            trackingConfidence: 1
        )
        let projector = AnatomicalSurfaceProjector(
            policy: AnatomicalProjectionPolicy(
                featureEnabled: true,
                minimumTrackingConfidence: 0.8,
                minimumProjectionConfidence: 0.8,
                maximumFrameAgeSeconds: 0.25
            )
        )
        let rayProvider = AnatomicalOrthographicScreenRayProvider(
            horizontalSpanMetres: 0.12,
            verticalSpanMetres: 0.28,
            cameraDepthMetres: 0.12,
            confidence: 1
        )
        let surfaces = GenericNestedForearmSurfaceModel.preview
        let now = frame.capturedAt

        snappedPoint = projector.project(
            AnatomicalAnnotationRequest(
                annotationIdentifier: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                frame: frame,
                targetLayer: .muscle,
                geometry: .point(at: .init(x: 0.5, y: 0.42))
            ),
            context: context,
            rayProvider: rayProvider,
            surfaces: surfaces,
            now: now
        )
        snappedCircle = projector.project(
            AnatomicalAnnotationRequest(
                annotationIdentifier: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
                frame: frame,
                targetLayer: .skin,
                geometry: .circle(center: .init(x: 0.5, y: 0.62), normalizedRadius: 0.08)
            ),
            context: context,
            rayProvider: rayProvider,
            surfaces: surfaces,
            now: now
        )
    }
}

struct GenericAnatomicalForearmPreview: View {
    private let model = GenericAnatomicalForearmPreviewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Anatomical-layer projection preview")
                .font(.title2.bold())
            Text(AnatomicalLayerProjectionFeature.disclosure)
                .font(.callout)
                .foregroundStyle(.secondary)

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                drawLayer(in: context, center: center, size: size, inset: 0, color: .pink.opacity(0.30))
                drawLayer(in: context, center: center, size: size, inset: 18, color: .yellow.opacity(0.35))
                drawLayer(in: context, center: center, size: size, inset: 36, color: .red.opacity(0.38))
                drawBone(in: context, center: center, xOffset: -15, size: size)
                drawBone(in: context, center: center, xOffset: 15, size: size)
                drawAnnotations(in: context, size: size)
            }
            .frame(minHeight: 360)
            .accessibilityLabel("Generic nested forearm model with one snapped point and one snapped circle")

            Text("Preview only • Feature flag OFF in production")
                .font(.footnote.weight(.semibold))
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 500)
    }

    private func drawLayer(
        in context: GraphicsContext,
        center: CGPoint,
        size: CGSize,
        inset: CGFloat,
        color: Color
    ) {
        let rect = CGRect(
            x: center.x - 70 + inset / 2,
            y: 24 + inset,
            width: 140 - inset,
            height: size.height - 48 - inset * 2
        )
        context.fill(Path(roundedRect: rect, cornerRadius: 55), with: .color(color))
    }

    private func drawBone(
        in context: GraphicsContext,
        center: CGPoint,
        xOffset: CGFloat,
        size: CGSize
    ) {
        let rect = CGRect(
            x: center.x + xOffset - 7,
            y: 80,
            width: 14,
            height: size.height - 160
        )
        context.fill(Path(roundedRect: rect, cornerRadius: 7), with: .color(.white.opacity(0.9)))
    }

    private func drawAnnotations(in context: GraphicsContext, size: CGSize) {
        if model.snappedPoint.state == .applied {
            let point = CGPoint(x: size.width / 2, y: size.height * 0.42)
            context.fill(Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)), with: .color(.cyan))
        }
        if model.snappedCircle.state == .applied {
            let center = CGPoint(x: size.width / 2, y: size.height * 0.62)
            context.stroke(Path(ellipseIn: CGRect(x: center.x - 28, y: center.y - 28, width: 56, height: 56)), with: .color(.mint), lineWidth: 5)
        }
    }
}

#Preview("Generic anatomical layers") {
    GenericAnatomicalForearmPreview()
}
#endif
