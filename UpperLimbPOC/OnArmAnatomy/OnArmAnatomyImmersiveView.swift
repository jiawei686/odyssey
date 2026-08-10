#if DEBUG
import RealityKit
import SwiftUI

struct OnArmAnatomyImmersiveView: View {
    @EnvironmentObject private var tracking: LandmarkTrackingService
    @EnvironmentObject private var labState: OnArmAnatomyLabState

    var body: some View {
        RealityView { content in
            labState.beginAssetLoad()
            do {
                let loaded = try await OnArmAnatomyRealityKitFactory.loadRoot()
                content.add(loaded.root)
                labState.markAssetReady(loaded.evidence)
            } catch {
                labState.markAssetFailed(error.localizedDescription)
            }
        } update: { content in
            guard let root = content.entities.first(where: {
                $0.name == OnArmAnatomyRealityKitFactory.rootName
            }) else { return }

            let presentation = labState.resolvePresentation(
                resolution: tracking.rightForearmResolution,
                wristTransform: tracking.rightHandJointTransforms[.wrist],
                timestamp: ProcessInfo.processInfo.systemUptime
            )
            root.transform = Transform(
                scale: presentation.transform.scale,
                rotation: presentation.transform.rotation,
                translation: presentation.transform.translation
            )
            root.isEnabled = presentation.isVisible
            OnArmAnatomyRealityKitFactory.setVisibleScope(
                on: root,
                showFullAsset: presentation.showFullAsset,
                opacity: presentation.opacity
            )
        }
    }
}
#endif
