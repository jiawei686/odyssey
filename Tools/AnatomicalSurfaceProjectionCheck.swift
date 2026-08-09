import Foundation
import simd

@main
enum AnatomicalSurfaceProjectionCheck {
    private static let frame = AnatomicalAnnotationFrameReference(
        identifier: "projection-frame",
        capturedAt: Date(timeIntervalSinceReferenceDate: 1_000)
    )
    private static let policy = AnatomicalProjectionPolicy(
        featureEnabled: true,
        minimumTrackingConfidence: 0.8,
        minimumProjectionConfidence: 0.8,
        maximumFrameAgeSeconds: 0.25
    )
    private static let surfaces = GenericNestedForearmSurfaceModel.preview
    private static let provider = AnatomicalOrthographicScreenRayProvider(
        horizontalSpanMetres: 0.12,
        verticalSpanMetres: 0.28,
        cameraDepthMetres: 0.12,
        confidence: 0.95
    )

    static func main() throws {
        try pointAndCircleSnapToTheSelectedSurface()
        try layerSelectionUsesDistinctNestedSurfaces()
        try missedSurfaceIsRejected()
        try staleInvalidAndLowConfidenceTrackingAreRejected()
        try frameMismatchAndLowProjectionConfidenceAreRejected()
        try defaultFeatureFlagFailsClosed()
        try floatingNeverEstimatesDepth()
        print("Anatomical-surface projection checks passed")
    }

    private static func pointAndCircleSnapToTheSelectedSurface() throws {
        let point = project(
            request(target: .muscle, geometry: .point(at: .init(x: 0.5, y: 0.45)))
        )
        try require(point.state == .applied, "point must snap to a selected live surface")
        try require(point.targetLayer == .muscle, "point must preserve selected layer")
        try require(point.placement?.forearmLocalRadiusMetres == nil, "point has no radius")
        try require(
            approximatelyEqual(point.placement?.forearmLocalPosition.z, surfaces.muscleRadiusMetres),
            "point must intersect the muscle surface, not an arbitrary depth"
        )

        let circle = project(
            request(
                target: .skin,
                geometry: .circle(center: .init(x: 0.5, y: 0.55), normalizedRadius: 0.08)
            )
        )
        try require(circle.state == .applied, "circle must snap to a selected live surface")
        try require(
            (circle.placement?.forearmLocalRadiusMetres ?? 0) > 0,
            "circle must carry a projected local radius"
        )
        try require(
            circle.placement?.forearmLocalSurfaceNormal.z ?? 0 > 0,
            "front-facing surface normal must be returned in forearm-local space"
        )
    }

    private static func layerSelectionUsesDistinctNestedSurfaces() throws {
        let geometry = AnatomicalAnnotationGeometry.point(at: .init(x: 0.5, y: 0.5))
        let skin = project(request(target: .skin, geometry: geometry))
        let fat = project(request(target: .subcutaneousFat, geometry: geometry))
        let muscle = project(request(target: .muscle, geometry: geometry))
        let skinZ = try positionZ(skin)
        let fatZ = try positionZ(fat)
        let muscleZ = try positionZ(muscle)
        try require(
            skinZ > fatZ && fatZ > muscleZ,
            "skin, fat, and muscle must resolve to their selected nested surfaces"
        )

        let radiusScreenX = 0.5 + surfaces.radiusBoneOffsetMetres / provider.horizontalSpanMetres
        let bone = project(
            request(
                target: .bone,
                geometry: .point(at: .init(x: radiusScreenX, y: 0.5))
            )
        )
        try require(bone.state == .applied, "bone ray must hit the simplified radius")
        try require(
            approximatelyEqual(
                bone.placement?.forearmLocalPosition.z,
                surfaces.radiusBoneRadiusMetres
            ),
            "bone selection must project to a bone surface"
        )
    }

    private static func missedSurfaceIsRejected() throws {
        let tallProvider = AnatomicalOrthographicScreenRayProvider(
            horizontalSpanMetres: 0.12,
            verticalSpanMetres: 0.50,
            cameraDepthMetres: 0.12,
            confidence: 1
        )
        let result = AnatomicalSurfaceProjector(policy: policy).project(
            request(target: .skin, geometry: .point(at: .init(x: 0.5, y: 0))),
            context: liveContext,
            rayProvider: tallProvider,
            surfaces: surfaces,
            now: frame.capturedAt
        )
        try require(result.state == .rejected, "a ray beyond finite forearm length must reject")
        try require(result.failureReason == .missedSurface, "surface miss reason must be explicit")
        try require(result.placement == nil, "surface miss must never fabricate depth")
    }

    private static func staleInvalidAndLowConfidenceTrackingAreRejected() throws {
        let source = request(target: .skin, geometry: .point(at: .init(x: 0.5, y: 0.5)))
        for trackingState in [
            AnatomicalProjectionTrackingState.stale,
            .failed,
            .unavailable
        ] {
            let result = AnatomicalSurfaceProjector(policy: policy).project(
                source,
                context: AnatomicalProjectionContext(
                    currentFrame: frame,
                    trackingState: trackingState,
                    trackingConfidence: 1
                ),
                rayProvider: provider,
                surfaces: surfaces,
                now: frame.capturedAt
            )
            try require(result.state == .rejected, "non-live tracking must reject")
            try require(result.placement == nil, "non-live tracking must not estimate placement")
        }

        let lowConfidence = AnatomicalSurfaceProjector(policy: policy).project(
            source,
            context: AnatomicalProjectionContext(
                currentFrame: frame,
                trackingState: .live,
                trackingConfidence: 0.79
            ),
            rayProvider: provider,
            surfaces: surfaces,
            now: frame.capturedAt
        )
        try require(
            lowConfidence.failureReason == .insufficientTrackingConfidence,
            "low tracking confidence must reject explicitly"
        )

        let staleFrame = AnatomicalSurfaceProjector(policy: policy).project(
            source,
            context: liveContext,
            rayProvider: provider,
            surfaces: surfaces,
            now: frame.capturedAt.addingTimeInterval(0.251)
        )
        try require(staleFrame.failureReason == .staleFrame, "stale frame must reject")
    }

    private static func frameMismatchAndLowProjectionConfidenceAreRejected() throws {
        let source = request(target: .skin, geometry: .point(at: .init(x: 0.5, y: 0.5)))
        let mismatch = AnatomicalSurfaceProjector(policy: policy).project(
            source,
            context: AnatomicalProjectionContext(
                currentFrame: .init(identifier: "new-frame", capturedAt: frame.capturedAt),
                trackingState: .live,
                trackingConfidence: 1
            ),
            rayProvider: provider,
            surfaces: surfaces,
            now: frame.capturedAt
        )
        try require(mismatch.failureReason == .frameMismatch, "frame mismatch must reject")

        let weakProvider = AnatomicalOrthographicScreenRayProvider(
            horizontalSpanMetres: 0.12,
            verticalSpanMetres: 0.28,
            cameraDepthMetres: 0.12,
            confidence: 0.79
        )
        let lowProjection = AnatomicalSurfaceProjector(policy: policy).project(
            source,
            context: liveContext,
            rayProvider: weakProvider,
            surfaces: surfaces,
            now: frame.capturedAt
        )
        try require(
            lowProjection.failureReason == .insufficientProjectionConfidence,
            "low ray/surface confidence must reject"
        )
        try require(lowProjection.placement == nil, "low confidence must not estimate depth")
    }

    private static func defaultFeatureFlagFailsClosed() throws {
        let result = AnatomicalSurfaceProjector().project(
            request(target: .skin, geometry: .point(at: .init(x: 0.5, y: 0.5))),
            context: liveContext,
            rayProvider: provider,
            surfaces: surfaces,
            now: frame.capturedAt
        )
        try require(result.failureReason == .featureDisabled, "default feature flag must reject")
    }

    private static func floatingNeverEstimatesDepth() throws {
        let result = project(
            request(target: .floating, geometry: .point(at: .init(x: 0.5, y: 0.5)))
        )
        try require(
            result.failureReason == .unsupportedTargetLayer,
            "floating compatibility target must be explicitly non-projectable"
        )
        try require(result.placement == nil, "floating must never guess depth")
    }

    private static var liveContext: AnatomicalProjectionContext {
        AnatomicalProjectionContext(
            currentFrame: frame,
            trackingState: .live,
            trackingConfidence: 0.96
        )
    }

    private static func request(
        target: AnatomicalLayerTarget,
        geometry: AnatomicalAnnotationGeometry
    ) -> AnatomicalAnnotationRequest {
        AnatomicalAnnotationRequest(
            annotationIdentifier: UUID(),
            frame: frame,
            targetLayer: target,
            geometry: geometry
        )
    }

    private static func project(
        _ request: AnatomicalAnnotationRequest
    ) -> AnatomicalAnnotationProjectionResult {
        AnatomicalSurfaceProjector(policy: policy).project(
            request,
            context: liveContext,
            rayProvider: provider,
            surfaces: surfaces,
            now: frame.capturedAt
        )
    }

    private static func positionZ(
        _ result: AnatomicalAnnotationProjectionResult
    ) throws -> Double {
        guard result.state == .applied,
              let z = result.placement?.forearmLocalPosition.z
        else {
            throw CheckFailure(message: "expected applied projection")
        }
        return z
    }

    private static func approximatelyEqual(
        _ lhs: Double?,
        _ rhs: Double,
        tolerance: Double = 0.000_001
    ) -> Bool {
        guard let lhs else { return false }
        return abs(lhs - rhs) <= tolerance
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message: message) }
    }
}

private struct CheckFailure: Error {
    let message: String
}
