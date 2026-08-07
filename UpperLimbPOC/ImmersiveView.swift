import SwiftUI
import RealityKit
import CoreGraphics

struct ImmersiveView: View {
    @EnvironmentObject private var overlay: OverlayState
    @EnvironmentObject private var peer: PeerSession
    @EnvironmentObject private var tracking: LandmarkTrackingService

    private let localElbow = SIMD3<Float>(0, 0, 0.205)
    private let referenceForearmLength: Float = 0.2625
    private let sectionRootName = "ReferenceSectionRoot"

    var body: some View {
        RealityView { content in
            do {
                guard let assetName = overlay.selectedRegion.assetName else {
                    return
                }
                let model = try await Entity(named: assetName)
                model.name = "BoneOverlayRoot"
                let sectionRoot = await makeReferenceSectionRoot(
                    sliceCount: overlay.sliceCount
                )
                model.addChild(sectionRoot)
                applyTransform(to: model)
                applyOpacity(effectiveOpacity, to: model)
                applySectionState(to: sectionRoot)
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
            if let sectionRoot = model.findEntity(named: sectionRootName) {
                applySectionState(to: sectionRoot)
            }
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
        guard entity.name != sectionRootName else { return }

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

    private var effectiveSectionOpacity: Float {
        let requested = Float(overlay.sectionOpacity)
        guard overlay.trackingEnabled,
              tracking.isAvailableOnDevice,
              !tracking.isTracking else {
            return requested
        }
        return min(requested, 0.12)
    }

    private func applySectionState(to root: Entity) {
        root.isEnabled = overlay.sectionVisible
        guard overlay.sectionVisible else { return }

        let selectedName = "ReferenceSectionSlice-\(overlay.selectedSliceIndex)"
        for child in root.children {
            let isSelected = child.name == selectedName
            child.isEnabled = isSelected

            guard isSelected,
                  var component = child.components[ModelComponent.self]
            else { continue }

            component.materials = component.materials.map { source in
                guard var material = source as? UnlitMaterial else {
                    return source
                }
                material.blending = .transparent(
                    opacity: .init(floatLiteral: effectiveSectionOpacity)
                )
                material.faceCulling = .none
                return material
            }
            child.components.set(component)
        }
    }

    private func makeReferenceSectionRoot(sliceCount: Int) async -> Entity {
        let root = Entity()
        root.name = sectionRootName

        for index in 0..<sliceCount {
            let progress = sliceCount > 1
                ? Float(index) / Float(sliceCount - 1)
                : 0
            let material: UnlitMaterial
            let resourceName = String(
                format: "reference-forearm-%02d",
                index + 1
            )
            if let texture = try? await TextureResource(named: resourceName) {
                material = UnlitMaterial(texture: texture)
            } else if let fallbackImage = makeReferenceSectionImage(
                index: index,
                sliceCount: sliceCount
            ), let fallbackTexture = try? await TextureResource(
                   image: fallbackImage,
                   withName: "procedural-reference-section-fallback-\(index)",
                   options: .init(semantic: .color)
               ) {
                material = UnlitMaterial(texture: fallbackTexture)
            } else {
                material = UnlitMaterial(color: .orange)
            }

            let slice = ModelEntity(
                mesh: .generatePlane(width: 0.105, depth: 0.150),
                materials: [material]
            )
            slice.name = "ReferenceSectionSlice-\(index)"
            slice.position.z = localElbow.z - (referenceForearmLength * progress)
            slice.orientation = simd_quatf(
                angle: .pi / 2,
                axis: SIMD3<Float>(1, 0, 0)
            )
            slice.isEnabled = index == overlay.selectedSliceIndex
            root.addChild(slice)
        }

        return root
    }

    private func makeReferenceSectionImage(
        index: Int,
        sliceCount: Int
    ) -> CGImage? {
        let dimension = 256
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: dimension,
            height: dimension,
            bitsPerComponent: 8,
            bytesPerRow: dimension * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let progress = sliceCount > 1
            ? CGFloat(index) / CGFloat(sliceCount - 1)
            : 0
        let bodyWidth = 176 + (sin(progress * .pi) * 28)
        let bodyHeight = 148 + (sin(progress * .pi) * 34)
        let bodyRect = CGRect(
            x: (256 - bodyWidth) / 2,
            y: (256 - bodyHeight) / 2,
            width: bodyWidth,
            height: bodyHeight
        )

        context.clear(CGRect(x: 0, y: 0, width: 256, height: 256))
        context.setFillColor(CGColor(
            red: 0.03,
            green: 0.05,
            blue: 0.07,
            alpha: 0.92
        ))
        context.fillEllipse(in: bodyRect)

        context.setStrokeColor(CGColor(
            red: 0.42,
            green: 0.78,
            blue: 0.84,
            alpha: 0.88
        ))
        context.setLineWidth(5)
        context.strokeEllipse(in: bodyRect.insetBy(dx: 5, dy: 5))

        context.setStrokeColor(CGColor(
            red: 0.35,
            green: 0.43,
            blue: 0.48,
            alpha: 0.75
        ))
        context.setLineWidth(3)
        context.strokeEllipse(in: bodyRect.insetBy(dx: 27, dy: 24))

        let separation = 34 + (progress * 13)
        let boneSize = 34 - (sin(progress * .pi) * 7)
        for xOffset in [-separation, separation] {
            let boneRect = CGRect(
                x: 128 + xOffset - (boneSize / 2),
                y: 128 - (boneSize / 2),
                width: boneSize,
                height: boneSize * 0.86
            )
            context.setFillColor(CGColor(
                red: 0.86,
                green: 0.90,
                blue: 0.91,
                alpha: 0.96
            ))
            context.fillEllipse(in: boneRect)
            context.setStrokeColor(CGColor(
                red: 1.0,
                green: 0.62,
                blue: 0.16,
                alpha: 1.0
            ))
            context.setLineWidth(4)
            context.strokeEllipse(in: boneRect)
        }

        context.setStrokeColor(CGColor(
            red: 1.0,
            green: 0.62,
            blue: 0.16,
            alpha: 0.82
        ))
        context.setLineWidth(2)
        context.move(to: CGPoint(x: 128, y: 18))
        context.addLine(to: CGPoint(x: 128, y: 238))
        context.move(to: CGPoint(x: 18, y: 128))
        context.addLine(to: CGPoint(x: 238, y: 128))
        context.strokePath()

        return context.makeImage()
    }
}
