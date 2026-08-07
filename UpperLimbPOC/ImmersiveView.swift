import SwiftUI
import RealityKit

struct ImmersiveView: View {
    @EnvironmentObject private var overlay: OverlayState
    @EnvironmentObject private var peer: PeerSession
    @EnvironmentObject private var tracking: LandmarkTrackingService

    private let localElbow = SIMD3<Float>(0, 0, 0.205)

    var body: some View {
        RealityView { content in
            do {
                guard let assetName = overlay.selectedRegion.assetName else {
                    return
                }
                let model = try await Entity(named: assetName)
                model.name = "BoneOverlayRoot"
                applyTransform(to: model)
                applyOpacity(effectiveOpacity, to: model)
                content.add(model)
            } catch {
                print("Could not load \(overlay.selectedRegion.name): \(error)")
            }
        } update: { content in
            guard let model = content.entities.first(where: {
                $0.name == "BoneOverlayRoot"
            }) else { return }

            applyTransform(to: model)
            applyOpacity(effectiveOpacity, to: model)
        }
        .onAppear(perform: peer.start)
        .onReceive(peer.$lastSnapshot.compactMap { $0 }) { snapshot in
            overlay.applyCalibration(snapshot)
        }
        .task {
            guard overlay.trackingEnabled else { return }
            await tracking.start()
        }
        .onDisappear {
            tracking.stop()
        }
    }

    private func applyTransform(to model: Entity) {
        if overlay.trackingEnabled, let fit = tracking.fit {
            applyTrackedTransform(fit, to: model)
            return
        }

        applyManualTransform(to: model)
    }

    private func applyTrackedTransform(
        _ fit: LandmarkTrackingService.ForearmFit,
        to model: Entity
    ) {
        let pitchOffset = overlay.pitchDegrees + 90.0
        let pitch = simd_quatf(
            angle: Float(pitchOffset * .pi / 180),
            axis: SIMD3<Float>(1, 0, 0)
        )
        let yaw = simd_quatf(
            angle: Float(overlay.yawDegrees * .pi / 180),
            axis: SIMD3<Float>(0, 1, 0)
        )
        let roll = simd_quatf(
            angle: Float(overlay.rollDegrees * .pi / 180),
            axis: SIMD3<Float>(0, 0, 1)
        )

        let rotation = fit.rotation * yaw * pitch * roll
        let uniformScale = fit.scale * Float(overlay.scale)
        let regionScale = overlay.selectedRegion.isLeft
            ? SIMD3<Float>(-uniformScale, uniformScale, uniformScale)
            : SIMD3<Float>(repeating: uniformScale)
        let manualOffset = SIMD3<Float>(
            Float(overlay.x),
            Float(overlay.y + 0.15),
            Float(overlay.z + 0.70)
        )
        let elbowOffset = rotation.act(localElbow * uniformScale)

        model.transform = Transform(
            scale: regionScale,
            rotation: rotation,
            translation: fit.elbowPosition - elbowOffset + manualOffset
        )
    }

    private func applyManualTransform(to model: Entity) {
        let pitch = simd_quatf(
            angle: Float(overlay.pitchDegrees * .pi / 180),
            axis: SIMD3<Float>(1, 0, 0)
        )
        let yaw = simd_quatf(
            angle: Float(overlay.yawDegrees * .pi / 180),
            axis: SIMD3<Float>(0, 1, 0)
        )
        let roll = simd_quatf(
            angle: Float(overlay.rollDegrees * .pi / 180),
            axis: SIMD3<Float>(0, 0, 1)
        )

        let scale = Float(overlay.scale)
        let regionScale = overlay.selectedRegion.isLeft
            ? SIMD3<Float>(-scale, scale, scale)
            : SIMD3<Float>(repeating: scale)

        model.transform = Transform(
            scale: regionScale,
            rotation: yaw * pitch * roll,
            translation: SIMD3<Float>(
                Float(overlay.x),
                Float(overlay.y),
                Float(overlay.z)
            )
        )
    }

    private var effectiveOpacity: Float {
        let requested = Float(overlay.opacity)
        guard overlay.trackingEnabled,
              tracking.isAvailableOnDevice,
              !tracking.isTracking else {
            return requested
        }
        return min(requested, 0.18)
    }

    private func applyOpacity(_ opacity: Float, to entity: Entity) {
        if var modelComponent = entity.components[ModelComponent.self] {
            modelComponent.materials = modelComponent.materials.map { source in
                if var material = source as? PhysicallyBasedMaterial {
                    material.opacityThreshold = nil
                    material.blending = .transparent(
                        opacity: .init(floatLiteral: opacity)
                    )
                    return material
                }

                var material = PhysicallyBasedMaterial()
                material.baseColor = .init(
                    tint: .init(red: 0.25, green: 0.95, blue: 1.0, alpha: 1.0)
                )
                material.roughness = .init(floatLiteral: 0.45)
                material.blending = .transparent(
                    opacity: .init(floatLiteral: opacity)
                )
                return material
            }
            entity.components.set(modelComponent)
        }

        for child in entity.children {
            applyOpacity(opacity, to: child)
        }
    }
}
