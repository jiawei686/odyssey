import Foundation
import simd

struct AnatomicalProjectionRay: Equatable, Sendable {
    let origin: SIMD3<Double>
    let direction: SIMD3<Double>

    init?(origin: SIMD3<Double>, direction: SIMD3<Double>) {
        guard origin.allFinite, direction.allFinite else { return nil }
        let length = simd_length(direction)
        guard length.isFinite, length > 0.000_001 else { return nil }
        self.origin = origin
        self.direction = direction / length
    }
}

struct AnatomicalScreenRaySample: Equatable, Sendable {
    let ray: AnatomicalProjectionRay
    let confidence: Double

    var isValid: Bool {
        confidence.isFinite && (0 ... 1).contains(confidence)
    }
}

protocol AnatomicalScreenRayProviding: Sendable {
    func ray(
        for screenPoint: AnatomicalNormalizedScreenPoint,
        in frame: AnatomicalAnnotationFrameReference
    ) -> AnatomicalScreenRaySample?
}

struct AnatomicalSurfaceIntersection: Equatable, Sendable {
    let targetLayer: AnatomicalLayerTarget
    let forearmLocalPosition: SIMD3<Double>
    let forearmLocalSurfaceNormal: SIMD3<Double>
    let confidence: Double

    var isValid: Bool {
        targetLayer != .floating &&
            forearmLocalPosition.allFinite &&
            forearmLocalSurfaceNormal.allFinite &&
            abs(simd_length(forearmLocalSurfaceNormal) - 1) < 0.001 &&
            confidence.isFinite &&
            (0 ... 1).contains(confidence)
    }
}

protocol AnatomicalLayerSurfaceProjecting: Sendable {
    func firstIntersection(
        of ray: AnatomicalProjectionRay,
        with targetLayer: AnatomicalLayerTarget
    ) -> AnatomicalSurfaceIntersection?
}

enum AnatomicalProjectionTrackingState: String, Equatable, Sendable {
    case live
    case stale
    case unavailable
    case failed
}

struct AnatomicalProjectionContext: Equatable, Sendable {
    let currentFrame: AnatomicalAnnotationFrameReference
    let trackingState: AnatomicalProjectionTrackingState
    let trackingConfidence: Double

    var isValid: Bool {
        currentFrame.isValid &&
            trackingConfidence.isFinite &&
            (0 ... 1).contains(trackingConfidence)
    }
}

struct AnatomicalProjectionPolicy: Equatable, Sendable {
    let featureEnabled: Bool
    let minimumTrackingConfidence: Double
    let minimumProjectionConfidence: Double
    let maximumFrameAgeSeconds: TimeInterval

    static let production = Self(
        featureEnabled: AnatomicalLayerProjectionFeature.isEnabledByDefault,
        minimumTrackingConfidence: 0.8,
        minimumProjectionConfidence: 0.8,
        maximumFrameAgeSeconds: 0.25
    )
}

struct AnatomicalSurfaceProjector: Sendable {
    let policy: AnatomicalProjectionPolicy

    init(policy: AnatomicalProjectionPolicy = .production) {
        self.policy = policy
    }

    func project(
        _ request: AnatomicalAnnotationRequest,
        context: AnatomicalProjectionContext,
        rayProvider: any AnatomicalScreenRayProviding,
        surfaces: any AnatomicalLayerSurfaceProjecting,
        now: Date
    ) -> AnatomicalAnnotationProjectionResult {
        guard policy.featureEnabled else {
            return rejected(request, .featureDisabled)
        }
        guard request.isValid, context.isValid else {
            return rejected(request, .invalidRequest)
        }
        guard request.frame.identifier == context.currentFrame.identifier else {
            return rejected(request, .frameMismatch)
        }
        let requestAge = now.timeIntervalSince(request.frame.capturedAt)
        let contextAge = now.timeIntervalSince(context.currentFrame.capturedAt)
        guard requestAge >= -0.05,
              contextAge >= -0.05,
              requestAge <= policy.maximumFrameAgeSeconds,
              contextAge <= policy.maximumFrameAgeSeconds
        else {
            return rejected(request, .staleFrame)
        }

        switch context.trackingState {
        case .live:
            break
        case .stale, .failed:
            return rejected(request, .trackingNotLive)
        case .unavailable:
            return rejected(request, .trackingUnavailable)
        }

        guard context.trackingConfidence >= policy.minimumTrackingConfidence else {
            return rejected(request, .insufficientTrackingConfidence)
        }
        guard request.targetLayer != .floating else {
            return rejected(request, .unsupportedTargetLayer)
        }
        guard let centerRay = rayProvider.ray(for: request.geometry.center, in: request.frame),
              centerRay.isValid
        else {
            return rejected(request, .invalidRay)
        }
        guard let centerHit = surfaces.firstIntersection(
            of: centerRay.ray,
            with: request.targetLayer
        ) else {
            return rejected(request, .missedSurface)
        }
        guard centerHit.isValid, centerHit.targetLayer == request.targetLayer else {
            return rejected(request, .surfaceUnavailable)
        }

        var projectionConfidence = min(
            context.trackingConfidence,
            centerRay.confidence,
            centerHit.confidence
        )
        var localRadiusMetres: Double?

        if request.geometry.kind == .circle {
            guard let normalizedRadius = request.geometry.normalizedRadius,
                  let edgePoint = circleEdgePoint(
                      center: request.geometry.center,
                      normalizedRadius: normalizedRadius
                  ),
                  let edgeRay = rayProvider.ray(for: edgePoint, in: request.frame),
                  edgeRay.isValid,
                  let edgeHit = surfaces.firstIntersection(
                      of: edgeRay.ray,
                      with: request.targetLayer
                  ),
                  edgeHit.isValid,
                  edgeHit.targetLayer == request.targetLayer
            else {
                return rejected(request, .missedSurface)
            }
            projectionConfidence = min(
                projectionConfidence,
                edgeRay.confidence,
                edgeHit.confidence
            )
            let radius = simd_distance(
                centerHit.forearmLocalPosition,
                edgeHit.forearmLocalPosition
            )
            guard radius.isFinite, radius > 0.000_001 else {
                return rejected(request, .missedSurface)
            }
            localRadiusMetres = radius
        }

        guard projectionConfidence >= policy.minimumProjectionConfidence else {
            return rejected(
                request,
                .insufficientProjectionConfidence,
                confidence: projectionConfidence
            )
        }

        return AnatomicalAnnotationProjectionResult(
            annotationIdentifier: request.annotationIdentifier,
            frame: request.frame,
            targetLayer: request.targetLayer,
            sourceGeometry: request.geometry,
            state: .applied,
            projectionConfidence: projectionConfidence,
            failureReason: nil,
            placement: AnatomicalAnnotationLocalPlacement(
                forearmLocalPosition: .init(centerHit.forearmLocalPosition),
                forearmLocalSurfaceNormal: .init(centerHit.forearmLocalSurfaceNormal),
                forearmLocalRadiusMetres: localRadiusMetres
            )
        )
    }

    private func circleEdgePoint(
        center: AnatomicalNormalizedScreenPoint,
        normalizedRadius: Double
    ) -> AnatomicalNormalizedScreenPoint? {
        let right = AnatomicalNormalizedScreenPoint(
            x: center.x + normalizedRadius,
            y: center.y
        )
        if right.isValid { return right }
        let left = AnatomicalNormalizedScreenPoint(
            x: center.x - normalizedRadius,
            y: center.y
        )
        return left.isValid ? left : nil
    }

    private func rejected(
        _ request: AnatomicalAnnotationRequest,
        _ reason: AnatomicalProjectionFailureReason,
        confidence: Double = 0
    ) -> AnatomicalAnnotationProjectionResult {
        AnatomicalAnnotationProjectionResult(
            annotationIdentifier: request.annotationIdentifier,
            frame: request.frame,
            targetLayer: request.targetLayer,
            sourceGeometry: request.geometry,
            state: .rejected,
            projectionConfidence: min(max(confidence, 0), 1),
            failureReason: reason,
            placement: nil
        )
    }
}

#if DEBUG
struct GenericNestedForearmSurfaceModel: AnatomicalLayerSurfaceProjecting, Equatable, Sendable {
    static let coordinateRootIdentifier = "GenericForearmCoordinateRoot"

    let lengthMetres: Double
    let skinRadiusMetres: Double
    let fatRadiusMetres: Double
    let muscleRadiusMetres: Double
    let radiusBoneOffsetMetres: Double
    let ulnaBoneOffsetMetres: Double
    let radiusBoneRadiusMetres: Double
    let ulnaBoneRadiusMetres: Double

    static let preview = Self(
        lengthMetres: 0.28,
        skinRadiusMetres: 0.050,
        fatRadiusMetres: 0.044,
        muscleRadiusMetres: 0.037,
        radiusBoneOffsetMetres: -0.014,
        ulnaBoneOffsetMetres: 0.014,
        radiusBoneRadiusMetres: 0.009,
        ulnaBoneRadiusMetres: 0.008
    )

    func firstIntersection(
        of ray: AnatomicalProjectionRay,
        with targetLayer: AnatomicalLayerTarget
    ) -> AnatomicalSurfaceIntersection? {
        switch targetLayer {
        case .skin:
            return cylinderIntersection(
                ray: ray,
                layer: .skin,
                centerX: 0,
                radius: skinRadiusMetres
            )
        case .subcutaneousFat:
            return cylinderIntersection(
                ray: ray,
                layer: .subcutaneousFat,
                centerX: 0,
                radius: fatRadiusMetres
            )
        case .muscle:
            return cylinderIntersection(
                ray: ray,
                layer: .muscle,
                centerX: 0,
                radius: muscleRadiusMetres
            )
        case .bone:
            let hits = [
                cylinderIntersection(
                    ray: ray,
                    layer: .bone,
                    centerX: radiusBoneOffsetMetres,
                    radius: radiusBoneRadiusMetres
                ),
                cylinderIntersection(
                    ray: ray,
                    layer: .bone,
                    centerX: ulnaBoneOffsetMetres,
                    radius: ulnaBoneRadiusMetres
                )
            ].compactMap { $0 }
            return hits.min {
                simd_distance(ray.origin, $0.forearmLocalPosition) <
                    simd_distance(ray.origin, $1.forearmLocalPosition)
            }
        case .floating:
            return nil
        }
    }

    private func cylinderIntersection(
        ray: AnatomicalProjectionRay,
        layer: AnatomicalLayerTarget,
        centerX: Double,
        radius: Double
    ) -> AnatomicalSurfaceIntersection? {
        let relativeX = ray.origin.x - centerX
        let a = ray.direction.x * ray.direction.x + ray.direction.z * ray.direction.z
        guard a > 0.000_000_001 else { return nil }
        let b = 2 * (relativeX * ray.direction.x + ray.origin.z * ray.direction.z)
        let c = relativeX * relativeX + ray.origin.z * ray.origin.z - radius * radius
        let discriminant = b * b - 4 * a * c
        guard discriminant >= 0 else { return nil }

        let root = discriminant.squareRoot()
        let candidates = [(-b - root) / (2 * a), (-b + root) / (2 * a)]
            .filter { $0 > 0.000_001 }
            .sorted()
        let halfLength = lengthMetres / 2

        for distance in candidates {
            let position = ray.origin + distance * ray.direction
            guard (-halfLength ... halfLength).contains(position.y) else { continue }
            let radial = SIMD3<Double>(position.x - centerX, 0, position.z)
            let radialLength = simd_length(radial)
            guard radialLength > 0.000_001 else { continue }
            return AnatomicalSurfaceIntersection(
                targetLayer: layer,
                forearmLocalPosition: position,
                forearmLocalSurfaceNormal: radial / radialLength,
                confidence: 1
            )
        }
        return nil
    }
}

struct AnatomicalOrthographicScreenRayProvider: AnatomicalScreenRayProviding, Equatable, Sendable {
    let horizontalSpanMetres: Double
    let verticalSpanMetres: Double
    let cameraDepthMetres: Double
    let confidence: Double

    func ray(
        for screenPoint: AnatomicalNormalizedScreenPoint,
        in frame: AnatomicalAnnotationFrameReference
    ) -> AnatomicalScreenRaySample? {
        guard screenPoint.isValid,
              frame.isValid,
              horizontalSpanMetres.isFinite,
              verticalSpanMetres.isFinite,
              cameraDepthMetres.isFinite,
              horizontalSpanMetres > 0,
              verticalSpanMetres > 0,
              cameraDepthMetres > 0,
              confidence.isFinite,
              (0 ... 1).contains(confidence),
              let ray = AnatomicalProjectionRay(
                  origin: SIMD3<Double>(
                      (screenPoint.x - 0.5) * horizontalSpanMetres,
                      (0.5 - screenPoint.y) * verticalSpanMetres,
                      cameraDepthMetres
                  ),
                  direction: SIMD3<Double>(0, 0, -1)
              )
        else {
            return nil
        }
        return AnatomicalScreenRaySample(ray: ray, confidence: confidence)
    }
}
#endif

private extension SIMD3 where Scalar == Double {
    var allFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}

private extension AnatomicalProjectionVector3 {
    init(_ vector: SIMD3<Double>) {
        self.init(x: vector.x, y: vector.y, z: vector.z)
    }
}
