#if DEBUG
import Foundation
import OSLog
import simd

enum ClinicalTwinLabFeatureGate {
    static let launchArgument = "--odyssey-clinical-twin"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
}

enum ClinicalTwinRendererPhase: Equatable {
    case idle
    case loading
    case staticReady(ClinicalTwinRenderEvidence)
    case failed(String)
}

struct ClinicalTwinRenderEvidence: Equatable {
    let softTissueTriangles: Int
    let pairedBoneATriangles: Int
    let pairedBoneBTriangles: Int
    let buildMilliseconds: Double
}

@MainActor
final class ClinicalTwinLabState: ObservableObject {
    @Published private(set) var rendererPhase: ClinicalTwinRendererPhase = .idle
    @Published private(set) var currentPresentation: ClinicalTwinPresentation?
    @Published private(set) var trackingRequested = false
    @Published var revealAnatomy = 0.0

    private var presentationResolver = ClinicalTwinPresentationResolver()
    private let logger = Logger(
        subsystem: "com.marcel.UpperLimbPOC",
        category: "ClinicalTwin"
    )

    var canAttachToRightForearm: Bool {
        if case .staticReady = rendererPhase { return !trackingRequested }
        return false
    }

    func beginStaticSession() {
        guard rendererPhase == .idle else { return }
        rendererPhase = .loading
        logger.notice("route=ctDerivedMeshFallback state=loading-static-reference")
    }

    func markStaticReady(_ evidence: ClinicalTwinRenderEvidence) {
        rendererPhase = .staticReady(evidence)
        logger.notice(
            "route=ctDerivedMeshFallback state=static-ready softTriangles=\(evidence.softTissueTriangles) boneATriangles=\(evidence.pairedBoneATriangles) boneBTriangles=\(evidence.pairedBoneBTriangles) buildMs=\(evidence.buildMilliseconds, format: .fixed(precision: 1))"
        )
    }

    func markRendererFailed(_ detail: String) {
        rendererPhase = .failed(detail)
        currentPresentation = nil
        logger.error("route=ctDerivedMeshFallback state=failed detail=\(detail, privacy: .public)")
    }

    func requestRightForearmTracking() {
        guard canAttachToRightForearm else { return }
        trackingRequested = true
        logger.notice("tracking=right-only state=requested")
    }

    func resolvePresentation(
        resolution: AVPForearmOverlayResolution,
        wristTransform: simd_float4x4?,
        timestamp: Double
    ) -> ClinicalTwinPresentation {
        let presentation = presentationResolver.resolve(
            resolution: resolution,
            wristTransform: wristTransform,
            timestamp: timestamp
        )
        if currentPresentation?.mode != presentation.mode
            || currentPresentation?.statusTitle != presentation.statusTitle {
            logger.notice(
                "tracking=right-only state=\(presentation.mode.rawValue, privacy: .public) status=\(presentation.statusTitle, privacy: .public)"
            )
        }
        if currentPresentation != presentation {
            currentPresentation = presentation
        }
        return presentation
    }

    func reset() {
        rendererPhase = .idle
        currentPresentation = nil
        trackingRequested = false
        revealAnatomy = 0
        presentationResolver = ClinicalTwinPresentationResolver()
        logger.notice("state=reset")
    }
}
#endif
