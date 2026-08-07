import ARKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import simd

@MainActor
final class LandmarkTrackingService: ObservableObject {
    struct ForearmFit {
        let elbowPosition: SIMD3<Float>
        let wristPosition: SIMD3<Float>
        let rotation: simd_quatf
        let scale: Float
    }

    enum Phase: Equatable {
        case idle
        case simulatorUnavailable
        case unsupported
        case authorizationDenied
        case searching
        case partial
        case tracking
        case invalidDistance
        case failed(String)

        var message: String {
            switch self {
            case .idle: "Tracking is idle"
            case .simulatorUnavailable: "Marker tracking requires a physical Apple Vision Pro"
            case .unsupported: "Image tracking is unavailable on this device"
            case .authorizationDenied: "World-sensing permission was denied"
            case .searching: "Show both ELBOW and WRIST markers"
            case .partial: "One marker found — show both markers"
            case .tracking: "Elbow and wrist locked"
            case .invalidDistance: "Markers are outside the expected forearm distance"
            case .failed(let reason): "Tracking failed: \(reason)"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var fit: ForearmFit?
    @Published private(set) var isTracking = false
    @Published private(set) var isAvailableOnDevice = false

    private let session = ARKitSession()
    private var provider: ImageTrackingProvider?
    private var updateTask: Task<Void, Never>?
    private var elbowTransform: simd_float4x4?
    private var wristTransform: simd_float4x4?

    private let referenceForearmLength: Float = 0.2625
    private let smoothingFactor: Float = 0.24

    func start() async {
        guard updateTask == nil else { return }

#if targetEnvironment(simulator)
        phase = .simulatorUnavailable
        isAvailableOnDevice = false
        return
#endif

        guard ImageTrackingProvider.isSupported else {
            phase = .unsupported
            isAvailableOnDevice = false
            return
        }

        do {
            let referenceImages = try loadReferenceImages()
            let authorizationTypes = ImageTrackingProvider.requiredAuthorizations
            let authorization = await session.requestAuthorization(for: authorizationTypes)

            guard !authorization.values.contains(.denied) else {
                phase = .authorizationDenied
                isAvailableOnDevice = false
                return
            }

            let provider = ImageTrackingProvider(referenceImages: referenceImages)
            self.provider = provider
            try await session.run([provider])

            phase = .searching
            isAvailableOnDevice = true

            updateTask = Task { [weak self] in
                for await update in provider.anchorUpdates {
                    guard !Task.isCancelled else { break }
                    self?.consume(update.anchor)
                }
            }
        } catch {
            phase = .failed(error.localizedDescription)
            isAvailableOnDevice = false
        }
    }

    func stop() {
        updateTask?.cancel()
        updateTask = nil
        session.stop()
        provider = nil
        elbowTransform = nil
        wristTransform = nil
        fit = nil
        isTracking = false
        isAvailableOnDevice = false
        phase = .idle
    }

    private func consume(_ anchor: ImageAnchor) {
        guard let name = anchor.referenceImage.name?.lowercased() else { return }
        let transform = anchor.isTracked ? anchor.originFromAnchorTransform : nil

        if name.contains("elbow") {
            elbowTransform = transform
        } else if name.contains("wrist") {
            wristTransform = transform
        }

        updateFit()
    }

    private func updateFit() {
        guard let elbowTransform, let wristTransform else {
            isTracking = false
            phase = elbowTransform != nil || wristTransform != nil ? .partial : .searching
            return
        }

        let elbow = translation(of: elbowTransform)
        let wrist = translation(of: wristTransform)
        let offset = wrist - elbow
        let distance = simd_length(offset)

        guard (0.12...0.45).contains(distance) else {
            isTracking = false
            phase = .invalidDistance
            return
        }

        let direction = simd_normalize(offset)
        let rotation = fittedRotation(
            direction: direction,
            elbowTransform: elbowTransform,
            wristTransform: wristTransform
        )
        let rawFit = ForearmFit(
            elbowPosition: elbow,
            wristPosition: wrist,
            rotation: rotation,
            scale: distance / referenceForearmLength
        )

        if let previous = fit {
            fit = ForearmFit(
                elbowPosition: simd_mix(
                    previous.elbowPosition,
                    rawFit.elbowPosition,
                    SIMD3<Float>(repeating: smoothingFactor)
                ),
                wristPosition: simd_mix(
                    previous.wristPosition,
                    rawFit.wristPosition,
                    SIMD3<Float>(repeating: smoothingFactor)
                ),
                rotation: simd_slerp(previous.rotation, rawFit.rotation, smoothingFactor),
                scale: previous.scale + ((rawFit.scale - previous.scale) * smoothingFactor)
            )
        } else {
            fit = rawFit
        }

        isTracking = true
        phase = .tracking
    }

    private func translation(of transform: simd_float4x4) -> SIMD3<Float> {
        SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
    }

    private func fittedRotation(
        direction: SIMD3<Float>,
        elbowTransform: simd_float4x4,
        wristTransform: simd_float4x4
    ) -> simd_quatf {
        var elbowNormal = simd_normalize(SIMD3<Float>(
            elbowTransform.columns.2.x,
            elbowTransform.columns.2.y,
            elbowTransform.columns.2.z
        ))
        var wristNormal = simd_normalize(SIMD3<Float>(
            wristTransform.columns.2.x,
            wristTransform.columns.2.y,
            wristTransform.columns.2.z
        ))

        if simd_dot(elbowNormal, wristNormal) < 0 {
            wristNormal *= -1
        }

        var surfaceNormal = elbowNormal + wristNormal
        surfaceNormal -= direction * simd_dot(surfaceNormal, direction)

        if simd_length_squared(surfaceNormal) < 0.0001 {
            elbowNormal = abs(direction.y) < 0.9
                ? SIMD3<Float>(0, 1, 0)
                : SIMD3<Float>(1, 0, 0)
            surfaceNormal = elbowNormal - direction * simd_dot(elbowNormal, direction)
        }

        let worldY = simd_normalize(surfaceNormal)
        let worldZ = -direction
        let worldX = simd_normalize(simd_cross(worldY, worldZ))
        let correctedWorldY = simd_normalize(simd_cross(worldZ, worldX))
        let basis = simd_float3x3(columns: (worldX, correctedWorldY, worldZ))
        return simd_quatf(basis)
    }

    private func loadReferenceImages() throws -> [ReferenceImage] {
        try ["elbow-marker", "wrist-marker"].map { resourceName in
            guard let url = Bundle.main.url(
                forResource: resourceName,
                withExtension: "png"
            ), let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw MarkerError.missingResource(resourceName)
            }

            var reference = ReferenceImage(
                cgimage: image,
                physicalSize: CGSize(width: 0.08, height: 0.08)
            )
            reference.name = resourceName
            return reference
        }
    }
}

private enum MarkerError: LocalizedError {
    case missingResource(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            "Missing marker resource: \(name).png"
        }
    }
}
