import SwiftUI
import RealityKit
import CoreGraphics

struct ImmersiveView: View {
    @EnvironmentObject private var overlay: OverlayState
    @EnvironmentObject private var peer: PeerSession
    @EnvironmentObject private var tracking: LandmarkTrackingService
    @State private var accessibilityActivateSubscription: EventSubscription?
    @State private var manipulationUpdateSubscription: EventSubscription?
    @State private var manipulationEndSubscription: EventSubscription?

    private let localElbow = SIMD3<Float>(0, 0, 0.205)
    private let referenceForearmLength: Float = 0.2625
    private let sectionRootName = "ReferenceSectionRoot"

    var body: some View {
        RealityView { content in
            overlay.setOverlayLoadError(nil)
            do {
                guard let assetName = overlay.selectedRegion.assetName else {
                    overlay.setOverlayLoadError("No 3D model is available for this region.")
                    return
                }
                let model = try await Entity(named: assetName)
                model.name = "BoneOverlayRoot"
                configureBoneHitTargets(in: model)
                if #available(visionOS 26.0, *) {
                    ManipulationComponent.configureEntity(model)
                    setManualManipulation(
                        enabled: !overlay.trackingEnabled && !overlay.locked,
                        on: model
                    )
                }
                let sectionRoot = await makeReferenceSectionRoot(
                    sliceCount: overlay.sliceCount
                )
                model.addChild(sectionRoot)
                applyTransform(to: model)
                applyAppearance(effectiveOpacity, tint: overlay.tint, to: model)
                applySectionState(to: sectionRoot)
                content.add(model)
                accessibilityActivateSubscription = content.subscribe(
                    to: AccessibilityEvents.Activate.self
                ) { event in
                    overlay.focusBone(
                        entityName: semanticEntityName(from: event.entity)
                    )
                }
                if #available(visionOS 26.0, *) {
                    manipulationEndSubscription = content.subscribe(
                        to: ManipulationEvents.WillEnd.self,
                        on: model
                    ) { event in
                        guard !overlay.trackingEnabled,
                              !overlay.locked else { return }
                        Task { @MainActor in
                            overlay.captureManualPlacement(
                                position: event.entity.position,
                                entityScale: event.entity.scale
                            )
                            peer.send(overlay.snapshot)
                        }
                    }
                    manipulationUpdateSubscription = content.subscribe(
                        to: ManipulationEvents.DidUpdateTransform.self,
                        on: model
                    ) { event in
                        guard !overlay.trackingEnabled,
                              !overlay.locked else { return }
                        let measuredScale = (
                            abs(event.entity.scale.x)
                            + abs(event.entity.scale.y)
                            + abs(event.entity.scale.z)
                        ) / 3
                        let uniformScale = min(max(measuredScale, 0.50), 1.50)
                        event.entity.scale = overlay.selectedRegion.isLeft
                            ? SIMD3<Float>(-uniformScale, uniformScale, uniformScale)
                            : SIMD3<Float>(repeating: uniformScale)
                    }
                }
            } catch {
                overlay.setOverlayLoadError(
                    "Could not load \(overlay.selectedRegion.name). Return to the library or retry."
                )
            }
        } update: { content in
            guard let model = content.entities.first(where: {
                $0.name == "BoneOverlayRoot"
            }) else { return }

            applyTransform(to: model)
            applyAppearance(effectiveOpacity, tint: overlay.tint, to: model)
            if #available(visionOS 26.0, *) {
                setManualManipulation(
                    enabled: !overlay.trackingEnabled && !overlay.locked,
                    on: model
                )
            }
            if let sectionRoot = model.findEntity(named: sectionRootName) {
                applySectionState(to: sectionRoot)
            }
        }
        .id(overlay.overlayLoadRevision)
        .onAppear(perform: peer.start)
        .onReceive(peer.$lastSnapshot.compactMap { $0 }) { snapshot in
            overlay.applyCalibration(snapshot)
        }
        .onChange(of: peer.isConnected) { _, isConnected in
            guard isConnected else { return }
            peer.send(overlay.snapshot)
        }
        .onChange(of: overlay.trackingEnabled) { _, isEnabled in
            if isEnabled {
                Task { await tracking.start() }
            } else {
                tracking.stop()
            }
        }
        .gesture(
            TapGesture(count: 2)
                .targetedToAnyEntity()
                .exclusively(
                    before: TapGesture(count: 1).targetedToAnyEntity()
                )
                .onEnded { result in
                    switch result {
                    case .first:
                        overlay.cycleImagingMode()
                        peer.send(overlay.snapshot)
                    case .second(let value):
                        overlay.focusBone(
                            entityName: semanticEntityName(from: value.entity)
                        )
                    }
                }
        )
        .task {
            guard overlay.trackingEnabled else { return }
            await tracking.start()
        }
        .onDisappear {
            tracking.stop()
        }
    }

    @available(visionOS 26.0, *)
    private func setManualManipulation(enabled: Bool, on model: Entity) {
        guard enabled else {
            model.components.remove(ManipulationComponent.self)
            return
        }
        var component = ManipulationComponent()
        var dynamics = component.dynamics
        dynamics.translationBehavior = .unconstrained
        dynamics.scalingBehavior = .unconstrained
        dynamics.primaryRotationBehavior = .none
        dynamics.secondaryRotationBehavior = .none
        dynamics.inertia = .low
        component.dynamics = dynamics
        component.releaseBehavior = .stay
        model.components.set(component)
    }

    private func semanticEntityName(from entity: Entity) -> String? {
        var candidate: Entity? = entity
        while let current = candidate, current.name != "BoneOverlayRoot" {
            if !current.name.isEmpty, !current.name.hasPrefix("mesh_") {
                return current.name
            }
            candidate = current.parent
        }
        return nil
    }

    private func configureBoneHitTargets(in entity: Entity) {
        if entity.components[ModelComponent.self] != nil {
            entity.generateCollisionShapes(recursive: false)
            entity.components.set(InputTargetComponent())
            entity.components.set(HoverEffectComponent())
            var accessibility = AccessibilityComponent()
            accessibility.isAccessibilityElement = true
            accessibility.label = LocalizedStringResource(
                stringLiteral: accessibleBoneLabel(
                    for: semanticEntityName(from: entity) ?? entity.name
                )
            )
            accessibility.systemActions = [.activate]
            entity.components.set(accessibility)
        }

        for child in entity.children {
            configureBoneHitTargets(in: child)
        }
    }

    private func accessibleBoneLabel(for entityName: String) -> String {
        entityName
            .replacingOccurrences(of: "_r", with: "")
            .replacingOccurrences(of: "_l", with: "")
            .replacingOccurrences(of: "_", with: " ")
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
              tracking.fit != nil,
              !tracking.isTracking else {
            return requested
        }
        return min(requested, 0.18)
    }

    private func applyAppearance(
        _ opacity: Float,
        tint: OverlayTint,
        to entity: Entity
    ) {
        guard entity.name != sectionRootName else { return }

        let rgb = tint.rgb

        if var modelComponent = entity.components[ModelComponent.self] {
            modelComponent.materials = modelComponent.materials.map { source in
                if var material = source as? PhysicallyBasedMaterial {
                    material.baseColor.tint = .init(
                        red: rgb.red,
                        green: rgb.green,
                        blue: rgb.blue,
                        alpha: 1.0
                    )
                    material.opacityThreshold = nil
                    material.blending = .transparent(
                        opacity: .init(floatLiteral: opacity)
                    )
                    return material
                }

                var material = PhysicallyBasedMaterial()
                material.baseColor = .init(
                    tint: .init(
                        red: rgb.red,
                        green: rgb.green,
                        blue: rgb.blue,
                        alpha: 1.0
                    )
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
            applyAppearance(opacity, tint: tint, to: child)
        }
    }

    private var effectiveSectionOpacity: Float {
        let requested = Float(overlay.sectionOpacity)
        guard overlay.trackingEnabled,
              tracking.fit != nil,
              !tracking.isTracking else {
            return requested
        }
        return min(requested, 0.12)
    }

    private func applySectionState(to root: Entity) {
        root.isEnabled = overlay.sectionVisible
        guard overlay.sectionVisible else { return }

        let selectedName = "ReferenceSectionSlice-\(overlay.selectedSliceIndex)"
        let sectionZ = localElbow.z - (
            referenceForearmLength * Float(overlay.normalizedSlicePosition)
        )
        for child in root.children {
            let isSelected = child.name == selectedName
            child.isEnabled = isSelected

            if isSelected {
                child.position = SIMD3<Float>(0, 0, sectionZ)
            }

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
        var usedSyntheticFallback = false

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
                usedSyntheticFallback = true
                material = UnlitMaterial(texture: fallbackTexture)
            } else {
                usedSyntheticFallback = true
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

        overlay.setSectionSourceStatus(
            usedSyntheticFallback ? .syntheticFallback : .referenceTextures
        )

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
